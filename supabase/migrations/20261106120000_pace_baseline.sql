-- Recalc resets the period's counter: spent_baseline_cents records how much
-- was already spent in the window when the allowance was recomputed, so the
-- display shows allowance - (spent - baseline) instead of double-charging a
-- big purchase against the freshly spread figure. Default 0 keeps the
-- ensure-written rows behaving exactly as before.
alter table public.pace_snapshots
  add column spent_baseline_cents bigint not null default 0;
