-- Fund deletion split: a bank with no 'out' entries is erased for real
-- (extras-or-discard drain unchanged); a bank with spends is flagged
-- deleted_at and recoverable until close_month purges it — balance lands
-- in the closing month's extras automatically. Plus restore_fund and
-- reopen_fund, and lifecycle guards on deposits.
create extension if not exists pgtap;

begin;

select plan(17);

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        'c6c6c6c6-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
        'u@fsd.test', 'x', now(), '', '', now(), now());

set role authenticated;
set "request.jwt.claim.sub" = 'c6c6c6c6-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"c6c6c6c6-0000-0000-0000-00000000000a","role":"authenticated"}';

select public.open_month(
  extract(year from current_date)::smallint,
  extract(month from current_date)::smallint, 1000000);

insert into public.funds (id, user_id, kind, name) values
  ('fb600000-0000-0000-0000-00000000000a', 'c6c6c6c6-0000-0000-0000-00000000000a', 'bank', 'Viagem'),
  ('fb600000-0000-0000-0000-00000000000b', 'c6c6c6c6-0000-0000-0000-00000000000a', 'bank', 'SóDepósito'),
  ('fb600000-0000-0000-0000-00000000000c', 'c6c6c6c6-0000-0000-0000-00000000000a', 'bank', 'Concluída'),
  ('fb600000-0000-0000-0000-00000000000e', 'c6c6c6c6-0000-0000-0000-00000000000a', 'bank', 'Depois');

