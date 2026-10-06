-- Funds: named reserves outside the month/bucket model.
--   bank  — holds money; can be activated so its name appears as a
--           "category" when logging entries. Entries with fund_flow='out'
--           draw from the bank balance and bypass both buckets.
--   piggy — savings goal: deposits track progress toward goal_cents.
-- Deposits (fund_flow='in') are regular bucket entries that also credit
-- the fund — the bucket pays at deposit time, the fund pays at spend time.
-- Deleting a fund can optionally move its balance into the open month's
-- extra_income atomically via delete_fund().

create type public.fund_kind as enum ('bank', 'piggy');

create table public.funds (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  kind public.fund_kind not null,
  name text not null,
  goal_cents bigint check (goal_cents is null or goal_cents > 0),
  -- banks: spendable when active; piggies can still be deposited to.
  active boolean not null default true,
  -- piggies: set when the goal was used/reached.
  achieved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, id),
  unique (user_id, kind, name),
  check ((kind = 'piggy') = (goal_cents is not null)),
  check (kind = 'piggy' or achieved_at is null)
);

alter table public.funds enable row level security;

-- Deletes go only through delete_fund() so the balance-transfer decision is
-- always made in one atomic call; no delete policy on purpose.
create policy own_rows_select on public.funds for select to authenticated
  using ((select auth.uid()) = user_id);
create policy own_rows_insert on public.funds for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy own_rows_update on public.funds for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- entries: link to a fund. fund_flow='in' = deposit (bucket entry that
-- credits the fund); 'out' = bank spend (bypasses buckets, debits the
-- fund). category_id becomes nullable for 'out' entries only.
-- ---------------------------------------------------------------------

alter table public.entries alter column category_id drop not null;
alter table public.entries add column fund_id uuid;
alter table public.entries add column fund_flow text;

-- Shapes: normal entry (no fund link, has category) / deposit ('in',
-- has category) / bank spend ('out', no category). After a fund delete
-- the FK nulls only fund_id, so 'in'/'out' rows may dangle — that's the
-- tombstone shape and is tolerated: flow is only meaningful with fund_id.
alter table public.entries add constraint entries_fund_shape check (
  (fund_flow is null and fund_id is null and category_id is not null)
  or (fund_flow = 'in' and category_id is not null)
  or (fund_flow = 'out' and category_id is null)
);

alter table public.entries add constraint entries_fund_fkey
  foreign key (user_id, fund_id) references public.funds (user_id, id)
  on delete set null (fund_id);

create index entries_fund on public.entries (user_id, fund_id)
  where fund_id is not null;

-- The closed-month entries guard must let the RI-triggered SET NULL
-- through — same shape exception as recurring_template_id.
create or replace function public.guard_entries_closed_month()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status public.month_status;
begin
  -- Deletes issued by ON DELETE CASCADE (e.g. auth.users -> months ->
  -- entries) run inside a foreign-key trigger, so trigger depth > 1.
  -- Let them through: the read-only rule is only for client statements.
  if tg_op = 'DELETE' and pg_trigger_depth() > 1 then
    return old;
  end if;
  -- ON DELETE SET NULL on the recurring_template and fund FKs performs an
  -- UPDATE inside an RI trigger as well. Allow exactly those shapes: the
  -- link columns going non-null -> null and nothing else changing.
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and old.recurring_template_id is not null
     and new.recurring_template_id is null
     and to_jsonb(new) - 'recurring_template_id'
         = to_jsonb(old) - 'recurring_template_id' then
    return new;
  end if;
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and old.fund_id is not null
     and new.fund_id is null
     and to_jsonb(new) - 'fund_id'
         = to_jsonb(old) - 'fund_id' then
    return new;
  end if;
  if tg_op <> 'INSERT' then
    select m.status into v_status from public.months m where m.id = old.month_id;
    if v_status = 'closed' then
      raise exception 'month is closed; entries are read-only';
    end if;
  end if;
  if tg_op <> 'DELETE' then
    select m.status into v_status from public.months m where m.id = new.month_id;
    if v_status = 'closed' then
      raise exception 'month is closed; entries are read-only';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- Only banks can fund 'out' entries, and only while active. Piggy banks
