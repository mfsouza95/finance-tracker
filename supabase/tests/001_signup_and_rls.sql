-- Signup trigger effects + table-driven RLS isolation between two users.
create extension if not exists pgtap;

begin;

select plan(23);

-- ----------------------------------------------------------------
-- Fixtures (as postgres superuser; RLS bypassed)
-- ----------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000',
   'aaaaaaaa-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
   'a@test.local', 'x', now(), '', '', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   'bbbbbbbb-0000-0000-0000-00000000000b', 'authenticated', 'authenticated',
   'b@test.local', 'x', now(), '', '', now(), now());

-- handle_new_user trigger effects (checked as superuser)
select is(
  (select count(*)::int from public.profiles
   where user_id in ('aaaaaaaa-0000-0000-0000-00000000000a',
                     'bbbbbbbb-0000-0000-0000-00000000000b')),
  2, 'signup trigger creates profiles');

select is(
  (select array[essential_pct, fun_pct, invest_pct]
   from public.budget_settings
   where user_id = 'aaaaaaaa-0000-0000-0000-00000000000a'),
  '{50,30,20}'::smallint[], 'signup trigger creates default 50/30/20 settings');

-- B has one row in every table, so nothing below is vacuous.
-- (profiles and budget_settings already exist via the trigger.)
insert into public.categories (id, user_id, bucket, name)
values ('cc000000-0000-0000-0000-0000000000b1',
        'bbbbbbbb-0000-0000-0000-00000000000b', 'essential', 'B category');
insert into public.months
  (id, user_id, year, month, net_income_cents, essential_pct, fun_pct, invest_pct)
values ('dd000000-0000-0000-0000-0000000000b1',
        'bbbbbbbb-0000-0000-0000-00000000000b', 2026, 1, 700000, 50, 30, 20),
       ('dd000000-0000-0000-0000-0000000000b2',
        'bbbbbbbb-0000-0000-0000-00000000000b', 2026, 2, 700000, 50, 30, 20);
insert into public.entries
  (id, user_id, month_id, category_id, amount_cents, paid_on)
values ('ee000000-0000-0000-0000-0000000000b1',
        'bbbbbbbb-0000-0000-0000-00000000000b',
        'dd000000-0000-0000-0000-0000000000b1',
        'cc000000-0000-0000-0000-0000000000b1',
        150000, '2026-01-05');
insert into public.recurring_templates
  (id, user_id, category_id, label, amount_cents, day_of_month)
values ('ff000000-0000-0000-0000-0000000000b1',
        'bbbbbbbb-0000-0000-0000-00000000000b',
        'cc000000-0000-0000-0000-0000000000b1', 'B rent', 100000, 5);
insert into public.month_summaries
  (month_id, user_id, net_income_cents,
   essential_budget_cents, essential_spent_cents, essential_rest_cents,
   fun_budget_cents, fun_spent_cents, fun_rest_cents,
   invest_target_cents, invested_cents)
values ('dd000000-0000-0000-0000-0000000000b1',
        'bbbbbbbb-0000-0000-0000-00000000000b',
        700000, 350000, 150000, 200000, 210000, 0, 210000, 140000, 550000);
insert into public.extra_income (user_id, month_id, amount_cents, received_on)
values ('bbbbbbbb-0000-0000-0000-00000000000b',
        'dd000000-0000-0000-0000-0000000000b1', 5000, '2026-01-10');
insert into public.funds (user_id, kind, name)
values ('bbbbbbbb-0000-0000-0000-00000000000b', 'bank', 'B reserva');

-- A needs an owned category for the cross-user FK tests below.
insert into public.categories (id, user_id, bucket, name)
values ('cc000000-0000-0000-0000-0000000000a1',
        'aaaaaaaa-0000-0000-0000-00000000000a', 'essential', 'A category');

-- ----------------------------------------------------------------
-- Act as user A: cannot read any of B's rows
-- ----------------------------------------------------------------
set role authenticated;
set "request.jwt.claim.sub" = 'aaaaaaaa-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}';

select is_empty(
  $$ select * from profiles
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' $$,
  'A cannot read B profiles');
select is_empty(
  $$ select * from budget_settings
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' $$,
  'A cannot read B budget_settings');
select is_empty(
  $$ select * from months
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' $$,
  'A cannot read B months');
select is_empty(
  $$ select * from categories
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' $$,
  'A cannot read B categories');
