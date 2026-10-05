-- close_month: summary values, rounding (buckets sum to net), several
-- splits including 55/25/20, closed-month write block, integrity guards.
create extension if not exists pgtap;

begin;

select plan(35);

-- ----------------------------------------------------------------
-- Fixtures: three users
-- ----------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000',
   'dddddddd-0000-0000-0000-00000000000d', 'authenticated', 'authenticated',
   'd@test.local', 'x', now(), '', '', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   'eeeeeeee-0000-0000-0000-00000000000e', 'authenticated', 'authenticated',
   'e@test.local', 'x', now(), '', '', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   'ffffffff-0000-0000-0000-00000000000f', 'authenticated', 'authenticated',
   'f@test.local', 'x', now(), '', '', now(), now());

insert into public.categories (id, user_id, bucket, name)
values
  ('cc200000-0000-0000-0000-000000000001',
   'dddddddd-0000-0000-0000-00000000000d', 'essential', 'Groceries'),
  ('cc200000-0000-0000-0000-000000000002',
   'dddddddd-0000-0000-0000-00000000000d', 'fun', 'Eating out'),
  ('cc200000-0000-0000-0000-000000000003',
   'eeeeeeee-0000-0000-0000-00000000000e', 'essential', 'Bills'),
  ('cc200000-0000-0000-0000-000000000004',
   'ffffffff-0000-0000-0000-00000000000f', 'essential', 'Rent');

-- ----------------------------------------------------------------
-- User D: split 50/30/20, net = 10003 (odd cents -> exercises rounding)
-- ----------------------------------------------------------------
set role authenticated;
set "request.jwt.claim.sub" = 'dddddddd-0000-0000-0000-00000000000d';
set "request.jwt.claims" =
  '{"sub":"dddddddd-0000-0000-0000-00000000000d","role":"authenticated"}';

select public.open_month(2026::smallint, 3::smallint, 10003);

insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select 'dddddddd-0000-0000-0000-00000000000d', m.id,
       'cc200000-0000-0000-0000-000000000001', 4000, '2026-03-05'
from public.months m
where m.user_id = 'dddddddd-0000-0000-0000-00000000000d' and m.year = 2026 and m.month = 3;

insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select 'dddddddd-0000-0000-0000-00000000000d', m.id,
       'cc200000-0000-0000-0000-000000000002', amount, '2026-03-10'
from public.months m,
     (values (2000), (1500)) as v(amount)
where m.user_id = 'dddddddd-0000-0000-0000-00000000000d' and m.year = 2026 and m.month = 3;

-- expected: essential = floor(10003*0.5) = 5001, fun = floor(10003*0.3) = 3000,
-- invest_target = 10003 - 5001 - 3000 = 2002
-- rests: 5001 - 4000 = 1001 ; 3000 - 3500 = -500
-- expected invest = 2002 + 1001 - 500 = 2503 -> user confirms 2503
select lives_ok(
  $$ select public.close_month(
       (select id from months where user_id = 'dddddddd-0000-0000-0000-00000000000d'
        and year = 2026 and month = 3), 2503) $$,
  'close_month succeeds');

