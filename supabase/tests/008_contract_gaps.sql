-- Contract gaps:
--  * entries cannot be moved into or out of a closed month
--  * categories with entries or referenced by templates cannot be deleted
--  * open months are editable (net + split) and close_month uses the
--    edited values; a split not summing to 100 is rejected
create extension if not exists pgtap;

begin;

select plan(11);

-- ----------------------------------------------------------------
-- Fixtures
-- ----------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        '50505050-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
        'p@test.local', 'x', now(), '', '', now(), now());

set role authenticated;
set "request.jwt.claim.sub" = '50505050-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"50505050-0000-0000-0000-00000000000a","role":"authenticated"}';

insert into public.categories (id, user_id, bucket, name)
values
  ('ca500000-0000-0000-0000-000000000001',
   '50505050-0000-0000-0000-00000000000a', 'essential', 'P groceries'),
  ('ca500000-0000-0000-0000-000000000002',
   '50505050-0000-0000-0000-00000000000a', 'essential', 'P templated'),
  ('ca500000-0000-0000-0000-000000000003',
   '50505050-0000-0000-0000-00000000000a', 'fun', 'P empty');

insert into public.recurring_templates
  (id, user_id, category_id, label, amount_cents, day_of_month)
values ('7e500000-0000-0000-0000-000000000001',
        '50505050-0000-0000-0000-00000000000a',
        'ca500000-0000-0000-0000-000000000002', 'P rent', 200000, 5);

-- January: open, add an entry, close. February: open, add an entry.
select public.open_month(2026::smallint, 1::smallint, 300000);
insert into public.entries
  (id, user_id, month_id, category_id, amount_cents, paid_on)
select 'ee500000-0000-0000-0000-000000000001',
       '50505050-0000-0000-0000-00000000000a', m.id,
       'ca500000-0000-0000-0000-000000000001', 4000, '2026-01-10'
from public.months m
where m.user_id = '50505050-0000-0000-0000-00000000000a' and m.month = 1;
select public.close_month(
  (select id from public.months
   where user_id = '50505050-0000-0000-0000-00000000000a' and month = 1), 0);

select public.open_month(2026::smallint, 2::smallint, 300000);
insert into public.entries
  (id, user_id, month_id, category_id, amount_cents, paid_on)
select 'ee500000-0000-0000-0000-000000000002',
       '50505050-0000-0000-0000-00000000000a', m.id,
       'ca500000-0000-0000-0000-000000000001', 2500, '2026-02-10'
from public.months m
where m.user_id = '50505050-0000-0000-0000-00000000000a' and m.month = 2;

-- ----------------------------------------------------------------
-- 1. Entries cannot cross the closed-month boundary in either direction
-- ----------------------------------------------------------------
select throws_ok(
  $$ update entries set month_id =
       (select id from months
        where user_id = '50505050-0000-0000-0000-00000000000a' and month = 1)
     where id = 'ee500000-0000-0000-0000-000000000002' $$,
  'P0001', 'month is closed; entries are read-only',
  'cannot move an entry into a closed month');
select throws_ok(
  $$ update entries set month_id =
       (select id from months
        where user_id = '50505050-0000-0000-0000-00000000000a' and month = 2)
     where id = 'ee500000-0000-0000-0000-000000000001' $$,
  'P0001', 'month is closed; entries are read-only',
  'cannot move an entry out of a closed month');

-- ----------------------------------------------------------------
-- 2. Category deletion is blocked while rows depend on it
-- ----------------------------------------------------------------
select throws_ok(
  $$ delete from categories
     where id = 'ca500000-0000-0000-0000-000000000001' $$,
  '23503', null, 'cannot delete a category that has entries');
select throws_ok(
  $$ delete from categories
     where id = 'ca500000-0000-0000-0000-000000000002' $$,
  '23503', null, 'cannot delete a category referenced by a template');
select lives_ok(
  $$ delete from categories
     where id = 'ca500000-0000-0000-0000-000000000003' $$,
  'can delete a category with no entries or templates');
select is_empty(
  $$ select * from categories
     where id = 'ca500000-0000-0000-0000-000000000003' $$,
  'empty category row is gone');

-- ----------------------------------------------------------------
-- 3. Open months are editable; close_month uses the edited values
-- ----------------------------------------------------------------
select public.open_month(2026::smallint, 3::smallint, 10000);

select lives_ok(
  $$ update months
     set net_income_cents = 20000,
         essential_pct = 55, fun_pct = 25, invest_pct = 20
     where user_id = '50505050-0000-0000-0000-00000000000a'
       and year = 2026 and month = 3 $$,
  'client can edit net income and split on an open month');
select is(
  (select net_income_cents from public.months
   where user_id = '50505050-0000-0000-0000-00000000000a'
     and year = 2026 and month = 3),
  20000::bigint, 'net income edit persisted');

select throws_ok(
  $$ update months set essential_pct = 60, fun_pct = 30, invest_pct = 20
     where user_id = '50505050-0000-0000-0000-00000000000a'
       and year = 2026 and month = 2 $$,
  '23514', null, 'split that does not sum to 100 is rejected');

select lives_ok(
  $$ select public.close_month(
       (select id from months
        where user_id = '50505050-0000-0000-0000-00000000000a'
          and year = 2026 and month = 3), 0) $$,
  'close_month on the edited month');
select is(
  (select array[ms.essential_budget_cents, ms.fun_budget_cents, ms.invest_target_cents]
   from public.month_summaries ms join public.months m on m.id = ms.month_id
   where ms.user_id = '50505050-0000-0000-0000-00000000000a'
     and m.year = 2026 and m.month = 3),
  '{11000,5000,4000}'::bigint[],
  'close uses the edited net (20000) and split (55/25/20)');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
