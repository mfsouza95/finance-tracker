-- Fatura fields + latest-open write target:
--   * months carry closes_on/payday_on (informational, set at open, editable)
--   * deposit_to_fund only accepts the latest open month and takes any date
--   * delete_fund/complete_fund extras + drains land in the latest open month
--   * soft-deleted banks anchor to deleted_in_month_id — only that month's
--     close purges them; a null anchor purges at the next close
create extension if not exists pgtap;

begin;

select plan(17);

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        'f7f7f7f7-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
        'u@fat.test', 'x', now(), '', '', now(), now());

set role authenticated;
set "request.jwt.claim.sub" = 'f7f7f7f7-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"f7f7f7f7-0000-0000-0000-00000000000a","role":"authenticated"}';

-- Two open months: 2026-10 (with dates) and 2026-11 (latest).
select public.open_month(2026::smallint, 10::smallint, 1000000,
  '2026-11-03'::date, '2026-11-07'::date);
select public.open_month(2026::smallint, 11::smallint, 500000);

select results_eq(
  $$ select closes_on, payday_on from public.months
     where year = 2026 and month = 10 $$,
  $$ values ('2026-11-03'::date, '2026-11-07'::date) $$,
  'open_month persists closes_on and payday_on');

update public.months set closes_on = '2026-11-05'
where year = 2026 and month = 10;
select is(
  (select closes_on from public.months where year = 2026 and month = 10),
  '2026-11-05'::date, 'closes_on is editable on an open month');

select is(
  (select closes_on from public.months where year = 2026 and month = 11),
  null::date, 'dates are optional — 2026-11 has none');

insert into public.funds (id, user_id, kind, name, goal_cents) values
  ('f7a00000-0000-0000-0000-00000000000a', 'f7f7f7f7-0000-0000-0000-00000000000a', 'bank', 'ComHist', null),
  ('f7a00000-0000-0000-0000-00000000000b', 'f7f7f7f7-0000-0000-0000-00000000000a', 'piggy', 'SemHist', 100000),
  ('f7a00000-0000-0000-0000-00000000000c', 'f7f7f7f7-0000-0000-0000-00000000000a', 'bank', 'Completa', null),
  ('f7a00000-0000-0000-0000-00000000000d', 'f7f7f7f7-0000-0000-0000-00000000000a', 'bank', 'SemAncora', null),
  ('f7a00000-0000-0000-0000-00000000000e', 'f7f7f7f7-0000-0000-0000-00000000000a', 'bank', 'Restaura', null);

-- Deposits only charge the latest open month (2026-11), not 2026-10.
select throws_ok(
  $$ select public.deposit_to_fund(
       'f7a00000-0000-0000-0000-00000000000a',
       (select id from public.months where year = 2026 and month = 10),
       40000, 0) $$,
  'deposits go to the latest open month');

select lives_ok(
  $$ select public.deposit_to_fund(
       'f7a00000-0000-0000-0000-00000000000a',
       (select id from public.months where year = 2026 and month = 11),
       40000, 0) $$,
  'deposit into the latest open month works');

select lives_ok(
  $$ select public.deposit_to_fund(
       'f7a00000-0000-0000-0000-00000000000b',
       (select id from public.months where year = 2026 and month = 11),
       20000, 0, '2020-01-01'::date, null) $$,
  'deposit accepts a paid_on outside the label month');

-- Remaining fixture balances (latest month targets).
select public.deposit_to_fund('f7a00000-0000-0000-0000-00000000000c',
  (select id from public.months where year = 2026 and month = 11), 5000, 0);
select public.deposit_to_fund('f7a00000-0000-0000-0000-00000000000d',
  (select id from public.months where year = 2026 and month = 11), 8000, 0);
select public.deposit_to_fund('f7a00000-0000-0000-0000-00000000000e',
  (select id from public.months where year = 2026 and month = 11), 5000, 0);

-- Spends for A/D/E: 'out' entries are free-form — 2026-10 takes them fine.
insert into public.entries
  (user_id, month_id, amount_cents, paid_on, fund_id, fund_flow)
