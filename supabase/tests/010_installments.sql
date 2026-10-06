-- Installment plans: bounded recurring_templates.
-- Position-based generation (index = months since first + 1), backfill into
-- open months on creation, closed months skipped, exhaustion, deactivation.
-- Months are computed from current_date so the file never goes stale.
create extension if not exists pgtap;

begin;

select plan(12);

-- ----------------------------------------------------------------
-- Fixtures
-- ----------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000',
   'a1a1a1a1-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
   'u@inst.test', 'x', now(), '', '', now(), now());

insert into public.categories (id, user_id, bucket, name, archived)
values
  ('cb100000-0000-0000-0000-000000000001'::uuid,
   'a1a1a1a1-0000-0000-0000-00000000000a', 'essential', 'U ess', false),
  ('cb100000-0000-0000-0000-000000000002'::uuid,
   'a1a1a1a1-0000-0000-0000-00000000000a', 'fun', 'U arch', true);

set role authenticated;
set "request.jwt.claim.sub" = 'a1a1a1a1-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"a1a1a1a1-0000-0000-0000-00000000000a","role":"authenticated"}';

-- C (current), C+1 open; C+2 opened then closed so a plan window crosses a
-- closed month.
select public.open_month(
  extract(year from current_date)::smallint,
  extract(month from current_date)::smallint, 100000);
select public.open_month(
  extract(year from current_date + interval '1 month')::smallint,
  extract(month from current_date + interval '1 month')::smallint, 100000);
select public.open_month(
  extract(year from current_date + interval '2 months')::smallint,
  extract(month from current_date + interval '2 months')::smallint, 100000);
select public.close_month(
  (select id from public.months
   where user_id = 'a1a1a1a1-0000-0000-0000-00000000000a'
     and year = extract(year from current_date + interval '2 months')::smallint
     and month = extract(month from current_date + interval '2 months')::smallint),
  0);

-- ----------------------------------------------------------------
-- Plan A: 3 installments, first defaults to the current month.
-- Backfills the two open months; the closed C+2 is skipped.
-- ----------------------------------------------------------------
select public.create_recurring_template(
  'cb100000-0000-0000-0000-000000000001'::uuid, 'Plano A', 3000::bigint, 10::smallint,
  3::smallint, null, null);

select is(
  (select first_month from public.recurring_templates
   where user_id = 'a1a1a1a1-0000-0000-0000-00000000000a'
     and label = 'Plano A'),
  extract(month from current_date)::smallint,
  'bounded plan defaults first_month to the current month');

select is(
  (select e.installment_index from public.entries e
   join public.months m on m.id = e.month_id
   where e.user_id = 'a1a1a1a1-0000-0000-0000-00000000000a'
     and m.year = extract(year from current_date)::smallint
     and m.month = extract(month from current_date)::smallint
     and e.note = 'Plano A'),
  1::smallint, 'creation backfills installment 1 into the open current month');

select is(
  (select e.installment_index from public.entries e
   join public.months m on m.id = e.month_id
   where e.user_id = 'a1a1a1a1-0000-0000-0000-00000000000a'
     and m.year = extract(year from current_date + interval '1 month')::smallint
     and m.month = extract(month from current_date + interval '1 month')::smallint
     and e.note = 'Plano A'),
  2::smallint, 'already-open next month gets its position-based installment 2');

-- ----------------------------------------------------------------
-- Plan B: 4 installments with explicit first=C. C+2 is closed so only
-- C and C+1 backfill; opening C+3 later generates index 4 anyway —
-- the skipped closed month does not shift positions.
-- ----------------------------------------------------------------
select public.create_recurring_template(
  'cb100000-0000-0000-0000-000000000001'::uuid, 'Plano B', 2000::bigint, 5::smallint,
  4::smallint,
  extract(year from current_date)::smallint,
  extract(month from current_date)::smallint);

