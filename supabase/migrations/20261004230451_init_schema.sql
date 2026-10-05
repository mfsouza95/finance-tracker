-- Initial schema: profiles, budget_settings, months, categories,
-- recurring_templates, entries, month_summaries.
-- Money is integer cents (bigint). Every table is multi-user via user_id + RLS.

create type public.bucket as enum ('essential', 'fun');
create type public.month_status as enum ('open', 'closed');

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table public.profiles (
  user_id uuid primary key references auth.users on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create table public.budget_settings (
  user_id uuid primary key references auth.users on delete cascade,
  essential_pct smallint not null default 50 check (essential_pct between 0 and 100),
  fun_pct smallint not null default 30 check (fun_pct between 0 and 100),
  invest_pct smallint not null default 20 check (invest_pct between 0 and 100),
  created_at timestamptz not null default now(),
  check (essential_pct + fun_pct + invest_pct = 100)
);

create table public.months (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  year smallint not null check (year between 2000 and 2200),
  month smallint not null check (month between 1 and 12),
  net_income_cents bigint not null check (net_income_cents >= 0),
  essential_pct smallint not null check (essential_pct between 0 and 100),
  fun_pct smallint not null check (fun_pct between 0 and 100),
  invest_pct smallint not null check (invest_pct between 0 and 100),
  status month_status not null default 'open',
  invested_cents bigint check (invested_cents is null or invested_cents >= 0),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint months_user_id_year_month_key unique (user_id, year, month),
  unique (user_id, id),
  check (essential_pct + fun_pct + invest_pct = 100),
  check ((status = 'open' and closed_at is null and invested_cents is null)
      or (status = 'closed' and closed_at is not null and invested_cents is not null))
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  bucket bucket not null,
  name text not null,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique (user_id, bucket, name),
  unique (user_id, id)
);

create table public.recurring_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  category_id uuid not null,
  label text not null,
  amount_cents bigint not null check (amount_cents > 0),
  day_of_month smallint not null check (day_of_month between 1 and 31),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (user_id, id),
  foreign key (user_id, category_id) references public.categories (user_id, id)
);

create table public.entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  month_id uuid not null,
  category_id uuid not null,
  amount_cents bigint not null check (amount_cents > 0),
  paid_on date not null,
  note text,
  recurring_template_id uuid,
  created_at timestamptz not null default now(),
  foreign key (user_id, month_id) references public.months (user_id, id) on delete cascade,
  foreign key (user_id, category_id) references public.categories (user_id, id),
  foreign key (user_id, recurring_template_id) references public.recurring_templates (user_id, id)
    on delete set null (recurring_template_id)
);

create unique index entries_recurring_once
  on public.entries (month_id, recurring_template_id)
  where recurring_template_id is not null;
create index entries_lookup on public.entries (user_id, month_id, category_id);
create index recurring_templates_active on public.recurring_templates (user_id) where active;

create table public.month_summaries (
  month_id uuid primary key,
  user_id uuid not null references auth.users on delete cascade,
  net_income_cents bigint not null,
  essential_budget_cents bigint not null,
  essential_spent_cents bigint not null,
  essential_rest_cents bigint not null,
  fun_budget_cents bigint not null,
  fun_spent_cents bigint not null,
  fun_rest_cents bigint not null,
  invest_target_cents bigint not null,
  invested_cents bigint not null check (invested_cents >= 0),
  created_at timestamptz not null default now(),
  foreign key (user_id, month_id) references public.months (user_id, id) on delete cascade
);

-- ---------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.budget_settings enable row level security;
alter table public.months enable row level security;
alter table public.categories enable row level security;
alter table public.recurring_templates enable row level security;
alter table public.entries enable row level security;
alter table public.month_summaries enable row level security;

-- profiles and budget_settings rows are created by handle_new_user and
-- removed by cascade from auth.users; clients may only read and update.
create policy own_rows_select on public.profiles for select to authenticated
  using ((select auth.uid()) = user_id);
create policy own_rows_update on public.profiles for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy own_rows_select on public.budget_settings for select to authenticated
  using ((select auth.uid()) = user_id);
create policy own_rows_update on public.budget_settings for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy own_rows on public.months for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy own_rows on public.categories for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy own_rows on public.recurring_templates for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy own_rows on public.entries for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- month_summaries is written only by close_month() (security definer);
-- clients get read-only access.
create policy own_rows on public.month_summaries for select to authenticated
  using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- New-user bootstrap: profiles + default 50/30/20 budget_settings
-- ---------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(
    new.raw_user_meta_data ->> 'display_name',
    new.raw_user_meta_data ->> 'full_name',
    new.email
  ))
  on conflict (user_id) do nothing;

  insert into public.budget_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Closed-month guards
-- ---------------------------------------------------------------------

