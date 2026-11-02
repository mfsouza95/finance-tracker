-- Pace snapshots: the dashboard pod shows a per-day and per-week spending
-- allowance for the latest open month. Each figure is FIXED for its period
-- (midnight for 'day', Monday for 'week'), so it must be stored: the
-- manual "recalcular" button overwrites the rows, which a pure derivation
-- could never express.
--
-- One row per (month, kind, scope, period_start):
--   kind  'day'/'week' — which figure
--   scope 'all'/'essential'/'fun' — the pod's bucket filter has its own
--         fixed allowance per period
--   period_start  the period's first day (today itself for 'day', the
--         Monday for 'week')
--   allowance_cents  the fixed figure; spent subtracts live at render time
--
-- Clients upsert directly under RLS — a snapshot is a sum and a division,
-- nothing multi-row to make atomic, so no RPC. The ensure path uses an
-- ignore-duplicates upsert (first write wins between racing tabs); the
-- recalc path overwrites.

create table public.pace_snapshots (
  month_id uuid not null,
  kind text not null check (kind in ('day', 'week')),
  scope text not null check (scope in ('all', 'essential', 'fun')),
  period_start date not null,
  user_id uuid not null references auth.users on delete cascade,
  allowance_cents bigint not null,
  computed_at timestamptz not null default now(),
  primary key (month_id, kind, scope, period_start),
  foreign key (user_id, month_id)
    references public.months (user_id, id) on delete cascade
);

alter table public.pace_snapshots enable row level security;

create policy own_rows on public.pace_snapshots for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