select is(
  (select ms.net_income_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 3
     and ms.user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  10003::bigint, 'summary stores net income');

select is(
  (select essential_budget_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 3
     and ms.user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  5001::bigint, 'essential budget = floor(net * 50/100)');

select is(
  (select fun_budget_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 3
     and ms.user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  3000::bigint, 'fun budget = floor(net * 30/100)');

select is(
  (select invest_target_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 3
     and ms.user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  2002::bigint, 'invest target absorbs rounding remainder');

select is(
  (select essential_budget_cents + fun_budget_cents + invest_target_cents
   from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 3
     and ms.user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  10003::bigint, 'three buckets always sum to net');

select is(
  (select essential_spent_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 3
     and ms.user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  4000::bigint, 'essential spent sums entries');

select is(
  (select fun_spent_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 3
     and ms.user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  3500::bigint, 'fun spent sums entries');

select is(
  (select essential_rest_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 3
     and ms.user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  1001::bigint, 'essential rest = budget - spent');

select is(
  (select fun_rest_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 3
     and ms.user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  (-500)::bigint, 'fun rest goes negative when overspent');

select is(
  (select ms.invested_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 3
     and ms.user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  2503::bigint, 'invested stored as confirmed by user');

select is(
  (select status::text from public.months
   where user_id = 'dddddddd-0000-0000-0000-00000000000d' and year = 2026 and month = 3),
  'closed', 'month marked closed');

select ok(
  (select closed_at is not null from public.months
   where user_id = 'dddddddd-0000-0000-0000-00000000000d' and year = 2026 and month = 3),
  'closed_at set');

select is(
  (select invested_cents from public.months
   where user_id = 'dddddddd-0000-0000-0000-00000000000d' and year = 2026 and month = 3),
  2503::bigint, 'invested_cents stored on the month');

-- ----------------------------------------------------------------
-- Closed-month write block (still as D)
-- ----------------------------------------------------------------
select throws_ok(
  $$ insert into entries (user_id, month_id, category_id, amount_cents, paid_on)
     select 'dddddddd-0000-0000-0000-00000000000d', m.id,
            'cc200000-0000-0000-0000-000000000001', 100, '2026-03-20'
     from months m where m.user_id = 'dddddddd-0000-0000-0000-00000000000d'
       and m.year = 2026 and m.month = 3 $$,
  'P0001', 'month is closed; entries are read-only',
  'cannot insert entry into closed month');

select throws_ok(
  $$ update entries set amount_cents = 999
     where user_id = 'dddddddd-0000-0000-0000-00000000000d' $$,
  'P0001', 'month is closed; entries are read-only',
  'cannot update entry in closed month');

select throws_ok(
  $$ delete from entries
     where user_id = 'dddddddd-0000-0000-0000-00000000000d' $$,
  'P0001', 'month is closed; entries are read-only',
  'cannot delete entry in closed month');

select throws_ok(
  $$ update months set net_income_cents = 1
     where user_id = 'dddddddd-0000-0000-0000-00000000000d'
       and year = 2026 and month = 3 $$,
  'P0001', 'closed months are read-only',
  'cannot edit net income of closed month');

select throws_ok(
  $$ update months set status = 'open'
     where user_id = 'dddddddd-0000-0000-0000-00000000000d'
       and year = 2026 and month = 3 $$,
  'P0001', 'closed months are read-only',
  'cannot reopen a closed month');

select throws_ok(
  $$ delete from months
     where user_id = 'dddddddd-0000-0000-0000-00000000000d'
       and year = 2026 and month = 3 $$,
  'P0001', 'closed months cannot be deleted',
  'cannot delete a closed month');

select throws_ok(
  $$ select public.close_month(
       (select id from months where user_id = 'dddddddd-0000-0000-0000-00000000000d'
        and year = 2026 and month = 3), 100) $$,
  'P0001', 'month is already closed',
  'close_month rejects already-closed month');

select throws_ok(
  $$ select public.open_month(2026::smallint, 3::smallint, 5000) $$,
  'P0001', 'month 2026-3 is already closed',
  'open_month rejects a closed month');

select is(
  (select count(*)::int from public.entries
   where user_id = 'dddddddd-0000-0000-0000-00000000000d'),
  3, 'entries in closed month remain readable');

-- ----------------------------------------------------------------
-- Integrity: status can only become 'closed' through close_month()
-- ----------------------------------------------------------------
-- Explicit id so user F can later attempt close_month on a real foreign month.
insert into public.months
  (id, user_id, year, month, net_income_cents, essential_pct, fun_pct, invest_pct)
values ('dd300000-0000-0000-0000-0000000000d6',
        'dddddddd-0000-0000-0000-00000000000d', 2026, 6, 200000, 50, 30, 20);

select throws_ok(
  $$ update months set status = 'closed'
     where id = 'dd300000-0000-0000-0000-0000000000d6' $$,
  'P0001', 'use close_month() to close a month',
  'direct status flip to closed is blocked (no summary)');

select throws_ok(
  $$ insert into months
       (user_id, year, month, net_income_cents,
        essential_pct, fun_pct, invest_pct, status, closed_at, invested_cents)
     values ('dddddddd-0000-0000-0000-00000000000d', 2026, 7, 1,
             50, 30, 20, 'closed', now(), 0) $$,
  'P0001', 'new months must be open; use close_month() to close',
  'cannot insert a month already closed');

-- ----------------------------------------------------------------
-- User E: split 55/25/20, net = 9999 (rounding again)
-- ----------------------------------------------------------------
set "request.jwt.claim.sub" = 'eeeeeeee-0000-0000-0000-00000000000e';
set "request.jwt.claims" =
  '{"sub":"eeeeeeee-0000-0000-0000-00000000000e","role":"authenticated"}';

update public.budget_settings
set essential_pct = 55, fun_pct = 25, invest_pct = 20
where user_id = 'eeeeeeee-0000-0000-0000-00000000000e';

select public.open_month(2026::smallint, 5::smallint, 9999);

insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select 'eeeeeeee-0000-0000-0000-00000000000e', m.id,
       'cc200000-0000-0000-0000-000000000003', 3000, '2026-05-02'
from public.months m
where m.user_id = 'eeeeeeee-0000-0000-0000-00000000000e' and m.year = 2026 and m.month = 5;

select lives_ok(
  $$ select public.close_month(
       (select id from months where user_id = 'eeeeeeee-0000-0000-0000-00000000000e'
        and year = 2026 and month = 5), 4500) $$,
  'close_month succeeds for 55/25/20 split');

-- floor(9999*0.55) = 5499 ; floor(9999*0.25) = 2499 ; invest = 9999-5499-2499 = 2001
select is(
  (select array[essential_budget_cents, fun_budget_cents, invest_target_cents]
   from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 5
     and ms.user_id = 'eeeeeeee-0000-0000-0000-00000000000e'),
  '{5499,2499,2001}'::bigint[], '55/25/20 buckets match computeBuckets');

select is(
  (select essential_budget_cents + fun_budget_cents + invest_target_cents
   from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 5
     and ms.user_id = 'eeeeeeee-0000-0000-0000-00000000000e'),
  9999::bigint, 'buckets sum to net for 55/25/20');

select is(
  (select essential_rest_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where m.year = 2026 and m.month = 5
     and ms.user_id = 'eeeeeeee-0000-0000-0000-00000000000e'),
  2499::bigint, 'essential rest for 55/25/20 = 5499 - 3000');

-- ----------------------------------------------------------------
-- User F: isolation + validation of close_month
-- ----------------------------------------------------------------
set "request.jwt.claim.sub" = 'ffffffff-0000-0000-0000-00000000000f';
set "request.jwt.claims" =
  '{"sub":"ffffffff-0000-0000-0000-00000000000f","role":"authenticated"}';

-- F passes D's real month id: the row exists but is not F's, so
-- close_month must report 'month not found' and change nothing.
select throws_ok(
  $$ select public.close_month(
       'dd300000-0000-0000-0000-0000000000d6'::uuid, 100) $$,
  'P0001', 'month not found',
  'cannot close another user''s month (real id, ownership enforced)');

select throws_ok(
  $$ select public.close_month(
       '00000000-0000-0000-0000-00000000dead'::uuid, 100) $$,
  'P0001', 'month not found',
  'close_month rejects unknown month id');

select public.open_month(2026::smallint, 8::smallint, 100000);

select throws_ok(
  $$ select public.close_month(
       (select id from months where user_id = 'ffffffff-0000-0000-0000-00000000000f'
        and year = 2026 and month = 8), -1) $$,
  'P0001', 'invested_cents must be >= 0',
  'close_month rejects negative invested amount');

select is(
  (select count(*)::int from public.month_summaries
   where user_id = 'ffffffff-0000-0000-0000-00000000000f'),
  0, 'failed closes write no summary');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

-- Verified as superuser: F's failed close left D's month untouched.
select is(
  (select status::text from public.months
   where id = 'dd300000-0000-0000-0000-0000000000d6'),
  'open', 'D''s month still open after F''s close attempt');
select is_empty(
  $$ select * from month_summaries
     where month_id = 'dd300000-0000-0000-0000-0000000000d6' $$,
  'no summary written for D''s month');

select * from finish();
rollback;
