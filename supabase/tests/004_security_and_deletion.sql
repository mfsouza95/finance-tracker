-- Regression tests for review findings:
--  * account deletion cascades through closed months/entries
--  * month_summaries is select-only for clients (close_month is definer)
--  * RPC execute restricted to authenticated
--  * months open/closed invariant check
--  * categories bucket cannot change once it has entries
--  * profiles / budget_settings are select+update only for clients
create extension if not exists pgtap;

begin;

select plan(30);

-- ----------------------------------------------------------------
-- Fixtures
-- ----------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000',
   '70707070-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
   'g@test.local', 'x', now(), '', '', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '70707070-0000-0000-0000-00000000000b', 'authenticated', 'authenticated',
   'h@test.local', 'x', now(), '', '', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '70707070-0000-0000-0000-00000000000c', 'authenticated', 'authenticated',
   'i@test.local', 'x', now(), '', '', now(), now());

-- ----------------------------------------------------------------
-- User G builds a full history: open -> entries -> close, then the
-- auth.users row is deleted (as superuser, as Supabase admin would).
-- ----------------------------------------------------------------
set role authenticated;
set "request.jwt.claim.sub" = '70707070-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"70707070-0000-0000-0000-00000000000a","role":"authenticated"}';

insert into public.categories (id, user_id, bucket, name)
values ('ca700000-0000-0000-0000-000000000001',
        '70707070-0000-0000-0000-00000000000a', 'essential', 'G rent');
insert into public.recurring_templates
  (id, user_id, category_id, label, amount_cents, day_of_month)
values ('7e700000-0000-0000-0000-000000000001',
        '70707070-0000-0000-0000-00000000000a',
        'ca700000-0000-0000-0000-000000000001', 'G rent', 200000, 5);

select public.open_month(2026::smallint, 1::smallint, 600000);

insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select '70707070-0000-0000-0000-00000000000a', m.id,
       'ca700000-0000-0000-0000-000000000001', 5000, '2026-01-10'
from public.months m
where m.user_id = '70707070-0000-0000-0000-00000000000a' and m.month = 1;

select public.close_month(
  (select id from public.months
   where user_id = '70707070-0000-0000-0000-00000000000a' and month = 1), 100000);

-- H keeps a plain open month + entry to verify isolation after G's delete.
set "request.jwt.claim.sub" = '70707070-0000-0000-0000-00000000000b';
set "request.jwt.claims" =
  '{"sub":"70707070-0000-0000-0000-00000000000b","role":"authenticated"}';

insert into public.categories (id, user_id, bucket, name)
values ('ca700000-0000-0000-0000-000000000002',
        '70707070-0000-0000-0000-00000000000b', 'essential', 'H cat');
select public.open_month(2026::smallint, 2::smallint, 300000);
insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select '70707070-0000-0000-0000-00000000000b', m.id,
       'ca700000-0000-0000-0000-000000000002', 100, '2026-02-01'
from public.months m
where m.user_id = '70707070-0000-0000-0000-00000000000b' and m.month = 2;

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

-- Account deletion cascades through closed months, entries, summaries.
delete from auth.users where id = '70707070-0000-0000-0000-00000000000a';

select is(
  (select count(*)::int from public.profiles
   where user_id = '70707070-0000-0000-0000-00000000000a'),
  0, 'account delete removes profiles');
select is(
  (select count(*)::int from public.budget_settings
   where user_id = '70707070-0000-0000-0000-00000000000a'),
  0, 'account delete removes budget_settings');
select is(
  (select count(*)::int from public.categories
   where user_id = '70707070-0000-0000-0000-00000000000a'),
  0, 'account delete removes categories');
select is(
  (select count(*)::int from public.recurring_templates
   where user_id = '70707070-0000-0000-0000-00000000000a'),
  0, 'account delete removes recurring_templates');
select is(
  (select count(*)::int from public.months
   where user_id = '70707070-0000-0000-0000-00000000000a'),
  0, 'account delete removes closed months');
select is(
  (select count(*)::int from public.entries
   where user_id = '70707070-0000-0000-0000-00000000000a'),
  0, 'account delete removes entries in closed months');
select is(
  (select count(*)::int from public.month_summaries
   where user_id = '70707070-0000-0000-0000-00000000000a'),
  0, 'account delete removes month_summaries');
select is(
  (select count(*)::int from public.entries
   where user_id = '70707070-0000-0000-0000-00000000000b'),
  1, 'other user''s data is unaffected');

-- ----------------------------------------------------------------
-- User I: closed month + two categories (one with an entry)
-- ----------------------------------------------------------------
set role authenticated;
set "request.jwt.claim.sub" = '70707070-0000-0000-0000-00000000000c';
set "request.jwt.claims" =
  '{"sub":"70707070-0000-0000-0000-00000000000c","role":"authenticated"}';

insert into public.categories (id, user_id, bucket, name)
values
  ('ca700000-0000-0000-0000-000000000003',
   '70707070-0000-0000-0000-00000000000c', 'essential', 'I groceries'),
  ('ca700000-0000-0000-0000-000000000004',
   '70707070-0000-0000-0000-00000000000c', 'essential', 'I unused');

select public.open_month(2026::smallint, 3::smallint, 400000);
insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select '70707070-0000-0000-0000-00000000000c', m.id,
       'ca700000-0000-0000-0000-000000000003', 7000, '2026-03-03'
from public.months m
where m.user_id = '70707070-0000-0000-0000-00000000000c' and m.month = 3;
select public.close_month(
  (select id from public.months
   where user_id = '70707070-0000-0000-0000-00000000000c' and month = 3), 50000);

