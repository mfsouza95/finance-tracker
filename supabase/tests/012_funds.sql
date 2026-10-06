-- Funds (banks + piggy banks): deposits are bucket entries that credit
-- the fund (flow 'in'); bank spends bypass buckets (flow 'out', no
-- category). Covers the split deposit, balance math, flow guards,
-- close_month exclusion of 'out' entries, delete-with-extras transfer,
-- the no-direct-delete policy and RLS isolation.
create extension if not exists pgtap;

begin;

select plan(18);

-- ----------------------------------------------------------------
-- Fixtures
-- ----------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000',
   'b3b3b3b3-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
   'u@funds.test', 'x', now(), '', '', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   'b3b3b3b3-0000-0000-0000-00000000000b', 'authenticated', 'authenticated',
   'v@funds.test', 'x', now(), '', '', now(), now());

set role authenticated;
set "request.jwt.claim.sub" = 'b3b3b3b3-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"b3b3b3b3-0000-0000-0000-00000000000a","role":"authenticated"}';

-- U: month 2026-08 (net 10000 → 5000/3000/2000) + current month open so
-- delete_fund has somewhere to send extras.
select public.open_month(2026::smallint, 8::smallint, 1000000);
select public.open_month(
  extract(year from current_date)::smallint,
  extract(month from current_date)::smallint, 500000);

select lives_ok(
  $$ insert into public.funds (user_id, kind, name, goal_cents) values
     ('b3b3b3b3-0000-0000-0000-00000000000a', 'bank', 'Viagem', null),
     ('b3b3b3b3-0000-0000-0000-00000000000a', 'piggy', 'Notebook', 500000) $$,
  'create a bank and a piggy bank');

-- ----------------------------------------------------------------
-- Split deposit: 30000 essential + 20000 fun -> two 'in' entries,
-- 'Reservas' categories created in both buckets, balance 50000.
-- ----------------------------------------------------------------
select public.deposit_to_fund(
  (select id from public.funds where name = 'Viagem'),
  (select id from public.months where year = 2026 and month = 8),
  30000, 20000, '2026-08-05'::date, null);

select is(
  (select count(*)::int from public.entries e
   join public.funds f on f.id = e.fund_id
   where f.name = 'Viagem' and e.fund_flow = 'in'),
  2, 'split deposit creates one entry per bucket');

select is(
  (select balance_cents from public.fund_balances fb
   join public.funds f on f.id = fb.fund_id where f.name = 'Viagem'),
  50000::bigint, 'bank balance credits both bucket amounts');

select is(
  (select count(*)::int from public.categories where name = 'Reservas'),
  2, 'deposit get-or-creates the Reservas category in both buckets');

-- Bank spend: 'out' entry has no category and bypasses buckets.
insert into public.entries
  (user_id, month_id, category_id, amount_cents, paid_on,
   fund_id, fund_flow)
select 'b3b3b3b3-0000-0000-0000-00000000000a', m.id, null, 15000,
       '2026-08-06', f.id, 'out'
from public.months m, public.funds f
where m.year = 2026 and m.month = 8 and f.name = 'Viagem';

select is(
  (select balance_cents from public.fund_balances fb
   join public.funds f on f.id = fb.fund_id where f.name = 'Viagem'),
  35000::bigint, 'bank spend debits the balance');

-- ----------------------------------------------------------------
-- Shape + flow guards
-- ----------------------------------------------------------------
select throws_ok(
  $$ insert into public.entries
       (user_id, month_id, category_id, amount_cents, paid_on,
        fund_id, fund_flow)
     select 'b3b3b3b3-0000-0000-0000-00000000000a', m.id,
            (select id from public.categories where bucket = 'fun' limit 1),
            100, '2026-08-07', f.id, 'out'
     from public.months m, public.funds f
     where m.year = 2026 and m.month = 8 and f.name = 'Viagem' $$,
  '23514', null,
  'an out entry cannot carry a category (entries_fund_shape)');

