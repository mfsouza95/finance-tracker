-- Fatura-aware months: months keep their (year, month) label but gain two
-- informational dates — closes_on (fatura deadline, drives the deadline
-- warning) and payday_on (display only). No date is enforced: any paid_on
-- can be logged into any open month — the user decides attribution.
--
-- "Latest open month" (max year,month among status='open') becomes the
-- single write-target for money movements: deposit_to_fund only accepts
-- that month, and delete_fund/complete_fund send extras + drain entries to
-- it. Soft-deleted banks anchor to it via funds.deleted_in_month_id —
-- close_month purges a flagged fund only when its anchor closes (a null
-- anchor — flagged with no open month, or anchor month deleted — purges at
-- the next close). deposit_to_fund's paid_on-in-calendar-month check goes
-- away: deposits are entries, and entries take any date.

alter table public.months
  add column closes_on date,
  add column payday_on date;

alter table public.funds
  add column deleted_in_month_id uuid
    references public.months(id) on delete set null;

-- Backfill: banks already flagged keep their intent — they die at the
-- latest open month's close, matching the old "current month" rule.
update public.funds f
set deleted_in_month_id = (
  select m.id from public.months m
  where m.user_id = f.user_id and m.status = 'open'
  order by m.year desc, m.month desc limit 1
)
where f.deleted_at is not null;

-- open_month gains the two optional dates. Postgres overloads by signature,
-- so the old 3-arg function must be dropped — otherwise it would keep
-- shadowing this one for existing callers (same pattern as
-- create_recurring_template). Defaults keep every current call working.
drop function public.open_month(smallint, smallint, bigint);

create function public.open_month(
  year smallint,
  month smallint,
  net_income_cents bigint,
  closes_on date default null,
  payday_on date default null
)
returns public.months
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_month public.months;
  v_settings public.budget_settings;
  v_last_day int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if month is null or month < 1 or month > 12 then
    raise exception 'month must be between 1 and 12';
  end if;
  if net_income_cents is null or net_income_cents < 0 then
    raise exception 'net_income_cents must be >= 0';
  end if;

  select bs.* into v_settings
  from public.budget_settings bs
  where bs.user_id = v_uid;
  if not found then
    raise exception 'budget_settings not found for current user';
  end if;

  -- ON CONFLICT ON CONSTRAINT is used (rather than a column list) because
  -- the parameter names year/month would shadow the arbiter columns under
  -- #variable_conflict use_variable.
  insert into public.months
    (user_id, year, month, net_income_cents, essential_pct, fun_pct,
     invest_pct, closes_on, payday_on)
  values
    (v_uid, year, month, net_income_cents,
     v_settings.essential_pct, v_settings.fun_pct, v_settings.invest_pct,
     closes_on, payday_on)
  on conflict on constraint months_user_id_year_month_key do nothing
  returning * into v_month;

  if v_month.id is null then
    -- The month already existed: return it unchanged (net_income_cents and
    -- the dates are ignored) and generate nothing.
    select m.* into v_month
    from public.months m
    where m.user_id = v_uid and m.year = year and m.month = month;
    if v_month.id is null then
      raise exception 'failed to create month';
    end if;
    if v_month.status = 'closed' then
      raise exception 'month %-% is already closed', year, month;
    end if;
    return v_month;
  end if;

  v_last_day := extract(day from
    (date_trunc('month', make_date(year::int, month::int, 1)) + interval '1 month - 1 day'))::int;

  insert into public.entries
    (user_id, month_id, category_id, bucket, amount_cents, paid_on, note,
     recurring_template_id, installment_index)
  select
    v_uid,
    v_month.id,
    t.category_id,
    t.bucket,
    t.amount_cents,
    make_date(year::int, month::int, least(t.day_of_month, v_last_day)),
    t.label,
    t.id,
    case
      when t.installments_total is null then null
      else (year::int * 12 + month::int)
           - (t.first_year::int * 12 + t.first_month::int) + 1
    end
  from public.recurring_templates t
  left join public.categories c
    on c.user_id = t.user_id and c.id = t.category_id
  where t.user_id = v_uid and t.active
    and (t.category_id is null or not c.archived)
    and (
      t.installments_total is null
      or (year::int * 12 + month::int)
         - (t.first_year::int * 12 + t.first_month::int) + 1
         between 1 and t.installments_total
    )
  on conflict (month_id, recurring_template_id)
    where recurring_template_id is not null
    do nothing;

  return v_month;