-- Direct client deletes of closed data are still rejected (depth = 1).
select throws_ok(
  $$ delete from entries
     where user_id = '70707070-0000-0000-0000-00000000000c' $$,
  'P0001', 'month is closed; entries are read-only',
  'direct client delete of closed entry rejected');
select throws_ok(
  $$ delete from months
     where user_id = '70707070-0000-0000-0000-00000000000c' and month = 3 $$,
  'P0001', 'closed months cannot be deleted',
  'direct client delete of closed month rejected');

-- month_summaries is select-only for clients.
select throws_ok(
  $$ insert into month_summaries
       (month_id, user_id, net_income_cents,
        essential_budget_cents, essential_spent_cents, essential_rest_cents,
        fun_budget_cents, fun_spent_cents, fun_rest_cents,
        invest_target_cents, invested_cents)
     select m.id, m.user_id, m.net_income_cents, 0, 0, 0, 0, 0, 0, 0, 0
     from months m where m.user_id = '70707070-0000-0000-0000-00000000000c' $$,
  '42501', null, 'client cannot insert into month_summaries');
select is_empty(
  $$ update month_summaries set invested_cents = 0
     where user_id = '70707070-0000-0000-0000-00000000000c' returning 1 $$,
  'client cannot update month_summaries');
select is_empty(
  $$ delete from month_summaries
     where user_id = '70707070-0000-0000-0000-00000000000c' returning 1 $$,
  'client cannot delete month_summaries');
select is(
  (select count(*)::int from public.month_summaries
   where user_id = '70707070-0000-0000-0000-00000000000c'),
  1, 'client can still read own month_summaries');

-- months open-state invariant: open months may not carry close fields.
select throws_ok(
  $$ insert into months
       (user_id, year, month, net_income_cents,
        essential_pct, fun_pct, invest_pct, status, closed_at)
     values ('70707070-0000-0000-0000-00000000000c', 2026, 9, 1,
             50, 30, 20, 'open', now()) $$,
  '23514', null, 'open month cannot have closed_at set');
select throws_ok(
  $$ insert into months
       (user_id, year, month, net_income_cents,
        essential_pct, fun_pct, invest_pct, status, invested_cents)
     values ('70707070-0000-0000-0000-00000000000c', 2026, 9, 1,
             50, 30, 20, 'open', 500) $$,
  '23514', null, 'open month cannot have invested_cents set');

-- categories.bucket is frozen once the category has entries.
select throws_ok(
  $$ update categories set bucket = 'fun'
     where id = 'ca700000-0000-0000-0000-000000000003' $$,
  'P0001', 'cannot change bucket of a category that has entries',
  'cannot change bucket of category that has entries');
select lives_ok(
  $$ update categories set bucket = 'fun'
     where id = 'ca700000-0000-0000-0000-000000000004' $$,
  'can change bucket of category without entries');
select is(
  (select bucket::text from public.categories
   where id = 'ca700000-0000-0000-0000-000000000004'),
  'fun', 'bucket change persisted on entry-less category');

-- profiles: select + update only.
select throws_ok(
  $$ insert into profiles (user_id, display_name)
     values ('70707070-0000-0000-0000-00000000000c', 'forged') $$,
  '42501', null, 'client cannot insert profiles');
select is_empty(
  $$ delete from profiles
     where user_id = '70707070-0000-0000-0000-00000000000c' returning 1 $$,
  'client cannot delete profiles');
select lives_ok(
  $$ update profiles set display_name = 'Irene'
     where user_id = '70707070-0000-0000-0000-00000000000c' $$,
  'client can update own profile');
select is(
  (select display_name from public.profiles
   where user_id = '70707070-0000-0000-0000-00000000000c'),
  'Irene', 'profile update persisted');

-- budget_settings: select + update only.
select throws_ok(
  $$ insert into budget_settings (user_id) values
     ('70707070-0000-0000-0000-00000000000c') $$,
  '42501', null, 'client cannot insert budget_settings');
select is_empty(
  $$ delete from budget_settings
     where user_id = '70707070-0000-0000-0000-00000000000c' returning 1 $$,
  'client cannot delete budget_settings');
select lives_ok(
  $$ update budget_settings set essential_pct = 60, fun_pct = 20
     where user_id = '70707070-0000-0000-0000-00000000000c' $$,
  'client can update own budget_settings');

-- Deleting an open month directly still cascades its entries.
insert into public.months
  (id, user_id, year, month, net_income_cents, essential_pct, fun_pct, invest_pct)
values ('dd700000-0000-0000-0000-0000000000c4',
        '70707070-0000-0000-0000-00000000000c', 2026, 4, 100000, 50, 30, 20);
insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
values ('70707070-0000-0000-0000-00000000000c',
        'dd700000-0000-0000-0000-0000000000c4',
        'ca700000-0000-0000-0000-000000000004', 100, '2026-04-01');

select lives_ok(
  $$ delete from months where id = 'dd700000-0000-0000-0000-0000000000c4' $$,
  'deleting an open month succeeds');
select is_empty(
  $$ select * from entries
     where month_id = 'dd700000-0000-0000-0000-0000000000c4' $$,
  'open-month entries cascade on delete');

-- ----------------------------------------------------------------
-- Anonymous callers cannot execute the RPCs.
-- ----------------------------------------------------------------
set role anon;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select throws_ok(
  $$ select public.open_month(2026::smallint, 1::smallint, 100) $$,
  '42501', null, 'anon cannot execute open_month');
select throws_ok(
  $$ select public.close_month(
       '00000000-0000-0000-0000-00000000dead'::uuid, 1) $$,
  '42501', null, 'anon cannot execute close_month');

reset role;

select * from finish();
rollback;
