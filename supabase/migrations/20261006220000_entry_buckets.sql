-- Categories become organizational-only: an entry now carries its own
-- bucket, so "log into Essencial without picking a category" is possible.
-- When a category IS set, a trigger syncs entries.bucket from it (the
-- category stays the source of truth for its entries). close_month and
-- the UI read entries.bucket directly instead of joining categories.

alter table public.entries add column bucket public.bucket;

update public.entries e set bucket = c.bucket
from public.categories c
where e.category_id = c.id;

create or replace function public.sync_entry_bucket()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_bucket public.bucket;
begin
  if new.category_id is not null then
    select c.bucket into v_bucket
    from public.categories c
    where c.user_id = new.user_id and c.id = new.category_id;
    if not found then
      -- Same surface the composite FK would give: cross-user or dangling
      -- category ids are rejected before the row is even checked.
      raise exception 'category not found' using errcode = '23503';
    end if;
    new.bucket := v_bucket;
  end if;
  return new;
end;
$$;

create trigger entries_sync_bucket
  before insert or update on public.entries
  for each row execute function public.sync_entry_bucket();

-- Shapes now: normal entry (bucket set, category optional) / deposit
-- ('in', bucket set — the bucket that funded it) / bank spend ('out',
-- no category and no bucket). Tombstones keep working: after a fund
-- delete the link is nulled but flow and bucket survive.
-- IS NOT DISTINCT FROM matters: plain = yields NULL on null flow, and a
-- check whose result is NULL passes — an all-null row would slip through.
alter table public.entries drop constraint entries_fund_shape;
alter table public.entries add constraint entries_fund_shape check (
  (fund_flow is null and fund_id is null and bucket is not null)
  or (fund_flow is not distinct from 'in' and bucket is not null)
  or (fund_flow is not distinct from 'out'
      and bucket is null and category_id is null)
);

-- close_month now reads entries.bucket directly: no category join, and
-- 'out' entries (bucket null) stay invisible to the buckets.
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