end;
$$;

-- deposit_to_fund: money movements only charge the latest open month, and
-- paid_on stops being checked against the label (deposits are entries;
-- entries take any date).
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
  v_latest uuid;
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
  if v_fund.completed_at is not null or v_fund.deleted_at is not null then
    raise exception 'cannot deposit to a completed or deleted fund';
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

  -- Deposits are a live money movement: they charge the newest open month,
  -- not whichever month happens to be on screen.
  select m.id into v_latest
  from public.months m
  where m.user_id = v_uid and m.status = 'open'
  order by m.year desc, m.month desc limit 1;
  if p_month_id is distinct from v_latest then
    raise exception 'deposits go to the latest open month';
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

-- delete_fund: extras go to the latest open month, and the soft-delete flag
-- records which month will kill the fund (its anchor).
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
  if v_fund.completed_at is not null then
    raise exception 'completed reserves cannot be deleted';
  end if;
  if v_fund.deleted_at is not null then
    raise exception 'fund is already marked for deletion';
  end if;

  -- A bank with spend history is only flagged: recoverable until its anchor
  -- month (the latest open one at flag time) closes and close_month purges
  -- it into extras.
  if v_fund.kind = 'bank' and exists (
    select 1 from public.entries e
    where e.user_id = v_uid
      and e.fund_id = p_fund_id
      and e.fund_flow = 'out'
  ) then
    update public.funds f
    set deleted_at = now(),
        active = false,
        deleted_in_month_id = (
          select m.id from public.months m
          where m.user_id = v_uid and m.status = 'open'
          order by m.year desc, m.month desc limit 1
        )
    where f.id = p_fund_id;
    return;
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
      where m.user_id = v_uid and m.status = 'open'
      order by m.year desc, m.month desc
      limit 1;
      if not found then
        raise exception 'no open month to receive extras';
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