select is_empty(
  $$ select * from recurring_templates
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' $$,
  'A cannot read B recurring_templates');
select is_empty(
  $$ select * from entries
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' $$,
  'A cannot read B entries');
select is_empty(
  $$ select * from month_summaries
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' $$,
  'A cannot read B month_summaries');
select is_empty(
  $$ select * from extra_income
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' $$,
  'A cannot read B extra_income');
select is_empty(
  $$ select * from funds
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' $$,
  'A cannot read B funds');

-- Cannot insert a row owned by B. One representative per policy shape:
-- FOR ALL (months), select+update only (profiles), select-only
-- (month_summaries), and funds' own insert policy.
select throws_ok(
  $$ insert into months
       (user_id, year, month, net_income_cents, essential_pct, fun_pct, invest_pct)
     values ('bbbbbbbb-0000-0000-0000-00000000000b', 2026, 2, 1, 50, 30, 20) $$,
  '42501', null, 'A cannot insert a month owned by B');
select throws_ok(
  $$ insert into profiles (user_id) values
     ('bbbbbbbb-0000-0000-0000-00000000000b') $$,
  '42501', null, 'A cannot insert a profile owned by B');
select throws_ok(
  $$ insert into month_summaries
       (month_id, user_id, net_income_cents,
        essential_budget_cents, essential_spent_cents, essential_rest_cents,
        fun_budget_cents, fun_spent_cents, fun_rest_cents,
        invest_target_cents, invested_cents)
     values ('dd000000-0000-0000-0000-0000000000b1',
             'bbbbbbbb-0000-0000-0000-00000000000b',
             1, 1, 1, 0, 1, 1, 0, 1, 1) $$,
  '42501', null, 'A cannot insert a summary owned by B');
select throws_ok(
  $$ insert into funds (user_id, kind, name) values
     ('bbbbbbbb-0000-0000-0000-00000000000b', 'bank', 'forged') $$,
  '42501', null, 'A cannot insert a fund owned by B');

-- Cannot update or delete B's rows (0 rows affected — the USING clause
-- hides them). One representative per policy shape again: a FOR ALL
-- table and the select+update / select-only shapes.
select is_empty(
  $$ update entries set amount_cents = 1
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' returning 1 $$,
  'A cannot update B entries');
select is_empty(
  $$ update profiles set display_name = 'x'
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' returning 1 $$,
  'A cannot update B profiles');
select is_empty(
  $$ delete from months
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' returning 1 $$,
  'A cannot delete B months');
select is_empty(
  $$ delete from month_summaries
     where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b' returning 1 $$,
  'A cannot delete B month_summaries');

-- A opens their own month, then tries to reference B's rows via FK columns
select lives_ok(
  $$ select public.open_month(2026::smallint, 2::smallint, 500000) $$,
  'A can open own month via rpc');

select throws_ok(
  $$ insert into entries (user_id, month_id, category_id, amount_cents, paid_on)
     select 'aaaaaaaa-0000-0000-0000-00000000000a', m.id,
            'cc000000-0000-0000-0000-0000000000b1', 100, '2026-02-01'
     from months m where m.user_id = 'aaaaaaaa-0000-0000-0000-00000000000a' $$,
  '23503', null, 'A cannot point an entry at B category (composite FK)');
select throws_ok(
  $$ insert into entries (user_id, month_id, category_id, amount_cents, paid_on)
     values ('aaaaaaaa-0000-0000-0000-00000000000a',
             'dd000000-0000-0000-0000-0000000000b1',
             'cc000000-0000-0000-0000-0000000000a1', 100, '2026-02-01') $$,
  '23503', null, 'A cannot point an entry at B month (composite FK)');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

-- As superuser the RLS barrier is gone, so the composite FK itself is
-- what must reject a summary attached to another user's month.
-- (Uses B's second month, which has no summary, to keep the PK free.)
select throws_ok(
  $$ insert into month_summaries
       (month_id, user_id, net_income_cents,
        essential_budget_cents, essential_spent_cents, essential_rest_cents,
        fun_budget_cents, fun_spent_cents, fun_rest_cents,
        invest_target_cents, invested_cents)
     values ('dd000000-0000-0000-0000-0000000000b2',
             'aaaaaaaa-0000-0000-0000-00000000000a',
             1, 1, 1, 0, 1, 1, 0, 1, 1) $$,
  '23503', null, 'composite FK rejects summary whose owner != month owner');

select * from finish();
rollback;