-- Viagem: 40k in, 10k spent -> 30k left, has history.
-- SóDepósito: 20k in, never spent. Concluída: 5k in. Depois: 8k in, 3k spent.
select public.deposit_to_fund(
  'fb600000-0000-0000-0000-00000000000a',
  (select id from public.months
   where user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'),
  40000, 0, current_date, null);
select public.deposit_to_fund(
  'fb600000-0000-0000-0000-00000000000b',
  (select id from public.months
   where user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'),
  20000, 0, current_date, null);
select public.deposit_to_fund(
  'fb600000-0000-0000-0000-00000000000c',
  (select id from public.months
   where user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'),
  5000, 0, current_date, null);
select public.deposit_to_fund(
  'fb600000-0000-0000-0000-00000000000e',
  (select id from public.months
   where user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'),
  8000, 0, current_date, null);

insert into public.entries
  (user_id, month_id, amount_cents, paid_on, fund_id, fund_flow)
select 'c6c6c6c6-0000-0000-0000-00000000000a', m.id, 10000, current_date,
       'fb600000-0000-0000-0000-00000000000a', 'out'
from public.months m
where m.user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'
  and m.status = 'open';

insert into public.entries
  (user_id, month_id, amount_cents, paid_on, fund_id, fund_flow)
select 'c6c6c6c6-0000-0000-0000-00000000000a', m.id, 3000, current_date,
       'fb600000-0000-0000-0000-00000000000e', 'out'
from public.months m
where m.user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'
  and m.status = 'open';

-- Completed funds: no delete, no deposit; reopen brings it back at zero.
select public.complete_fund('fb600000-0000-0000-0000-00000000000c', false);

select throws_ok(
  $$ select public.deposit_to_fund(
       'fb600000-0000-0000-0000-00000000000c',
       (select id from public.months
        where user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'),
       100, 0) $$,
  'cannot deposit to a completed or deleted fund');

select throws_ok(
  $$ select public.delete_fund(
       'fb600000-0000-0000-0000-00000000000c', false) $$,
  'completed reserves cannot be deleted');

select public.reopen_fund('fb600000-0000-0000-0000-00000000000c');

select results_eq(
  $$ select completed_at is null, active
     from public.funds where id = 'fb600000-0000-0000-0000-00000000000c' $$,
  $$ values (true, true) $$,
  'reopen_fund clears completion and reactivates');

select is(
  (select balance_cents from public.fund_balances
   where fund_id = 'fb600000-0000-0000-0000-00000000000c'),
  0::bigint, 'reopened bank keeps the drain in its ledger (balance 0)');

select throws_ok(
  $$ select public.reopen_fund(
       'fb600000-0000-0000-0000-00000000000c') $$,
  'fund not found or not completed');

-- Viagem has spends: delete only flags it.
select public.delete_fund('fb600000-0000-0000-0000-00000000000a', false);

select results_eq(
  $$ select deleted_at is not null, active
     from public.funds where id = 'fb600000-0000-0000-0000-00000000000a' $$,
  $$ values (true, false) $$,
  'bank with spends is flagged, not erased');

select throws_ok(
  $$ select public.deposit_to_fund(
       'fb600000-0000-0000-0000-00000000000a',
       (select id from public.months
        where user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'),
       100, 0) $$,
  'cannot deposit to a completed or deleted fund');

select throws_ok(
  $$ insert into public.entries
       (user_id, month_id, amount_cents, paid_on, fund_id, fund_flow)
     select 'c6c6c6c6-0000-0000-0000-00000000000a', m.id, 100, current_date,
            'fb600000-0000-0000-0000-00000000000a', 'out'
     from public.months m
     where m.user_id = 'c6c6c6c6-0000-0000-0000-00000000000a' $$,
  'entries cannot target a deleted fund');

select throws_ok(
  $$ select public.delete_fund(
       'fb600000-0000-0000-0000-00000000000a', false) $$,
  'fund is already marked for deletion');

select public.restore_fund('fb600000-0000-0000-0000-00000000000a');

select results_eq(
  $$ select deleted_at is null, active
     from public.funds where id = 'fb600000-0000-0000-0000-00000000000a' $$,
  $$ values (true, true) $$,
  'restore_fund clears the flag and reactivates');

-- Flag it again for the purge test below.
select public.delete_fund('fb600000-0000-0000-0000-00000000000a', false);

-- SóDepósito has no spends: delete erases it, balance -> extras as before.
select public.delete_fund('fb600000-0000-0000-0000-00000000000b', true);

select ok(
  (select count(*) from public.funds
   where id = 'fb600000-0000-0000-0000-00000000000b') = 0,
  'spendless bank is erased for real');

select is(
  (select amount_cents from public.extra_income
   where user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'),
  20000::bigint, 'erased bank balance lands in extras');

-- Closing a month that is NOT the current one must not purge.
select public.delete_fund('fb600000-0000-0000-0000-00000000000e', false);

select public.open_month(
  extract(year from current_date + interval '1 month')::smallint,
  extract(month from current_date + interval '1 month')::smallint, 500000);

select public.close_month(
  (select id from public.months
   where user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'
     and year = extract(year from current_date + interval '1 month')::smallint
     and month = extract(month from current_date + interval '1 month')::smallint),
  0);

select ok(
  (select deleted_at is not null from public.funds
   where id = 'fb600000-0000-0000-0000-00000000000e'),
  'closing a non-current month leaves flagged funds alone');

-- Closing the current month purges both flagged banks into its extras.
select public.close_month(
  (select id from public.months
   where user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'
     and status = 'open'),
  0);

select ok(
  (select count(*) from public.funds
   where id in ('fb600000-0000-0000-0000-00000000000a',
                'fb600000-0000-0000-0000-00000000000e')) = 0,
  'close_month erases flagged banks for good');

select is(
  (select sum(amount_cents)::bigint from public.extra_income
   where user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'),
  55000::bigint, 'purged balances (30k + 5k) join the earlier 20k extra');

select is(
  (select extra_income_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where ms.user_id = 'c6c6c6c6-0000-0000-0000-00000000000a'
     and m.year = extract(year from current_date)::smallint
     and m.month = extract(month from current_date)::smallint),
  55000::bigint, 'purge extras are counted in the stored summary');

select throws_ok(
  $$ select public.restore_fund(
       'fb600000-0000-0000-0000-00000000000a') $$,
  'fund not found or not marked for deletion');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
