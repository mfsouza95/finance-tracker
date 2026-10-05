-- open_month: creation, split snapshot, idempotent recurring generation,
-- short-month day clamping, input validation.
create extension if not exists pgtap;

begin;

select plan(26);

-- ----------------------------------------------------------------
-- Fixtures
-- ----------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        'cccccccc-0000-0000-0000-00000000000c', 'authenticated', 'authenticated',
        'c@test.local', 'x', now(), '', '', now(), now());

insert into public.categories (id, user_id, bucket, name)
values
  ('cc100000-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-00000000000c', 'essential', 'Housing'),
  ('cc100000-0000-0000-0000-000000000002',
   'cccccccc-0000-0000-0000-00000000000c', 'fun', 'Streaming');

insert into public.recurring_templates
  (id, user_id, category_id, label, amount_cents, day_of_month, active)
values
  ('ff100000-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-00000000000c',
   'cc100000-0000-0000-0000-000000000001', 'Rent', 250000, 31, true),
  ('ff100000-0000-0000-0000-000000000002',
   'cccccccc-0000-0000-0000-00000000000c',
   'cc100000-0000-0000-0000-000000000002', 'Streaming plan', 5000, 15, true),
  ('ff100000-0000-0000-0000-000000000003',
   'cccccccc-0000-0000-0000-00000000000c',
   'cc100000-0000-0000-0000-000000000001', 'Old template', 1000, 10, false);

-- ----------------------------------------------------------------
-- Act as user C
-- ----------------------------------------------------------------
set role authenticated;
set "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-00000000000c';
set "request.jwt.claims" =
  '{"sub":"cccccccc-0000-0000-0000-00000000000c","role":"authenticated"}';

select lives_ok(
  $$ select public.open_month(2026::smallint, 2::smallint, 500000) $$,
  'open_month creates the month');

select is(
  (select count(*)::int from public.months
   where user_id = 'cccccccc-0000-0000-0000-00000000000c'),
  1, 'exactly one month row created');

select is(
  (select array[essential_pct, fun_pct, invest_pct] from public.months
   where user_id = 'cccccccc-0000-0000-0000-00000000000c' and year = 2026 and month = 2),
  '{50,30,20}'::smallint[], 'split snapshotted from budget_settings');

select is(
  (select status::text from public.months
   where user_id = 'cccccccc-0000-0000-0000-00000000000c'),
  'open', 'month starts open');

select is(
  (select count(*)::int from public.entries
   where user_id = 'cccccccc-0000-0000-0000-00000000000c'),
  2, 'one entry per active template (inactive skipped)');

select is(
  (select e.paid_on from public.entries e
   where e.recurring_template_id = 'ff100000-0000-0000-0000-000000000001'),
  '2026-02-28'::date, 'day 31 clamps to Feb 28');

select is(
  (select e.paid_on from public.entries e
   where e.recurring_template_id = 'ff100000-0000-0000-0000-000000000002'),
  '2026-02-15'::date, 'day 15 stays day 15');

select is(
  (select e.note from public.entries e
   where e.recurring_template_id = 'ff100000-0000-0000-0000-000000000001'),
  'Rent', 'template label copied to entry note');

-- Idempotency: second call must not duplicate months or entries.
select lives_ok(
  $$ select public.open_month(2026::smallint, 2::smallint, 999999) $$,
  'open_month is callable a second time');

select is(
  (select count(*)::int from public.entries
   where user_id = 'cccccccc-0000-0000-0000-00000000000c'),
  2, 're-running open_month does not duplicate entries');

select is(
  (select count(*)::int from public.months
   where user_id = 'cccccccc-0000-0000-0000-00000000000c'),
  1, 're-running open_month does not duplicate the month');

select is(
  (select net_income_cents from public.months
   where user_id = 'cccccccc-0000-0000-0000-00000000000c'),
  500000::bigint, 'existing month keeps original net income');

-- A template added after the month exists generates nothing on re-run.
insert into public.recurring_templates
  (id, user_id, category_id, label, amount_cents, day_of_month, active)
