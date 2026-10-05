-- Catalog check: every ordinary table in public must have RLS enabled.
-- Anon role: no access to any of the 7 tables at all.
create extension if not exists pgtap;

begin;

select plan(29);

-- One fixture user so the anon select tests are not vacuous.
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        '60606060-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
        'anon-fixture@test.local', 'x', now(), '', '', now(), now());
insert into public.categories (user_id, bucket, name)
values ('60606060-0000-0000-0000-00000000000a', 'essential', 'fixture');
insert into public.months
  (user_id, year, month, net_income_cents, essential_pct, fun_pct, invest_pct)
values ('60606060-0000-0000-0000-00000000000a', 2026, 1, 1000, 50, 30, 20);
insert into public.entries
  (user_id, month_id, category_id, amount_cents, paid_on)
select '60606060-0000-0000-0000-00000000000a', m.id, c.id, 100, '2026-01-01'
from public.months m, public.categories c
where m.user_id = '60606060-0000-0000-0000-00000000000a'
  and c.user_id = '60606060-0000-0000-0000-00000000000a';
insert into public.recurring_templates
  (user_id, category_id, label, amount_cents, day_of_month)
select '60606060-0000-0000-0000-00000000000a', c.id, 'fixture', 100, 1
from public.categories c
where c.user_id = '60606060-0000-0000-0000-00000000000a';
insert into public.month_summaries
  (month_id, user_id, net_income_cents,
   essential_budget_cents, essential_spent_cents, essential_rest_cents,
   fun_budget_cents, fun_spent_cents, fun_rest_cents,
   invest_target_cents, invested_cents)
select m.id, m.user_id, 1000, 500, 0, 500, 300, 0, 300, 200, 0
from public.months m
where m.user_id = '60606060-0000-0000-0000-00000000000a';

select is_empty(
  $$ select c.relname::text from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
     order by 1 $$,
  'every table in public has RLS enabled');

set role anon;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select is_empty($$ select * from profiles $$, 'anon cannot read profiles');
select is_empty($$ select * from budget_settings $$, 'anon cannot read budget_settings');
select is_empty($$ select * from months $$, 'anon cannot read months');
select is_empty($$ select * from categories $$, 'anon cannot read categories');
select is_empty($$ select * from recurring_templates $$, 'anon cannot read recurring_templates');
select is_empty($$ select * from entries $$, 'anon cannot read entries');
select is_empty($$ select * from month_summaries $$, 'anon cannot read month_summaries');

select throws_ok(
  $$ insert into profiles (user_id)
     values ('60606060-0000-0000-0000-00000000000a') $$,
  '42501', null, 'anon cannot insert profiles');
select throws_ok(
  $$ insert into budget_settings (user_id)
     values ('60606060-0000-0000-0000-00000000000a') $$,
  '42501', null, 'anon cannot insert budget_settings');
select throws_ok(
  $$ insert into months
       (user_id, year, month, net_income_cents, essential_pct, fun_pct, invest_pct)
     values ('60606060-0000-0000-0000-00000000000a', 2026, 3, 1, 50, 30, 20) $$,
  '42501', null, 'anon cannot insert months');
select throws_ok(
  $$ insert into categories (user_id, bucket, name)
     values ('60606060-0000-0000-0000-00000000000a', 'essential', 'x') $$,
  '42501', null, 'anon cannot insert categories');
select throws_ok(
  $$ insert into recurring_templates
       (user_id, category_id, label, amount_cents, day_of_month)
     values ('60606060-0000-0000-0000-00000000000a',
             '60606060-0000-0000-0000-00000000000a', 'x', 1, 1) $$,
  '42501', null, 'anon cannot insert recurring_templates');
select throws_ok(
  $$ insert into entries (user_id, month_id, category_id, amount_cents, paid_on)
     values ('60606060-0000-0000-0000-00000000000a',
             '60606060-0000-0000-0000-00000000000a',
             '60606060-0000-0000-0000-00000000000a', 1, '2026-01-01') $$,
  '42501', null, 'anon cannot insert entries');
select throws_ok(
  $$ insert into month_summaries
       (month_id, user_id, net_income_cents,
        essential_budget_cents, essential_spent_cents, essential_rest_cents,
        fun_budget_cents, fun_spent_cents, fun_rest_cents,
        invest_target_cents, invested_cents)
     values ('60606060-0000-0000-0000-00000000000a',
             '60606060-0000-0000-0000-00000000000a',
             1, 1, 1, 0, 1, 1, 0, 1, 1) $$,
  '42501', null, 'anon cannot insert month_summaries');

select is_empty(
  $$ update profiles set display_name = 'x' returning 1 $$,
  'anon cannot update profiles');
select is_empty(
  $$ update budget_settings set essential_pct = 99 returning 1 $$,
  'anon cannot update budget_settings');
select is_empty(
  $$ update months set net_income_cents = 1 returning 1 $$,
  'anon cannot update months');
select is_empty(
  $$ update categories set name = 'x' returning 1 $$,
  'anon cannot update categories');
select is_empty(
  $$ update recurring_templates set label = 'x' returning 1 $$,
  'anon cannot update recurring_templates');
select is_empty(
  $$ update entries set amount_cents = 1 returning 1 $$,
  'anon cannot update entries');
select is_empty(
  $$ update month_summaries set invested_cents = 0 returning 1 $$,
  'anon cannot update month_summaries');

select is_empty(
  $$ delete from profiles returning 1 $$,
  'anon cannot delete profiles');
select is_empty(
  $$ delete from budget_settings returning 1 $$,
  'anon cannot delete budget_settings');
select is_empty(
  $$ delete from months returning 1 $$,
  'anon cannot delete months');
select is_empty(
  $$ delete from categories returning 1 $$,
  'anon cannot delete categories');
select is_empty(
  $$ delete from recurring_templates returning 1 $$,
  'anon cannot delete recurring_templates');
select is_empty(
  $$ delete from entries returning 1 $$,
  'anon cannot delete entries');
select is_empty(
  $$ delete from month_summaries returning 1 $$,
  'anon cannot delete month_summaries');

reset role;

select * from finish();
rollback;
