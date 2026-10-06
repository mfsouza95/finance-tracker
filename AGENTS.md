# Personal Finance App

Working title. A personal budgeting app that replaces a Google Sheet: net income is split 50/30/20 into buckets, expenses are logged by category, recurring items are generated automatically, and each month is closed into a stored summary. Built as a personal project but structured like a real product, and shared with a small group (5 to 10 people), so it is **multi-user from day one**.

Full plan: `docs/PROJECT_PLAN.docx` (human-readable). This file is the working context for coding agents. If they disagree, ask before deviating.

## Stack

- **Frontend:** React + Vite + TypeScript, shipped as an installable PWA (`vite-plugin-pwa`). No Next.js, no SSR.
- **UI:** Tailwind + shadcn/ui (Radix), TanStack Table, Recharts.
- **Data:** TanStack Query (persisted cache), `@supabase/supabase-js`.
- **Forms/validation:** react-hook-form + Zod.
- **Backend:** Supabase (Postgres, Auth, RLS, Realtime). No custom server. Business logic that must be atomic lives in SQL functions (RPC).
- **Tests:** Vitest (unit) and SQL tests for RLS and RPCs first. Playwright e2e is added after the first month of real use.
- **Hosting/CI:** Cloudflare Pages or Vercel, GitHub Actions. Target cost: US$0/month.
- **Database decision is not final:** Supabase is the recommendation, Neon the alternative. Keep the schema plain Postgres so either works.

## Commands

Adjust once the project is scaffolded.

```bash
pnpm install
pnpm dev            # Vite dev server
pnpm typecheck      # tsc --noEmit
pnpm lint
pnpm test           # Vitest
pnpm test:e2e       # Playwright
pnpm build
supabase start      # local Supabase
supabase db reset   # re-apply migrations + seed locally
supabase migration new <name>
```

## Suggested structure

```
src/
  app/              routes, layouts (desktop and mobile)
  features/
    entries/ categories/ months/ recurring/ dashboard/ history/
  components/ui/    shadcn components
  lib/              money.ts, dates.ts, supabase.ts, query client
supabase/
  migrations/       versioned SQL (source of truth for schema)
  tests/            SQL tests (RLS, open_month, close_month)
  seed.sql
docs/
  PROJECT_PLAN.docx
```

## Domain rules (do not break)

1. **Money is integer cents** (`bigint` in DB, `number` of cents in TS). Never use floats for money. One formatter (`Intl.NumberFormat`, pt-BR, BRL) for display.
2. **Buckets from net income:** `essential = floor(net * essential_pct / 100)`, `fun = floor(net * fun_pct / 100)`, `invest_target = net - essential - fun` (absorbs rounding so the three always sum to net). Default split 50/30/20, configurable. Percentages are snapshotted on the month when it is opened.
3. **Rest per bucket** = bucket budget minus sum of entries in that bucket. There are **no per-category limits**. Rest `>= 0` is positive (green), negative is overspent (red).
4. **Month total to spend** = `net - invest_target`.
5. **Expected investment** = `invest_target + essential_rest + fun_rest` (leftover flows into investment; overspending reduces it).
6. **Grouping is a query, not stored data.** A category row shows `SUM(amount)` and `COUNT(*)` of its entries and expands to show each entry. Each purchase is always its own row.
7. **Recurrence is template-based and idempotent.** `recurring_templates` hold category, amount and day of month. Opening a month runs `open_month`, which inserts one entry per active template with `ON CONFLICT DO NOTHING` against the partial unique index on `(month_id, recurring_template_id)`. Use `least(day_of_month, last_day_of_month)` for short months. No cron job.
8. **Closing a month never deletes data.** `close_month` computes and writes `month_summaries` (month/year, net, spent per bucket, rest, invested), sets `status = 'closed'`, and the month becomes read-only (enforced by a trigger). The next month starts with only recurring entries.
9. **Invested amount** is confirmed by the user at close, defaulting to expected investment. (Open decision: whether to track investments as separate entries.)
10. **Bucket calculation is one pure function:** `computeBuckets(net, split)`. The dashboard, month close and the future simulator all use it. Do not duplicate bucket math anywhere else (components, SQL, scripts), except where `close_month` must reproduce it in SQL, in which case a test must assert both give identical results for every preset.
11. **Splits:** percentage-based over three fixed buckets (essential, fun, invest) in v1. The user can edit the split (e.g. 55/25/20) or pick a preset (50/30/20, 55/25/20, 60/20/20, 70/20/10). Presets are constants in client code, not a table. Percentages must sum to 100. Editing the split on an **open** month is allowed; **closed** months never change.
12. **What-if simulator (post-MVP):** runs client-side with a draft split against the current month's real entries and persists nothing unless the user applies the split.
13. **Other strategy shapes are out of scope for now** (custom bucket count, zero-based, envelopes). If needed later, buckets become user-defined rows referenced by categories; the isolated calculation function keeps that migration contained. Do not build for it in advance.

