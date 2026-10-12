-- complete_fund: finishing a bank keeps the fund row (entries keep
-- fund_id → full history survives), drains the remainder with a balancing
-- 'out' entry, and optionally mirrors it into the month's extras.
create extension if not exists pgtap;

begin;

select plan(9);

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        'c5c5c5c5-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
        'u@fcpl.test', 'x', now(), '', '', now(), now());

set role authenticated;
set "request.jwt.claim.sub" = 'c5c5c5c5-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"c5c5c5c5-0000-0000-0000-00000000000a","role":"authenticated"}';

select public.open_month(
  extract(year from current_date)::smallint,
  extract(month from current_date)::smallint, 1000000);

insert into public.funds (id, user_id, kind, name) values
  ('fa500000-0000-0000-0000-00000000000a', 'c5c5c5c5-0000-0000-0000-00000000000a', 'bank', 'Viagem'),
  ('fa500000-0000-0000-0000-00000000000b', 'c5c5c5c5-0000-0000-0000-00000000000a', 'bank', 'Carro'),
  ('fa500000-0000-0000-0000-00000000000c', 'c5c5c5c5-0000-0000-0000-00000000000a', 'bank', 'Vazia'),
  ('fa500000-0000-0000-0000-00000000000d', 'c5c5c5c5-0000-0000-0000-00000000000a', 'bank', 'Fechada');

-- Viagem: 40k in, 10k spent -> 30k left. Carro: 20k. Fechada: 5k.
select public.deposit_to_fund(
  'fa500000-0000-0000-0000-00000000000a',
  (select id from public.months
   where user_id = 'c5c5c5c5-0000-0000-0000-00000000000a'),
  40000, 0, current_date, null);
select public.deposit_to_fund(
  'fa500000-0000-0000-0000-00000000000b',
  (select id from public.months
   where user_id = 'c5c5c5c5-0000-0000-0000-00000000000a'),
  20000, 0, current_date, null);
select public.deposit_to_fund(
  'fa500000-0000-0000-0000-00000000000d',
  (select id from public.months
   where user_id = 'c5c5c5c5-0000-0000-0000-00000000000a'),
  5000, 0, current_date, null);

insert into public.entries
  (user_id, month_id, amount_cents, paid_on, fund_id, fund_flow)
select 'c5c5c5c5-0000-0000-0000-00000000000a', m.id, 10000, current_date,
       'fa500000-0000-0000-0000-00000000000a', 'out'
from public.months m
where m.user_id = 'c5c5c5c5-0000-0000-0000-00000000000a';

-- A bank with balance cannot complete while no month is open.
select public.close_month(
  (select id from public.months
   where user_id = 'c5c5c5c5-0000-0000-0000-00000000000a'), 0);

select throws_ok(
  $$ select public.complete_fund(
       'fa500000-0000-0000-0000-00000000000d', false) $$,
  'open the current month to complete a reserve with balance');

-- A zero-balance bank completes fine even without an open month.
select public.complete_fund('fa500000-0000-0000-0000-00000000000c', false);

select ok(
  (select completed_at is not null from public.funds
   where id = 'fa500000-0000-0000-0000-00000000000c'),
  'zero-balance bank completes without an open month');

select public.reopen_month(
  (select id from public.months
   where user_id = 'c5c5c5c5-0000-0000-0000-00000000000a'));

-- Complete Viagem moving the 30k remainder into the month's extras.
select public.complete_fund('fa500000-0000-0000-0000-00000000000a', true);

select is(
  (select amount_cents from public.extra_income
   where user_id = 'c5c5c5c5-0000-0000-0000-00000000000a'),
  30000::bigint, 'remainder lands in extras when requested');

select is(
  (select balance_cents from public.fund_balances
   where fund_id = 'fa500000-0000-0000-0000-00000000000a'),
  0::bigint, 'drain entry zeroes the balance');

select is(
  (select count(*) from public.entries
   where fund_id = 'fa500000-0000-0000-0000-00000000000a'),
  3::bigint, 'deposit + spend + drain rows all keep fund_id (history)');

select results_eq(
  $$ select completed_at is not null, active
     from public.funds where id = 'fa500000-0000-0000-0000-00000000000a' $$,
  $$ values (true, false) $$,
  'completed bank is stamped and deactivated');

-- Complete Carro discarding the remainder: still drains via an 'out' row.
select public.complete_fund('fa500000-0000-0000-0000-00000000000b', false);

select is(
  (select count(*) from public.entries
   where fund_id = 'fa500000-0000-0000-0000-00000000000b'
     and fund_flow = 'out' and note like 'Concluída%'),
  1::bigint, 'discard path still writes the drain row');

select throws_ok(
  $$ select public.complete_fund(
       'fa500000-0000-0000-0000-00000000000a', false) $$,
  'fund is already completed');

select throws_ok(
  $$ insert into public.entries
       (user_id, month_id, amount_cents, paid_on, fund_id, fund_flow)
     select 'c5c5c5c5-0000-0000-0000-00000000000a', m.id, 100, current_date,
            'fa500000-0000-0000-0000-00000000000a', 'out'
     from public.months m
     where m.user_id = 'c5c5c5c5-0000-0000-0000-00000000000a' $$,
  'entries can only spend from active banks',
  'completed bank rejects new spends');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