-- never spend — their money leaves via delete_fund's extras transfer.
create or replace function public.guard_entry_fund_flow()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_kind public.fund_kind;
  v_active boolean;
  v_balance bigint;
begin
  if new.fund_id is null then
    return new;
  end if;
  select f.kind, f.active into v_kind, v_active
  from public.funds f
  where f.user_id = new.user_id and f.id = new.fund_id;
  if not found then
    raise exception 'fund not found';
  end if;
  if new.fund_flow = 'out' then
    if v_kind <> 'bank' or not v_active then
      raise exception 'entries can only spend from active banks';
    end if;
    -- A bank can never go negative: the spend must fit inside the
    -- deposits minus prior spends. On UPDATE the row itself is excluded
    -- so it doesn't count against its own balance.
    select coalesce(sum(
      case e.fund_flow when 'in' then e.amount_cents else -e.amount_cents end
    ), 0) into v_balance
    from public.entries e
    where e.user_id = new.user_id
      and e.fund_id = new.fund_id
      and (tg_op <> 'UPDATE' or e.id <> old.id);
    if new.amount_cents > v_balance then
      raise exception 'insufficient fund balance';
    end if;
  end if;
  return new;
end;
$$;

create trigger entries_guard_fund_flow
  before insert or update on public.entries
  for each row execute function public.guard_entry_fund_flow();

-- ---------------------------------------------------------------------
-- deposit_to_fund: bucket -> fund in one atomic call. Each nonzero bucket
-- amount becomes a normal entry under a per-kind system category
-- ('Reservas' / 'Cofrinhos', created on demand) so the bucket is charged
-- at deposit time, and credits the fund via fund_flow='in'. Passing both
-- amounts splits the deposit across buckets.
-- ---------------------------------------------------------------------