## Data model (summary)

`profiles`, `budget_settings`, `months`, `categories` (bucket: essential | fun), `entries`, `recurring_templates`, `month_summaries`. Every table has `user_id`. Full draft DDL is in Appendix A of the plan; migrations in `supabase/migrations/` are the source of truth.

## Security rules

- **RLS enabled on every table**, policy `(select auth.uid()) = user_id` for both `USING` and `WITH CHECK`. Never create a table without RLS.
- Foreign keys must not allow pointing at another user's rows: use composite FKs `(user_id, id)` or verify ownership in `WITH CHECK`.
- Only the public anon key is used in the client. **The service-role key never goes in client code or the repo.**
- Secrets live in hosting/CI environment variables. Never commit `.env` files; keep `.env.example` with placeholder names only.
- Do not log financial data (amounts, categories, notes) to the console, Sentry or analytics.
- Schema changes go through migrations only. Never edit the production database by hand.

## Design system

- Design tokens as CSS variables (colour, spacing, radius, type scale). Dark mode by redefining tokens.
- Semantic tokens `--positive` and `--negative`; never hardcode green/red in components. Pair colour with an icon or sign.
- **Desktop (>= 1024 px):** three-panel dashboard (summary, essential, fun), expandable rows, inline editing.
- **Mobile (< 768 px):** summary card, tabs (Essential / Fun / History), floating add button opening a bottom sheet. Adding an entry must take about two taps.
- Same data layer and shared components across both layouts; only the layout differs.
- Use tabular numerals for money. Default UI language pt-BR, keep strings i18n-ready for English.

## Testing requirements

- Any change to money math, bucket split, recurrence or month close **must ship with tests**.
- Unit: split and rounding, rest and expected-investment formulas, day clamping.
- SQL: `open_month` idempotency, `close_month` values, RLS isolation between two users, closed-month write block.
- Unit: `computeBuckets` is tested for every preset and for rounding edge cases (sums always equal net).
- E2E (add after the first month of real use): sign in, add entry, grouped total updates, close month, history shows summary.

## Conventions

- TypeScript strict mode. No `any` without a comment explaining why.
- Validate all external input with Zod; share schemas between forms and API payloads.
- Prefer small feature folders over global utility dumping grounds.
- Small, focused commits and PRs; every PR runs typecheck, lint, tests and build in CI.
- Do not add dependencies without a clear reason; prefer what is already in the stack.
- Ask before: changing the money model, changing the bucket model (e.g. custom buckets), changing RLS policies, adding a backend service, or switching database.

## Roadmap

1. **Foundation:** repo, CI, Supabase projects (dev and prod), schema + RLS, auth, design tokens, app shell.
2. **MVP core:** categories, entries, grouped totals, dashboard, editable split with presets, one-tap add, backup and keepalive jobs. **Checkpoint:** the owner runs it in parallel with the Google Sheet for a month and compares numbers.
3. **Recurrence:** templates UI, `open_month`, idempotent generation.
4. **Month close:** `close_month`, summaries, history, read-only closed months.
5. **Polish:** PWA install, what-if simulator, charts, realtime sync, Playwright e2e, CSV import (optional).
6. **Sharing:** invite friends and family after 1 to 2 months of solo use; onboarding and delete-account path.
7. **Optional:** offline write queue, Tauri desktop wrapper, budget alerts, other strategy shapes. See also Future feature ideas below.

## Future feature ideas (not committed — do not build yet)

Parked ideas to be designed together before any implementation. Both touch the money model, so they need design review first (per Conventions).

### Daily / weekly allowance ("pace" counter)

- Shows how much can still be spent per day and per week, derived from what is left of the month's budget.
- The daily amount is a fixed number set at midnight; the weekly amount is fixed each Monday. Neither moves during the day as entries are logged — the number only changes on the next reset.
- Busting the limit shows the counter negative in red (`--negative` token), so the overspend amount stays visible.
- Week boundaries clip at month end: the last day of the month counts as the last day of that week, and the allowance resets on the 1st of the next month even when it is not a Monday.
- **Manual recalculation:** a "recalculate" button recomputes the daily/weekly figure now (e.g. after a big planned expense or piggy-bank deposit that would otherwise bust the allowance) instead of waiting for the next reset. It refreshes the allowance amount but does NOT reset the counter — what was already spent today/this week is still subtracted, so the display shows `new_allowance - spent_in_period`, which can be negative right away.
- To settle before building: which budget it derives from (fun bucket? month total to spend?); how the fixed figure is computed (e.g. remaining ÷ remaining days in the period); whether it needs a stored per-day/per-week snapshot or derives client-side; whose timezone defines "midnight"/"Monday" for a multi-user app; whether a manual recalculation also refreshes the weekly figure, only the daily one, or both separately.