-- Entries in a closed month are immutable, and no entry may be moved
-- into a closed month.
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
  -- ON DELETE SET NULL on the recurring_template FK performs an UPDATE
  -- inside an RI trigger as well. Allow exactly that shape: the link
  -- column going non-null -> null and nothing else changing. A client
  -- touching recurring_template_id directly is depth 1 and still blocked.
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and old.recurring_template_id is not null
     and new.recurring_template_id is null
     and to_jsonb(new) - 'recurring_template_id'
         = to_jsonb(old) - 'recurring_template_id' then
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

create trigger entries_guard_closed_month
  before insert or update or delete on public.entries
  for each row execute function public.guard_entries_closed_month();

-- A closed month is fully read-only. Months can only transition
-- open -> closed inside close_month(), which sets the app.close_month
-- transaction-local flag. This prevents closing a month without a
-- month_summaries row (or inserting one already closed).
create or replace function public.guard_month_closed()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    -- Cascaded deletes (auth.users -> ...) fire this trigger at depth > 1;
    -- the block applies only to direct client deletes.
    if pg_trigger_depth() = 1 and old.status = 'closed' then
      raise exception 'closed months cannot be deleted';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'open' then
      raise exception 'new months must be open; use close_month() to close';
    end if;
    return new;
  end if;
  if old.status = 'closed' then
    raise exception 'closed months are read-only';
  end if;
  if new.status = 'closed'
     and coalesce(current_setting('app.close_month', true), '') <> 'on' then
    raise exception 'use close_month() to close a month';
  end if;
  return new;
end;
$$;

create trigger months_guard_closed
  before insert or update or delete on public.months
  for each row execute function public.guard_month_closed();

-- A category's bucket determines which bucket its entries count against;
-- changing it after entries exist would silently rewrite history.
create or replace function public.guard_category_bucket()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.bucket is distinct from old.bucket
     and exists (
       select 1 from public.entries e
       where e.user_id = old.user_id and e.category_id = old.id
     ) then
    raise exception 'cannot change bucket of a category that has entries';
  end if;
  return new;
end;
$$;

create trigger categories_guard_bucket
  before update on public.categories
  for each row execute function public.guard_category_bucket();

-- ---------------------------------------------------------------------
-- open_month: create month (snapshotting split), generate recurring
-- entries. Idempotent via unique constraints + ON CONFLICT DO NOTHING.
-- ---------------------------------------------------------------------

create or replace function public.open_month(
  year smallint,
  month smallint,
  net_income_cents bigint
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
    (user_id, year, month, net_income_cents, essential_pct, fun_pct, invest_pct)
  values
    (v_uid, year, month, net_income_cents,
     v_settings.essential_pct, v_settings.fun_pct, v_settings.invest_pct)
  on conflict on constraint months_user_id_year_month_key do nothing
  returning * into v_month;

  if v_month.id is null then
    -- The month already existed: return it unchanged (net_income_cents is
    -- ignored) and generate nothing. Recurring generation only happens on
    -- creation so user edits/deletions are never resurrected.
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
    (user_id, month_id, category_id, amount_cents, paid_on, note, recurring_template_id)
  select
    v_uid,
    v_month.id,
    t.category_id,
    t.amount_cents,
    make_date(year::int, month::int, least(t.day_of_month, v_last_day)),
    t.label,
    t.id
  from public.recurring_templates t
  join public.categories c
    on c.user_id = t.user_id and c.id = t.category_id
  where t.user_id = v_uid and t.active and not c.archived
  on conflict (month_id, recurring_template_id)
    where recurring_template_id is not null
    do nothing;

  return v_month;
end;
$$;

-- ---------------------------------------------------------------------
-- close_month: write month_summaries, mark month closed.
-- Bucket math mirrors computeBuckets in the client:
--   essential = floor(net * essential_pct / 100)   (integer division = floor, net >= 0)
--   fun       = floor(net * fun_pct / 100)
--   invest    = net - essential - fun
--   rest      = budget - spent
-- ---------------------------------------------------------------------

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
     invest_target_cents, invested_cents)
  values
    (month_id, v_uid, v_month.net_income_cents,
     v_essential_budget, v_essential_spent, v_essential_budget - v_essential_spent,
     v_fun_budget, v_fun_spent, v_fun_budget - v_fun_spent,
     v_invest_target, invested_cents)
  returning * into v_summary;

  return v_summary;
end;
$$;

-- ---------------------------------------------------------------------
-- Function privileges: RPC entry points are for authenticated users only.
-- ---------------------------------------------------------------------

revoke all on function public.open_month(smallint, smallint, bigint) from public, anon, authenticated;
revoke all on function public.close_month(uuid, bigint) from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.open_month(smallint, smallint, bigint) to authenticated;
grant execute on function public.close_month(uuid, bigint) to authenticated;