select is(
  (select count(*)::int from public.entries e
   join public.recurring_templates t on t.id = e.recurring_template_id
   where e.user_id = 'a1a1a1a1-0000-0000-0000-00000000000a'
     and t.label = 'Plano B'),
  2, 'closed month inside the window is never backfilled');

select public.open_month(
  extract(year from current_date + interval '3 months')::smallint,
  extract(month from current_date + interval '3 months')::smallint, 100000);

select is(
  (select e.installment_index from public.entries e
   join public.months m on m.id = e.month_id
   join public.recurring_templates t on t.id = e.recurring_template_id
   where e.user_id = 'a1a1a1a1-0000-0000-0000-00000000000a'
     and m.year = extract(year from current_date + interval '3 months')::smallint
     and m.month = extract(month from current_date + interval '3 months')::smallint
     and t.label = 'Plano B'),
  4::smallint, 'open_month generates position-based index after skipped month');

select is(
  (select count(*)::int from public.entries e
   join public.recurring_templates t on t.id = e.recurring_template_id
   where e.user_id = 'a1a1a1a1-0000-0000-0000-00000000000a'
     and t.label = 'Plano A'),
  2, 'exhausted plan generates nothing beyond installments_total');

-- ----------------------------------------------------------------
-- Unbounded template backfills only open months >= creation month:
-- C, C+1 and C+3 are open (C+2 is closed) -> exactly 3 entries.
-- ----------------------------------------------------------------
select public.create_recurring_template(
  'cb100000-0000-0000-0000-000000000001'::uuid, 'Netflix', 5000::bigint, 15::smallint);

select is(
  (select count(*)::int from public.entries e
   join public.recurring_templates t on t.id = e.recurring_template_id
   where e.user_id = 'a1a1a1a1-0000-0000-0000-00000000000a'
     and t.label = 'Netflix'),
  3, 'unbounded template backfills all open months from creation onward');

select is(
  (select count(*)::int from public.entries e
   join public.recurring_templates t on t.id = e.recurring_template_id
   where e.user_id = 'a1a1a1a1-0000-0000-0000-00000000000a'
     and t.label = 'Netflix' and e.installment_index is null),
  3, 'unbounded template entries carry no installment_index');

-- ----------------------------------------------------------------
-- Deactivate the unbounded template, then open C+4: nothing generates
-- (plan A exhausted at 3, plan B exhausted at 4, Netflix inactive).
-- ----------------------------------------------------------------
update public.recurring_templates set active = false
where user_id = 'a1a1a1a1-0000-0000-0000-00000000000a' and label = 'Netflix';

select public.open_month(
  extract(year from current_date + interval '4 months')::smallint,
  extract(month from current_date + interval '4 months')::smallint, 100000);

select is(
  (select count(*)::int from public.entries e
   join public.months m on m.id = e.month_id
   where e.user_id = 'a1a1a1a1-0000-0000-0000-00000000000a'
     and m.year = extract(year from current_date + interval '4 months')::smallint
     and m.month = extract(month from current_date + interval '4 months')::smallint),
  0, 'inactive and exhausted templates generate nothing in later months');

-- ----------------------------------------------------------------
-- Validation and grants
-- ----------------------------------------------------------------
select throws_ok(
  $$ select public.create_recurring_template(
    'cb100000-0000-0000-0000-000000000001'::uuid, 'Ruim', 1000::bigint, 10::smallint, 1::smallint, null, null) $$,
  'P0001', 'installments_total must be >= 2',
  'single-payment plans are rejected');

select throws_ok(
  $$ select public.create_recurring_template(
    'cb100000-0000-0000-0000-000000000002'::uuid, 'Arquivada', 1000::bigint, 10::smallint) $$,
  'P0001', 'category not found or archived',
  'archived category is rejected');

reset role;
set role anon;
select throws_ok(
  $$ select public.create_recurring_template(
    gen_random_uuid(), 'x', 1000::bigint, 10::smallint) $$,
  '42501', null,
  'anon cannot execute create_recurring_template');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