select throws_ok(
  $$ insert into public.entries
       (user_id, month_id, category_id, amount_cents, paid_on,
        fund_id, fund_flow)
     select 'b3b3b3b3-0000-0000-0000-00000000000a', m.id, null, 100,
            '2026-08-07', f.id, 'out'
     from public.months m, public.funds f
     where m.year = 2026 and m.month = 8 and f.name = 'Notebook' $$,
  'P0001', 'entries can only spend from active banks',
  'piggy banks never fund spends');

update public.funds set active = false where name = 'Viagem';
select throws_ok(
  $$ insert into public.entries
       (user_id, month_id, category_id, amount_cents, paid_on,
        fund_id, fund_flow)
     select 'b3b3b3b3-0000-0000-0000-00000000000a', m.id, null, 100,
            '2026-08-07', f.id, 'out'
     from public.months m, public.funds f
     where m.year = 2026 and m.month = 8 and f.name = 'Viagem' $$,
  'P0001', 'entries can only spend from active banks',
  'inactive banks reject spends');
update public.funds set active = true where name = 'Viagem';

select throws_ok(
  $$ insert into public.entries
       (user_id, month_id, category_id, amount_cents, paid_on,
        fund_id, fund_flow)
     select 'b3b3b3b3-0000-0000-0000-00000000000a', m.id, null, 40000,
            '2026-08-07', f.id, 'out'
     from public.months m, public.funds f
     where m.year = 2026 and m.month = 8 and f.name = 'Viagem' $$,
  'P0001', 'insufficient fund balance',
  'a bank cannot be spent below zero');

select throws_ok(
  $$ select public.deposit_to_fund(
       (select id from public.funds where name = 'Viagem'),
       (select id from public.months where year = 2026 and month = 8),
       0, 0, '2026-08-05'::date, null) $$,
  'P0001', 'deposit must be > 0 in at least one bucket',
  'empty deposit is rejected');

-- ----------------------------------------------------------------
-- close_month: only the 30000 deposit counts in essential_spent; the
-- 15000 bank spend is invisible to the buckets.
-- ----------------------------------------------------------------
select public.close_month(
  (select id from public.months where year = 2026 and month = 8), 0);

select is(
  (select essential_spent_cents from public.month_summaries
   where user_id = 'b3b3b3b3-0000-0000-0000-00000000000a'),
  30000::bigint, 'summary counts the deposit but not the bank spend');

select is(
  (select fun_spent_cents from public.month_summaries
   where user_id = 'b3b3b3b3-0000-0000-0000-00000000000a'),
  20000::bigint, 'fun spent is the deposit only');

-- ----------------------------------------------------------------
-- delete_fund with extras transfer: balance 35000 lands in the
-- currently open month''s extra_income, then the fund is gone.
-- ----------------------------------------------------------------
select public.delete_fund(
  (select id from public.funds where name = 'Viagem'), true);

select is(
  (select count(*)::int from public.extra_income
   where note = 'Reserva: Viagem' and amount_cents = 35000),
  1, 'delete_fund moves the balance into extras of the open month');

select is(
  (select count(*)::int from public.funds where name = 'Viagem'),
  0, 'fund row is gone after delete_fund');

-- Direct delete is not allowed: no delete policy exists, so a client
-- delete affects zero rows instead of the row.
delete from public.funds where name = 'Notebook';
select is(
  (select count(*)::int from public.funds where name = 'Notebook'),
  1, 'direct client delete touches no rows (deletes go through delete_fund)');

select public.delete_fund(
  (select id from public.funds where name = 'Notebook'), false);
select is(
  (select count(*)::int from public.funds),
  0, 'delete_fund without extras just removes the fund');

-- ----------------------------------------------------------------
-- RLS: V sees none of U's funds or balances.
-- ----------------------------------------------------------------
insert into public.funds (user_id, kind, name)
values ('b3b3b3b3-0000-0000-0000-00000000000a', 'bank', 'Só do U');

set "request.jwt.claim.sub" = 'b3b3b3b3-0000-0000-0000-00000000000b';
set "request.jwt.claims" =
  '{"sub":"b3b3b3b3-0000-0000-0000-00000000000b","role":"authenticated"}';

select is(
  (select count(*)::int from public.funds),
  0, 'second user sees none of the first user''s funds');

select is(
  (select count(*)::int from public.fund_balances),
  0, 'second user sees no fund balances');

reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
