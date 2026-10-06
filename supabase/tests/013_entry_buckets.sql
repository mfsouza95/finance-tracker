-- entries.bucket: category-less entries count directly against a bucket;
-- when a category is present the bucket syncs from it. close_month and
-- the bucket UI read entries.bucket; 'out' fund entries stay bucket-less.
create extension if not exists pgtap;

begin;

select plan(6);

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        'c3c3c3c3-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
        'u@ebkt.test', 'x', now(), '', '', now(), now());

set role authenticated;
set "request.jwt.claim.sub" = 'c3c3c3c3-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"c3c3c3c3-0000-0000-0000-00000000000a","role":"authenticated"}';

insert into public.categories (id, user_id, bucket, name)
values ('ce300000-0000-0000-0000-000000000001',
        'c3c3c3c3-0000-0000-0000-00000000000a', 'essential', 'Mercado');

select public.open_month(2026::smallint, 8::smallint, 1000000);

-- Category-less entry into essential + one with a category whose bucket
-- syncs from the category (client-supplied bucket is overridden).
insert into public.entries
  (user_id, month_id, category_id, bucket, amount_cents, paid_on, note)
select 'c3c3c3c3-0000-0000-0000-00000000000a', m.id, null, 'essential',
       25000, '2026-08-05', 'Óculos'
from public.months m where m.user_id = 'c3c3c3c3-0000-0000-0000-00000000000a';

select is(
  (select bucket::text from public.entries where note = 'Óculos'),
  'essential', 'category-less entry keeps its own bucket');

insert into public.entries
  (user_id, month_id, category_id, bucket, amount_cents, paid_on, note)
select 'c3c3c3c3-0000-0000-0000-00000000000a', m.id,
       'ce300000-0000-0000-0000-000000000001', 'fun',
       30000, '2026-08-06', 'Feira'
from public.months m where m.user_id = 'c3c3c3c3-0000-0000-0000-00000000000a';

select is(
  (select bucket::text from public.entries where note = 'Feira'),
  'essential', 'categorized entry takes the category bucket (sync wins)');

-- Shape guard: a normal entry still needs a bucket; 'out' stays
-- bucket-less by definition.
select throws_ok(
  $$ insert into public.entries
       (user_id, month_id, category_id, amount_cents, paid_on)
     select 'c3c3c3c3-0000-0000-0000-00000000000a', m.id, null, 100,
            '2026-08-07'
     from public.months m
     where m.user_id = 'c3c3c3c3-0000-0000-0000-00000000000a' $$,
  '23514', null, 'entry without category AND without bucket is rejected');

select public.close_month(
  (select id from public.months
   where user_id = 'c3c3c3c3-0000-0000-0000-00000000000a' and month = 8), 0);

select is(
  (select essential_spent_cents from public.month_summaries
   where user_id = 'c3c3c3c3-0000-0000-0000-00000000000a'),
  55000::bigint, 'summary counts the category-less entry via entries.bucket');

-- Fund deposit still lands in its bucket through the synced category.
select public.reopen_month(
  (select id from public.months
   where user_id = 'c3c3c3c3-0000-0000-0000-00000000000a' and month = 8));

insert into public.funds (user_id, kind, name)
values ('c3c3c3c3-0000-0000-0000-00000000000a', 'bank', 'Viagem');

select public.deposit_to_fund(
  (select id from public.funds where name = 'Viagem'),
  (select id from public.months
   where user_id = 'c3c3c3c3-0000-0000-0000-00000000000a' and month = 8),
  0, 40000, '2026-08-10'::date, null);

select is(
  (select bucket::text from public.entries
   where fund_id = (select id from public.funds where name = 'Viagem')
     and fund_flow = 'in'),
  'fun', 'deposit entry carries its funding bucket on the row');

-- And a fund 'out' entry must have bucket null.
insert into public.entries
  (user_id, month_id, amount_cents, paid_on, fund_id, fund_flow)
select 'c3c3c3c3-0000-0000-0000-00000000000a', m.id, 10000, '2026-08-11',
       f.id, 'out'
from public.months m, public.funds f
where m.user_id = 'c3c3c3c3-0000-0000-0000-00000000000a' and m.month = 8
  and f.name = 'Viagem';

select is(
  (select bucket is null from public.entries where fund_flow = 'out'),
  true, 'out entries never carry a bucket');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
