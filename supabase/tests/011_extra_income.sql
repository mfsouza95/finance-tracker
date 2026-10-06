-- Extra income: receipts that bypass the split and land 100% in fun.
-- Covers close_month math, the summary column, the closed-month guard,
-- reopen restoring editability, RLS isolation and cascade deletes.
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
values
  ('00000000-0000-0000-0000-000000000000',
   'b2b2b2b2-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
   'u@extras.test', 'x', now(), '', '', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   'b2b2b2b2-0000-0000-0000-00000000000b', 'authenticated', 'authenticated',
   'v@extras.test', 'x', now(), '', '', now(), now());

insert into public.categories (id, user_id, bucket, name)
values
  ('cb200000-0000-0000-0000-000000000001',
   'b2b2b2b2-0000-0000-0000-00000000000a', 'fun', 'U fun');

set role authenticated;
set "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"b2b2b2b2-0000-0000-0000-00000000000a","role":"authenticated"}';

-- U opens 2026-08 with net 10000 (split 50/30/20): fun base = 3000.
-- Two extras (500 + 250) and one fun entry of 3500.
select public.open_month(2026::smallint, 8::smallint, 1000000);
insert into public.extra_income (user_id, month_id, amount_cents, received_on, note)
select 'b2b2b2b2-0000-0000-0000-00000000000a', m.id, x.amount, x.day::date, x.note
from public.months m,
     (values (50000, '2026-08-03'::date, 'Amigo pagou'),
             (25000, '2026-08-12'::date, 'Cashback')) as x(amount, day, note)
where m.user_id = 'b2b2b2b2-0000-0000-0000-00000000000a' and m.month = 8;
insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select 'b2b2b2b2-0000-0000-0000-00000000000a', m.id,
       'cb200000-0000-0000-0000-000000000001', 350000, '2026-08-10'
from public.months m
where m.user_id = 'b2b2b2b2-0000-0000-0000-00000000000a' and m.month = 8;

-- ----------------------------------------------------------------
-- close_month: fun budget = base 3000 + extras 750 = 3750,
-- rest = 3750 - 3500 = 250. extra_income_cents = 75000.
-- ----------------------------------------------------------------
select public.close_month(
  (select id from public.months
   where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a' and month = 8), 0);

select is(
  (select fun_budget_cents from public.month_summaries
   where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a'),
  375000::bigint, 'fun budget = base split + extras');

select is(
  (select fun_rest_cents from public.month_summaries
   where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a'),
  25000::bigint, 'fun rest subtracts spent from the extras-boosted budget');

select is(
  (select extra_income_cents from public.month_summaries
   where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a'),
  75000::bigint, 'summary records the extras total');

select is(
  (select essential_budget_cents from public.month_summaries
   where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a'),
  500000::bigint, 'essential budget is untouched by extras');

-- ----------------------------------------------------------------
-- Closed month: extras are read-only in all directions.
-- ----------------------------------------------------------------
select throws_ok(
  $$ insert into public.extra_income (user_id, month_id, amount_cents, received_on)
     select 'b2b2b2b2-0000-0000-0000-00000000000a', m.id, 1000, '2026-08-20'
     from public.months m
     where m.user_id = 'b2b2b2b2-0000-0000-0000-00000000000a' and m.month = 8 $$,
  'P0001', 'month is closed; extra income is read-only',
  'insert into a closed month is blocked');

select throws_ok(
  $$ update public.extra_income set amount_cents = 99999
     where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a' $$,
  'P0001', 'month is closed; extra income is read-only',
  'update in a closed month is blocked');

select throws_ok(
  $$ delete from public.extra_income
     where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a' $$,
  'P0001', 'month is closed; extra income is read-only',
  'delete in a closed month is blocked');

-- Reopen restores full editability on extras too.
select public.reopen_month(
  (select id from public.months
   where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a' and month = 8));
select lives_ok(
  $$ delete from public.extra_income
     where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a' and note = 'Cashback' $$,
  'extras are editable again after reopen_month');

-- ----------------------------------------------------------------
-- RLS: V cannot see or write U's extras.
-- ----------------------------------------------------------------
set "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-00000000000b';
set "request.jwt.claims" =
  '{"sub":"b2b2b2b2-0000-0000-0000-00000000000b","role":"authenticated"}';

select is(
  (select count(*)::int from public.extra_income),
  0, 'second user sees none of the first user''s extras');

select throws_ok(
  $$ insert into public.extra_income
     (user_id, month_id, amount_cents, received_on)
     values ('b2b2b2b2-0000-0000-0000-00000000000a',
             gen_random_uuid(), 1000, '2026-08-01') $$,
  '42501', null,
  'second user cannot insert extras under another user_id');

-- ----------------------------------------------------------------
-- Open-month delete cascades extras (as superuser so RLS is out of
-- the way; the cascade fires at trigger depth > 1 and is allowed).
-- ----------------------------------------------------------------
reset role;
delete from public.months
where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a' and month = 8;
select is(
  (select count(*)::int from public.extra_income
   where user_id = 'b2b2b2b2-0000-0000-0000-00000000000a'),
  0, 'deleting an open month cascades its extras');

reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