values ('ff100000-0000-0000-0000-000000000004',
        'cccccccc-0000-0000-0000-00000000000c',
        'cc100000-0000-0000-0000-000000000002', 'Gym', 9000, 5, true);

select lives_ok(
  $$ select public.open_month(2026::smallint, 2::smallint, 500000) $$,
  're-running open_month after adding a template');

select is_empty(
  $$ select * from entries
     where recurring_template_id = 'ff100000-0000-0000-0000-000000000004' $$,
  'existing month generates nothing for new templates');

-- Deleting a generated entry survives re-runs: generation only happens
-- when the month row is created.
select lives_ok(
  $$ delete from public.entries
     where recurring_template_id = 'ff100000-0000-0000-0000-000000000002' $$,
  'delete a generated entry in the open month');

select lives_ok(
  $$ select public.open_month(2026::smallint, 2::smallint, 500000) $$,
  're-running open_month after deleting an entry');

select is_empty(
  $$ select * from entries
     where recurring_template_id = 'ff100000-0000-0000-0000-000000000002' $$,
  'deleted generated entry stays deleted');

select is(
  (select count(*)::int from public.entries e
   join public.months m on m.id = e.month_id
   where m.user_id = 'cccccccc-0000-0000-0000-00000000000c'
     and m.year = 2026 and m.month = 2),
  1, 'February keeps exactly the remaining entry');

-- April has 30 days: day 31 clamps to 30.
select lives_ok(
  $$ select public.open_month(2026::smallint, 4::smallint, 400000) $$,
  'open_month April');

select is(
  (select e.paid_on from public.entries e
   join public.months m on m.id = e.month_id
   where e.recurring_template_id = 'ff100000-0000-0000-0000-000000000001'
     and m.year = 2026 and m.month = 4),
  '2026-04-30'::date, 'day 31 clamps to Apr 30');

-- Templates on archived categories are skipped at generation time.
insert into public.categories (id, user_id, bucket, name, archived)
values ('cc100000-0000-0000-0000-000000000003',
        'cccccccc-0000-0000-0000-00000000000c', 'essential', 'Old flat', true);
insert into public.recurring_templates
  (id, user_id, category_id, label, amount_cents, day_of_month, active)
values ('ff100000-0000-0000-0000-000000000005',
        'cccccccc-0000-0000-0000-00000000000c',
        'cc100000-0000-0000-0000-000000000003', 'Old rent', 3000, 20, true);

-- Snapshot uses settings at open time, not later edits.
update public.budget_settings
set essential_pct = 55, fun_pct = 25, invest_pct = 20
where user_id = 'cccccccc-0000-0000-0000-00000000000c';

select lives_ok(
  $$ select public.open_month(2026::smallint, 5::smallint, 100000) $$,
  'open_month May after settings change');

select is(
  (select array[essential_pct, fun_pct, invest_pct] from public.months
   where user_id = 'cccccccc-0000-0000-0000-00000000000c' and year = 2026 and month = 5),
  '{55,25,20}'::smallint[], 'new month snapshots the updated split');

select is(
  (select count(*)::int from public.entries e
   join public.months m on m.id = e.month_id
   where m.user_id = 'cccccccc-0000-0000-0000-00000000000c'
     and m.year = 2026 and m.month = 5),
  3, 'new month generates entries for active templates incl. mid-month additions');

select is_empty(
  $$ select e.* from public.entries e
     join public.months m on m.id = e.month_id
     where e.recurring_template_id = 'ff100000-0000-0000-0000-000000000005'
       and m.year = 2026 and m.month = 5 $$,
  'template on archived category is skipped');

select throws_ok(
  $$ select public.open_month(2026::smallint, 13::smallint, 100000) $$,
  'P0001', 'month must be between 1 and 12',
  'open_month rejects month = 13');
select throws_ok(
  $$ select public.open_month(2026::smallint, 6::smallint, -5) $$,
  'P0001', 'net_income_cents must be >= 0',
  'open_month rejects negative net income');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