create or replace function public.deposit_to_fund(
  p_fund_id uuid,
  p_month_id uuid,
  p_essential_cents bigint default 0,
  p_fun_cents bigint default 0,
  p_paid_on date default null,
  p_note text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_fund public.funds;
  v_month public.months;
  v_paid_on date;
  v_cat_name text;
  v_cat_id uuid;
  v_note text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select f.* into v_fund
  from public.funds f
  where f.id = p_fund_id and f.user_id = v_uid;
  if not found then
    raise exception 'fund not found';
  end if;

  select m.* into v_month
  from public.months m
  where m.id = p_month_id and m.user_id = v_uid;
  if not found then
    raise exception 'month not found';
  end if;
  if v_month.status <> 'open' then
    raise exception 'month is not open';
  end if;

  if coalesce(p_essential_cents, 0) < 0 or coalesce(p_fun_cents, 0) < 0 then
    raise exception 'deposit amounts must be >= 0';
  end if;
  if coalesce(p_essential_cents, 0) + coalesce(p_fun_cents, 0) <= 0 then
    raise exception 'deposit must be > 0 in at least one bucket';
  end if;

  v_paid_on := coalesce(
    p_paid_on,
    least(current_date, make_date(v_month.year, v_month.month, 1)
      + interval '1 month - 1 day')::date
  );
  if extract(year from v_paid_on) <> v_month.year
     or extract(month from v_paid_on) <> v_month.month then
    raise exception 'paid_on must be inside the month';
  end if;

  v_cat_name := case v_fund.kind when 'bank' then 'Reservas' else 'Cofrinhos' end;
  v_note := coalesce(nullif(btrim(p_note), ''), v_fund.name);


  -- One entry per nonzero bucket amount, under the get-or-create system
  -- category ('Reservas'/'Cofrinhos') for that bucket. Both fire in the
  -- same transaction, so a partial split can never be committed.
  if coalesce(p_essential_cents, 0) > 0 then
    insert into public.categories (user_id, bucket, name)
    values (v_uid, 'essential', v_cat_name)
    on conflict (user_id, bucket, name) do nothing;
    select c.id into v_cat_id from public.categories c
    where c.user_id = v_uid and c.bucket = 'essential' and c.name = v_cat_name;
    insert into public.entries
      (user_id, month_id, category_id, amount_cents, paid_on, note,
       fund_id, fund_flow)
    values
      (v_uid, p_month_id, v_cat_id, p_essential_cents, v_paid_on, v_note,
       p_fund_id, 'in');
  end if;

  if coalesce(p_fun_cents, 0) > 0 then
    insert into public.categories (user_id, bucket, name)
    values (v_uid, 'fun', v_cat_name)
    on conflict (user_id, bucket, name) do nothing;
    select c.id into v_cat_id from public.categories c
    where c.user_id = v_uid and c.bucket = 'fun' and c.name = v_cat_name;
    insert into public.entries
      (user_id, month_id, category_id, amount_cents, paid_on, note,
       fund_id, fund_flow)
    values
      (v_uid, p_month_id, v_cat_id, p_fun_cents, v_paid_on, v_note,
       p_fund_id, 'in');
  end if;

  return;
end;
$$;

-- ---------------------------------------------------------------------
-- delete_fund: removes the fund (entries keep their rows; the fund link
-- is nulled by the FK). With p_move_to_extras, the remaining balance is
-- moved into the current open month's extra_income in the same
-- transaction — the only way to reclaim bank/piggy money.
-- ---------------------------------------------------------------------

create or replace function public.delete_fund(
  p_fund_id uuid,
  p_move_to_extras boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_fund public.funds;
  v_balance bigint;
  v_month public.months;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select f.* into v_fund
  from public.funds f
  where f.id = p_fund_id and f.user_id = v_uid
  for update;
  if not found then
    raise exception 'fund not found';
  end if;

  if p_move_to_extras then
    select coalesce(sum(
      case e.fund_flow when 'in' then e.amount_cents else -e.amount_cents end
    ), 0) into v_balance
    from public.entries e
    where e.user_id = v_uid and e.fund_id = p_fund_id;

    if v_balance > 0 then
      select m.* into v_month
      from public.months m
      where m.user_id = v_uid
        and m.year = extract(year from current_date)::smallint
        and m.month = extract(month from current_date)::smallint
        and m.status = 'open';
      if not found then
        raise exception 'no open month for the current period to receive extras';
      end if;
      insert into public.extra_income
        (user_id, month_id, amount_cents, received_on, note)
      values
        (v_uid, v_month.id, v_balance, current_date,
         case v_fund.kind
           when 'bank' then 'Reserva: ' || v_fund.name
           else 'Cofrinho: ' || v_fund.name
         end);
    end if;
  end if;

  delete from public.funds f where f.id = p_fund_id;
end;
$$;

-- ---------------------------------------------------------------------
-- fund_balances: computed, not stored — balance = deposits - spends over
-- all months. Deleting a month removes its fund entries too, so the
-- balance always reflects the entries that exist.
-- ---------------------------------------------------------------------

create view public.fund_balances
with (security_invoker = true) as
select e.fund_id,
  sum(case e.fund_flow
        when 'in' then e.amount_cents
        else -e.amount_cents
      end)::bigint as balance_cents
from public.entries e
where e.fund_id is not null
group by e.fund_id;

-- ---------------------------------------------------------------------
-- Function privileges: RPC entry points are for authenticated users only.
-- ---------------------------------------------------------------------

revoke all on function public.deposit_to_fund(uuid, uuid, bigint, bigint, date, text) from public, anon, authenticated;
revoke all on function public.delete_fund(uuid, boolean) from public, anon, authenticated;
grant execute on function public.deposit_to_fund(uuid, uuid, bigint, bigint, date, text) to authenticated;
grant execute on function public.delete_fund(uuid, boolean) to authenticated;
