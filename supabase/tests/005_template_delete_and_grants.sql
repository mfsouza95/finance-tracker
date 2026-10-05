-- Regression tests:
--  * deleting a recurring_template runs ON DELETE SET NULL on entries,
--    including entries inside closed months (RI trigger depth > 1 bypass)
--  * clients still cannot touch recurring_template_id on closed-month entries
--  * handle_new_user is not callable by clients but still fires on signup
create extension if not exists pgtap;

begin;

select plan(13);

-- ----------------------------------------------------------------
-- User J: two active templates; entries in a closed month (Jan) and
-- an open month (Feb)
-- ----------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        '90909090-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
        'j@test.local', 'x', now(), '', '', now(), now());

set role authenticated;
set "request.jwt.claim.sub" = '90909090-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"90909090-0000-0000-0000-00000000000a","role":"authenticated"}';

insert into public.categories (id, user_id, bucket, name)
values ('ca900000-0000-0000-0000-000000000001',
        '90909090-0000-0000-0000-00000000000a', 'essential', 'J bills');

insert into public.recurring_templates
  (id, user_id, category_id, label, amount_cents, day_of_month)
values
  ('aa900000-0000-0000-0000-000000000001',
   '90909090-0000-0000-0000-00000000000a',
   'ca900000-0000-0000-0000-000000000001', 'Internet', 15000, 10),
  ('aa900000-0000-0000-0000-000000000002',
   '90909090-0000-0000-0000-00000000000a',
   'ca900000-0000-0000-0000-000000000001', 'Phone', 5000, 20);

select public.open_month(2026::smallint, 1::smallint, 400000);
select public.close_month(
  (select id from public.months
   where user_id = '90909090-0000-0000-0000-00000000000a' and month = 1), 50000);
select public.open_month(2026::smallint, 2::smallint, 400000);

-- (b) Clients cannot write recurring_template_id on closed-month entries,
--     either nulling it or pointing it at another template.
select throws_ok(
  $$ update entries set recurring_template_id = null
     where user_id = '90909090-0000-0000-0000-00000000000a'
       and amount_cents = 15000
       and month_id = (select id from months
                       where user_id = '90909090-0000-0000-0000-00000000000a'
                         and month = 1) $$,
  'P0001', 'month is closed; entries are read-only',
  'cannot null recurring_template_id on closed-month entry');
select throws_ok(
  $$ update entries set recurring_template_id = 'aa900000-0000-0000-0000-000000000002'
     where user_id = '90909090-0000-0000-0000-00000000000a'
       and amount_cents = 15000
       and month_id = (select id from months
                       where user_id = '90909090-0000-0000-0000-00000000000a'
                         and month = 1) $$,
  'P0001', 'month is closed; entries are read-only',
  'cannot re-point recurring_template_id on closed-month entry');

-- (a) Client deletes template 1: SET NULL must reach the closed-month
--     entry and the open-month entry; everything else stays intact.
select lives_ok(
  $$ delete from recurring_templates
     where id = 'aa900000-0000-0000-0000-000000000001' $$,
  'deleting a template with entries in closed and open months succeeds');

select is_empty(
  $$ select * from recurring_templates
     where id = 'aa900000-0000-0000-0000-000000000001' $$,
  'template row is gone');

select ok(
  (select e.recurring_template_id is null from public.entries e
   join public.months m on m.id = e.month_id
   where e.user_id = '90909090-0000-0000-0000-00000000000a'
     and m.month = 1 and e.amount_cents = 15000),
  'closed-month entry loses its template link');
select results_eq(
  $$ select e.amount_cents, e.paid_on, e.category_id
     from public.entries e
     join public.months m on m.id = e.month_id
     where e.user_id = '90909090-0000-0000-0000-00000000000a'
       and m.month = 1 and e.amount_cents = 15000 $$,
  $$ values (15000::bigint, '2026-01-10'::date,
             'ca900000-0000-0000-0000-000000000001'::uuid) $$,
  'closed-month entry keeps amount, paid_on and category');

select ok(
  (select e.recurring_template_id is null from public.entries e
   join public.months m on m.id = e.month_id
   where e.user_id = '90909090-0000-0000-0000-00000000000a'
     and m.month = 2 and e.amount_cents = 15000),
  'open-month entry loses its template link');
select results_eq(
  $$ select e.amount_cents, e.paid_on, e.category_id
     from public.entries e
     join public.months m on m.id = e.month_id
     where e.user_id = '90909090-0000-0000-0000-00000000000a'
       and m.month = 2 and e.amount_cents = 15000 $$,
  $$ values (15000::bigint, '2026-02-10'::date,
             'ca900000-0000-0000-0000-000000000001'::uuid) $$,
  'open-month entry keeps amount, paid_on and category');

-- Entries for the surviving template keep their link, closed month included.
select is(
  (select e.recurring_template_id from public.entries e
   join public.months m on m.id = e.month_id
   where e.user_id = '90909090-0000-0000-0000-00000000000a'
     and m.month = 1 and e.amount_cents = 5000),
  'aa900000-0000-0000-0000-000000000002'::uuid,
  'closed-month entry for surviving template keeps its link');
select ok(
  (select exists (select 1 from public.recurring_templates
                  where id = 'aa900000-0000-0000-0000-000000000002')),
  'surviving template row untouched');

-- (c) handle_new_user is not client-callable, but signup still works.
select throws_ok(
  $$ select public.handle_new_user() $$,
  '42501', null, 'authenticated cannot execute handle_new_user');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        '90909090-0000-0000-0000-00000000000b', 'authenticated', 'authenticated',
        'k@test.local', 'x', now(), '', '', now(), now());

select ok(
  (select exists (select 1 from public.profiles
                  where user_id = '90909090-0000-0000-0000-00000000000b')),
  'signup trigger still creates profile');
select ok(
  (select exists (select 1 from public.budget_settings
                  where user_id = '90909090-0000-0000-0000-00000000000b')),
  'signup trigger still creates budget_settings');

select * from finish();
rollback;