### Bank and piggy bank

- **Bank:** a named reserve fed by setting aside part of the monthly budget. It can later be activated for an occasion (e.g. a trip): entries tagged to that occasion draw from the bank balance first; once the bank hits zero, further entries count against the month's bucket budget again.
- **Piggy bank:** goal tracking for a planned purchase — set aside a labelled amount and track progress toward the goal.
- To settle before building: whether feeding a bank/piggy bank counts as spending at feed time or at spend time; whether entries get an optional fund link (schema change affecting rest math, `close_month` and summaries); how bank balances interact with expected investment; whether piggy-bank savings live inside the invest bucket or outside the split entirely.

## Scope discipline

- Multi-user is in the schema from day one (`user_id` + RLS), but the app is used alone first.
- Do not delay phases 3 and 4: recurrence and month close are the main reasons to leave the sheet.
- Do not build early: simulator, custom strategies, charts, realtime, i18n beyond keeping strings extractable, custom design work beyond tokens plus shadcn defaults.
- Do not skip: money tests, RLS tests, idempotent `open_month`, the backup job.

## Operations notes

- Supabase free projects pause after 7 days of inactivity: keep a scheduled GitHub Action pinging the prod project every few days.
- Free tier has no automatic backups: keep a scheduled export and test a restore once.
- Free-tier terms change; re-check pricing pages before relying on them.

## Open decisions

App name; UI language default; how to track invested amounts (decision so far: allowed to edit the split on an open month); sign-in methods (proposed: email magic link plus Google); final database choice (Supabase recommended).

## Database contract (do not undo)

- Clients create, close and reopen months only through the RPCs `open_month(year, month, net)`, `close_month(month_id, invested)` and `reopen_month(month_id)`. Never insert a closed month or change `status` directly.
- `open_month` generates recurring entries only when it creates the month. Calling it for an existing open month returns it unchanged and ignores the net amount. Change net income with a normal update on `months`. Deleted generated entries are never brought back. Templates on archived categories are skipped.
- Templates are created via `create_recurring_template`, which also backfills entries into already-open months: bounded plans into every open month inside their window, unbounded templates only into open months from the creation month onward (a reopened past month never gains a retroactive entry). Closed months are never written to.
- **Extra income** (`extra_income` table) is unplanned money received mid-month — it bypasses the split and lands 100% in the fun bucket. Each receipt is its own row (amount, received_on, note), read-only when the month closes, cascades on open-month delete. `close_month` adds the extras total to `fun_budget_cents` and records `month_summaries.extra_income_cents`, so unspent extras still flow into expected investment via fun rest.
- **Installments (parcelas)** are bounded templates: `installments_total` + `first_year`/`first_month` set, or all three null for indefinite recurrence. The installment index is position-based (`months elapsed since first + 1`), not a counter — skipped or backfilled months never shift numbering, and a closed month inside the window is skipped (its installment is never written unless the month is reopened and the entry added manually). Generated entries carry `entries.installment_index` (null for unbounded). Cancel/early payoff = `active = false`; reactivating resumes at the correct position.
- `close_month` is SECURITY DEFINER and is the only writer of `month_summaries`, which is read-only for clients. `reopen_month` (also SECURITY DEFINER) is the only way back: it deletes the summary row and sets the month open, clearing `closed_at`/`invested_cents`. Re-closing recomputes the summary from current data.
- Closed months and their entries are read-only until reopened via `reopen_month`. A direct client delete of a closed month or entry is rejected. Deleting a recurring template nulls the link on its entries, even in closed months. Deleting an open month cascades its entries.
- `categories.bucket` cannot change once the category has entries. Categories and templates with history are archived or deactivated, not deleted.
- `profiles` and `budget_settings` are created at signup and are select and update only for clients.
- Execute on `open_month`, `close_month`, `reopen_month` and `create_recurring_template` is granted to `authenticated` only.
- Migrations and pgTAP tests in `supabase/` are the source of truth. Any schema change ships with tests. Run `supabase db reset` and `supabase test db` before every commit.