select 'f7f7f7f7-0000-0000-0000-00000000000a', m.id, v.amt, '2026-10-15',
       v.fid, 'out'
from public.months m,
     (values ('f7a00000-0000-0000-0000-00000000000a'::uuid, 10000),
             ('f7a00000-0000-0000-0000-00000000000d'::uuid, 3000),
             ('f7a00000-0000-0000-0000-00000000000e'::uuid, 1000)) as v(fid, amt)
where m.year = 2026 and m.month = 10;

-- Flag A (has spends): anchors to the latest open month, not the viewed one.
select public.delete_fund('f7a00000-0000-0000-0000-00000000000a', false);
select is(
  (select deleted_in_month_id from public.funds
   where id = 'f7a00000-0000-0000-0000-00000000000a'),
  (select id from public.months where year = 2026 and month = 11),
  'soft-delete anchors to the latest open month');

-- Piggy P (no spends) hard-deletes; its 20000 extras land in 2026-11.
select public.delete_fund('f7a00000-0000-0000-0000-00000000000b', true);
select is(
  (select month_id from public.extra_income where note = 'Cofrinho: SemHist'),
  (select id from public.months where year = 2026 and month = 11),
  'delete_fund extras land in the latest open month');

-- Flag + restore E: the anchor is cleared along with the flag.
select public.delete_fund('f7a00000-0000-0000-0000-00000000000e', false);
select public.restore_fund('f7a00000-0000-0000-0000-00000000000e');
select results_eq(
  $$ select deleted_at is null, deleted_in_month_id is null, active
     from public.funds where id = 'f7a00000-0000-0000-0000-00000000000e' $$,
  $$ values (true, true, true) $$,
  'restore_fund clears the flag and the anchor');

-- Complete C with extras: drain entry AND extras land in 2026-11.
select public.complete_fund('f7a00000-0000-0000-0000-00000000000c', true);
select is(
  (select month_id from public.entries
   where fund_id = 'f7a00000-0000-0000-0000-00000000000c'
     and fund_flow = 'out' and note like 'Concluída%'),
  (select id from public.months where year = 2026 and month = 11),
  'complete_fund drain entry lands in the latest open month');
select is(
  (select month_id from public.extra_income where note = 'Reserva: Completa'),
  (select id from public.months where year = 2026 and month = 11),
  'complete_fund extras land in the latest open month');

-- Closing 2026-10 (not A's anchor) must not purge A.
select public.close_month(
  (select id from public.months where year = 2026 and month = 10), 0);
select ok(
  (select deleted_at is not null from public.funds
   where id = 'f7a00000-0000-0000-0000-00000000000a'),
  'closing a non-anchor month leaves the flagged bank alone');

-- Closing 2026-11 (the anchor) purges A; its 30000 lands in extras.
select public.close_month(
  (select id from public.months where year = 2026 and month = 11), 0);
select ok(
  (select count(*) from public.funds
   where id = 'f7a00000-0000-0000-0000-00000000000a') = 0,
  'closing the anchor month purges the flagged bank');
select is(
  (select amount_cents from public.extra_income where note = 'Reserva: ComHist'),
  30000::bigint, 'purged balance lands in the anchor month''s extras');

-- No open months left: flagging D leaves the anchor null, and the next
-- close purges it.
select public.delete_fund('f7a00000-0000-0000-0000-00000000000d', false);
select is(
  (select deleted_in_month_id from public.funds
   where id = 'f7a00000-0000-0000-0000-00000000000d'),
  null::uuid, 'flag with no open month leaves the anchor null');

select public.open_month(2026::smallint, 12::smallint, 100000);
select public.close_month(
  (select id from public.months where year = 2026 and month = 12), 0);
select ok(
  (select count(*) from public.funds
   where id = 'f7a00000-0000-0000-0000-00000000000d') = 0,
  'null-anchor fund purges at the next close');
select is(
  (select month_id from public.extra_income where note = 'Reserva: SemAncora'),
  (select id from public.months where year = 2026 and month = 12),
  'null-anchor purge lands in whichever month closes');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
