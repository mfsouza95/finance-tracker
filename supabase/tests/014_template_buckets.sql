-- recurring_templates.bucket: templates may carry a bucket directly so a
-- parcela like "óculos 6x" needs no category. With a category the bucket
-- syncs from it, exactly like entries.
create extension if not exists pgtap;

begin;

select plan(6);

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        'c4c4c4c4-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
        'u@tbkt.test', 'x', now(), '', '', now(), now());

set role authenticated;
set "request.jwt.claim.sub" = 'c4c4c4c4-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"c4c4c4c4-0000-0000-0000-00000000000a","role":"authenticated"}';

insert into public.categories (id, user_id, bucket, name)
values ('ce400000-0000-0000-0000-000000000001',
        'c4c4c4c4-0000-0000-0000-00000000000a', 'fun', 'Lazer');

-- An open month inside the plan window receives the backfilled entry.
select public.open_month(
  extract(year from current_date)::smallint,
  extract(month from current_date)::smallint, 1000000);

-- Category-less installment plan: "óculos 6x" straight into essential.
select public.create_recurring_template(
  'Óculos 6x', 50000, 10::smallint,
  null, 'essential'::public.bucket, 3::smallint,
  extract(year from current_date)::smallint,
  extract(month from current_date)::smallint);

select results_eq(
  $$ select bucket::text, category_id::text
     from public.recurring_templates where label = 'Óculos 6x' $$,
  $$ values ('essential', null::text) $$,
  'category-less template keeps its own bucket');

select results_eq(
  $$ select bucket::text, category_id::text, installment_index::text
     from public.entries where note = 'Óculos 6x' $$,
  $$ values ('essential', null::text, '1'::text) $$,
  'backfilled entry lands in the bucket with index 1');

-- A categorized template still derives its bucket from the category.
select public.create_recurring_template(
  'Cinema', 3000, 5::smallint, 'ce400000-0000-0000-0000-000000000001');

select is(
  (select bucket::text from public.recurring_templates where label = 'Cinema'),
  'fun', 'categorized template takes the category bucket');

-- Neither category nor bucket is an error, RPC or direct insert alike.
select throws_ok(
  $$ select public.create_recurring_template('Sem destino', 1000, 5::smallint) $$,
  'bucket is required when category is not set');

select throws_ok(
  $$ insert into public.recurring_templates
       (user_id, label, amount_cents, day_of_month)
     values ('c4c4c4c4-0000-0000-0000-00000000000a', 'X', 100, 1) $$,
  '23514', null, 'template without category AND bucket is rejected');

-- open_month generates the category-less plan into the next month, index 2.
delete from public.months
where user_id = 'c4c4c4c4-0000-0000-0000-00000000000a'
  and (year, month) <> (
    extract(year from current_date)::smallint,
    extract(month from current_date)::smallint);

select public.open_month(
  extract(year from (current_date + interval '1 month'))::smallint,
  extract(month from (current_date + interval '1 month'))::smallint, 1000000);

select is(
  (select count(*) from public.entries
   where note = 'Óculos 6x' and installment_index = 2 and bucket = 'essential'),
  1::bigint, 'next month generates installment 2 in the same bucket');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
