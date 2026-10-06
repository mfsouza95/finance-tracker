-- Extra income: mid-month receipts that bypass the 50/30/20 split and land
-- 100% in the fun bucket (e.g. a friend paying back a loan you had written
-- off). Each receipt is its own row — never an aggregate.
-- extra_income rows are read-only once their month closes, same as entries.

create table public.extra_income (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  month_id uuid not null,
  amount_cents bigint not null check (amount_cents > 0),
  received_on date not null,
  note text,
  created_at timestamptz not null default now(),
  foreign key (user_id, month_id) references public.months (user_id, id) on delete cascade
);

create index extra_income_lookup on public.extra_income (user_id, month_id);

alter table public.extra_income enable row level security;
create policy own_rows on public.extra_income for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- month_summaries records the extras total so history can explain why the
-- fun budget exceeded the plain split.
alter table public.month_summaries
  add column extra_income_cents bigint not null default 0;

-- Same closed-month read-only rule as entries (minus the recurring-template
-- SET NULL path, which does not exist here).
create or replace function public.guard_extra_income_closed_month()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status public.month_status;
begin
  -- Cascaded deletes (auth.users -> months -> extra_income) run inside a
  -- foreign-key trigger; the read-only rule is only for client statements.
  if tg_op = 'DELETE' and pg_trigger_depth() > 1 then
    return old;
  end if;
  if tg_op <> 'INSERT' then
    select m.status into v_status from public.months m where m.id = old.month_id;
    if v_status = 'closed' then
      raise exception 'month is closed; extra income is read-only';
    end if;
  end if;
  if tg_op <> 'DELETE' then
    select m.status into v_status from public.months m where m.id = new.month_id;
    if v_status = 'closed' then
      raise exception 'month is closed; extra income is read-only';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger extra_income_guard_closed_month
  before insert or update or delete on public.extra_income
  for each row execute function public.guard_extra_income_closed_month();

-- close_month: extras raise the fun budget 1:1 (they bypass the split).
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
    coalesce(sum(e.amount_cents) filter (where c.bucket = 'essential'), 0),
    coalesce(sum(e.amount_cents) filter (where c.bucket = 'fun'), 0)
  into v_essential_spent, v_fun_spent
  from public.entries e
  join public.categories c
    on c.user_id = e.user_id and c.id = e.category_id
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
