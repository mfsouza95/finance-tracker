-- Completing a bank ("concluir reserva") is a lifecycle end that PRESERVES
-- the fund row: entries keep their fund_id, so the full history (deposits
-- and spends) stays inspectable afterwards — unlike delete_fund, which
-- nulls the link. The remainder is drained by a balancing 'out' entry
-- written into the current open month, optionally mirrored into
-- extra_income (same choice as delete).

alter table public.funds add column completed_at timestamptz;

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
    where m.user_id = v_uid
      and m.year = extract(year from current_date)::smallint
      and m.month = extract(month from current_date)::smallint
      and m.status = 'open';
    if not found then
      raise exception 'open the current month to complete a reserve with balance';
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

revoke all on function public.complete_fund(uuid, boolean) from public, anon, authenticated;
grant execute on function public.complete_fund(uuid, boolean) to authenticated;
