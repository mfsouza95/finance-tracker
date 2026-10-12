-- Split delete into two paths so it never destroys history:
--   * a bank with no 'out' entries ("empty" — deposits alone don't count)
--     is erased for real, keeping the extras-or-discard drain;
--   * a bank with spends is soft-deleted: flagged deleted_at + deactivated,
--     hidden but recoverable. When the real-time current month closes,
--     close_month purges flagged funds — balance lands in that month's
--     extras automatically, then the row is deleted for good.
-- Plus reopen_fund (undo completion; the drain stays in the ledger and the
-- bank returns at zero) and restore_fund (un-flag a pending deletion).

alter table public.funds add column deleted_at timestamptz;

-- Lifecycle guards on deposit: a completed or deletion-flagged fund must
-- not accept money — the UI hides them, but the RPC itself now enforces it.
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

-- Same guard inside the entry trigger: 'in' rows inserted directly (not via
-- deposit_to_fund) also can't credit a completed or deleted fund.
create or replace function public.guard_entry_fund_flow()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_fund public.funds;
  v_balance bigint;
begin
  if new.fund_id is null then
    return new;
  end if;
  select f.* into v_fund
  from public.funds f
  where f.user_id = new.user_id and f.id = new.fund_id;
  if not found then
    raise exception 'fund not found';
  end if;
  if v_fund.deleted_at is not null then
    raise exception 'entries cannot target a deleted fund';
  end if;
  if new.fund_flow = 'in' and v_fund.completed_at is not null then
    raise exception 'entries cannot credit a completed fund';
  end if;
  if new.fund_flow = 'out' then
    if v_fund.kind <> 'bank' or not v_fund.active then
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

-- delete_fund: the path is decided by history, not balance.
--   * no 'out' entries -> the extras-or-discard drain + hard DELETE
--     (entries keep their rows; the fund link is nulled by the FK);
--   * has 'out' entries -> soft delete only: flagged + deactivated, the
--     balance stays parked until close_month purges it into extras.
-- Completed funds can't be deleted — they're part of month history.
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

  -- A bank with spend history is only flagged: recoverable until the
  -- current month closes, when close_month purges it into extras.
  if v_fund.kind = 'bank' and exists (
    select 1 from public.entries e
    where e.user_id = v_uid
      and e.fund_id = p_fund_id
      and e.fund_flow = 'out'
  ) then
    update public.funds f
    set deleted_at = now(), active = false
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

-- Undo a pending deletion: bank comes back active with balance untouched.
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
  set deleted_at = null, active = true
  where f.id = p_fund_id and f.user_id = v_uid and f.deleted_at is not null;
  if not found then
    raise exception 'fund not found or not marked for deletion';
  end if;
end;
$$;

-- Undo a completion: the 'Concluída' drain stays in the ledger, so the
-- bank returns at zero balance — reopening revives it, it doesn't rewind.
create or replace function public.reopen_fund(p_fund_id uuid)
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
  set completed_at = null, active = true
  where f.id = p_fund_id and f.user_id = v_uid and f.completed_at is not null;
  if not found then
    raise exception 'fund not found or not completed';
  end if;
end;
$$;

-- close_month gains the purge: flagged funds drain into the extras of the
-- month being closed (before extras are summed, so they count toward the
-- fun budget and the stored summary), then are deleted for real. Only runs
-- when the closing month is the real-time current one — closing a past
-- month must not pull a deletion that happened later.
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

  -- Purge funds marked for deletion when this is the current month:
  -- balance lands in extras automatically, then the row goes for good.
  if v_month.year = extract(year from current_date)::smallint
     and v_month.month = extract(month from current_date)::smallint then
    for v_fund in
      select f.* from public.funds f
      where f.user_id = v_uid and f.deleted_at is not null
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
  end if;

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

revoke all on function public.deposit_to_fund(uuid, uuid, bigint, bigint, date, text) from public, anon, authenticated;
revoke all on function public.delete_fund(uuid, boolean) from public, anon, authenticated;
revoke all on function public.restore_fund(uuid) from public, anon, authenticated;
revoke all on function public.reopen_fund(uuid) from public, anon, authenticated;
grant execute on function public.deposit_to_fund(uuid, uuid, bigint, bigint, date, text) to authenticated;
grant execute on function public.delete_fund(uuid, boolean) to authenticated;
grant execute on function public.restore_fund(uuid) to authenticated;
grant execute on function public.reopen_fund(uuid) to authenticated;
