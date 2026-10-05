create type bucket as enum ('essential','fun');
create type month_status as enum ('open','closed');
 
create table budget_settings (
  user_id uuid primary key references auth.users on delete cascade,
  essential_pct smallint not null default 50,
  fun_pct smallint not null default 30,
  invest_pct smallint not null default 20,
  check (essential_pct + fun_pct + invest_pct = 100)
);
 
create table months (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  year smallint not null,
  month smallint not null check (month between 1 and 12),
  net_income_cents bigint not null check (net_income_cents >= 0),
  essential_pct smallint not null,
  fun_pct smallint not null,
  invest_pct smallint not null,
  status month_status not null default 'open',
  invested_cents bigint,
  closed_at timestamptz,
  unique (user_id, year, month),
  unique (user_id, id),
  check (essential_pct + fun_pct + invest_pct = 100)
);
 
create table categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  bucket bucket not null,
  name text not null,
  archived boolean not null default false,
  unique (user_id, bucket, name),
  unique (user_id, id)
);
 
create table recurring_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  category_id uuid not null,
  label text not null,
  amount_cents bigint not null check (amount_cents > 0),
  day_of_month smallint not null check (day_of_month between 1 and 31),
  active boolean not null default true,
  unique (user_id, id),
  foreign key (user_id, category_id) references categories (user_id, id)
);
 
create table entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  month_id uuid not null,
  category_id uuid not null,
  amount_cents bigint not null check (amount_cents > 0),
  paid_on date not null,
  note text,
  recurring_template_id uuid,
  created_at timestamptz not null default now(),
  foreign key (user_id, month_id) references months (user_id, id) on delete cascade,
  foreign key (user_id, category_id) references categories (user_id, id),
  foreign key (user_id, recurring_template_id) references recurring_templates (user_id, id)
);
create unique index entries_recurring_once
  on entries (month_id, recurring_template_id) where recurring_template_id is not null;
create index entries_lookup on entries (user_id, month_id, category_id);
 
create table month_summaries (
  month_id uuid primary key references months on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  net_income_cents bigint not null,
  essential_budget_cents bigint not null,
  essential_spent_cents bigint not null,
  fun_budget_cents bigint not null,
  fun_spent_cents bigint not null,
  invest_target_cents bigint not null,
  invested_cents bigint not null,
  created_at timestamptz not null default now()
);
 
-- repeat for every table:
alter table entries enable row level security;
create policy own_rows on entries for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