-- complete_fund: the drain entry and the optional extras mirror land in the
-- latest open month (same write-target rule as deposits/deletions).
create or replace function public.complete_fund(
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
  if v_fund.kind <> 'bank' then
    raise exception 'only banks can be completed';
  end if;
  if v_fund.completed_at is not null then
    raise exception 'fund is already completed';
  end if;

  select coalesce(sum(
    case e.fund_flow when 'in' then e.amount_cents else -e.amount_cents end
  ), 0) into v_balance
  from public.entries e
  where e.user_id = v_uid and e.fund_id = p_fund_id;

  if v_balance > 0 then
    -- The drain entry needs a writable month: closed months are read-only.
    select m.* into v_month
    from public.months m
    where m.user_id = v_uid and m.status = 'open'
    order by m.year desc, m.month desc
    limit 1;
    if not found then
      raise exception 'no open month to complete a reserve with balance';
    end if;

    if p_move_to_extras then
      insert into public.extra_income
        (user_id, month_id, amount_cents, received_on, note)
      values
        (v_uid, v_month.id, v_balance, current_date,
         'Reserva: ' || v_fund.name);
    end if;

    -- Balancing 'out' entry: drains the computed balance to zero and keeps
    -- an honest ledger line in the bank's history. Inserted while the bank
    -- is still active so guard_entry_fund_flow accepts it.
    insert into public.entries
      (user_id, month_id, amount_cents, paid_on, note, fund_id, fund_flow)
    values
      (v_uid, v_month.id, v_balance, current_date,
       case when p_move_to_extras
            then 'Concluída — saldo para extras'
            else 'Concluída — saldo descartado' end,
       p_fund_id, 'out');
  end if;

  update public.funds f
  set completed_at = now(), active = false
  where f.id = p_fund_id;
end;
$$;

-- restore_fund: un-flag a pending deletion — clears the anchor too.
create or replace function public.restore_fund(p_fund_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  update public.funds f
  set deleted_at = null, active = true, deleted_in_month_id = null
  where f.id = p_fund_id and f.user_id = v_uid and f.deleted_at is not null;
  if not found then
    raise exception 'fund not found or not marked for deletion';
  end if;
end;
$$;

-- close_month: purge flagged funds whose ANCHOR is the closing month (or
-- whose anchor is null — flagged with no open month, or anchor deleted).
-- A retroactively-closed past month can no longer drain a deletion that was
-- anchored to a newer one.
create or replace function public.close_month(
  month_id uuid,
  invested_cents bigint
)
returns public.month_summaries
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_month public.months;
  v_summary public.month_summaries;
  v_fund public.funds;
  v_fund_balance bigint;
  v_essential_budget bigint;
  v_fun_budget bigint;
  v_invest_target bigint;
  v_essential_spent bigint;
  v_fun_spent bigint;
  v_extras bigint;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if invested_cents is null or invested_cents < 0 then
    raise exception 'invested_cents must be >= 0';
  end if;

  select m.* into v_month
  from public.months m
  where m.id = month_id and m.user_id = v_uid
  for update;

  if not found then
    raise exception 'month not found';
  end if;
  if v_month.status = 'closed' then
    raise exception 'month is already closed';
  end if;

  -- Purge funds anchored to this month (and unanchored ones): balance lands
  -- in extras automatically — before extras are summed, so the stored
  -- summary counts them — then the row goes for good.
  for v_fund in
    select f.* from public.funds f
    where f.user_id = v_uid
      and f.deleted_at is not null
      and (f.deleted_in_month_id is null
           or f.deleted_in_month_id = month_id)
  loop
    select coalesce(sum(
      case e.fund_flow when 'in' then e.amount_cents else -e.amount_cents end
    ), 0) into v_fund_balance
    from public.entries e
    where e.user_id = v_uid and e.fund_id = v_fund.id;

    if v_fund_balance > 0 then
      insert into public.extra_income
        (user_id, month_id, amount_cents, received_on, note)
      values
        (v_uid, month_id, v_fund_balance, current_date,
         case v_fund.kind
           when 'bank' then 'Reserva: ' || v_fund.name
           else 'Cofrinho: ' || v_fund.name
         end);
    end if;

    delete from public.funds f where f.id = v_fund.id;
  end loop;

  v_essential_budget := v_month.net_income_cents * v_month.essential_pct / 100;
  v_fun_budget := v_month.net_income_cents * v_month.fun_pct / 100;
  v_invest_target := v_month.net_income_cents - v_essential_budget - v_fun_budget;

  select
    coalesce(sum(e.amount_cents) filter (where e.bucket = 'essential'), 0),
    coalesce(sum(e.amount_cents) filter (where e.bucket = 'fun'), 0)
  into v_essential_spent, v_fun_spent
  from public.entries e
  where e.user_id = v_uid and e.month_id = month_id;

  select coalesce(sum(x.amount_cents), 0) into v_extras
  from public.extra_income x
  where x.user_id = v_uid and x.month_id = month_id;

  -- Extras go 100% to fun, so the recorded fun budget is base + extras.
  v_fun_budget := v_fun_budget + v_extras;

  -- Allow the months guard to accept this open -> closed transition.
  -- is_local = true scopes the flag to the transaction; clear it
  -- immediately after the update so no later statement in the same
  -- transaction can bypass the guard.
  perform set_config('app.close_month', 'on', true);

  update public.months m
  set status = 'closed',
      closed_at = now(),
      invested_cents = close_month.invested_cents
  where m.id = month_id;

  perform set_config('app.close_month', 'off', true);

  insert into public.month_summaries
    (month_id, user_id, net_income_cents,
     essential_budget_cents, essential_spent_cents, essential_rest_cents,
     fun_budget_cents, fun_spent_cents, fun_rest_cents,
     invest_target_cents, invested_cents, extra_income_cents)
  values
    (month_id, v_uid, v_month.net_income_cents,
     v_essential_budget, v_essential_spent, v_essential_budget - v_essential_spent,
     v_fun_budget, v_fun_spent, v_fun_budget - v_fun_spent,
     v_invest_target, invested_cents, v_extras)
  returning * into v_summary;

  return v_summary;
end;
$$;

-- The dropped 3-arg open_month took its grants with it; re-apply to the
-- new signature. deposit/delete/complete/restore/close keep theirs
-- (create or replace preserves grants).
revoke all on function public.open_month(smallint, smallint, bigint, date, date) from public, anon, authenticated;
grant execute on function public.open_month(smallint, smallint, bigint, date, date) to authenticated;
