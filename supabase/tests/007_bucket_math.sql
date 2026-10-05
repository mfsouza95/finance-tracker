-- Bucket math through the real open_month/close_month path:
--  * spent sums are scoped to the closed month and the closing user
--  * presets 60/20/20 and 70/20/10 on nets with remainders
--  * edge nets 0, 1, 99
--  * close_month uses the split snapshotted on the month, not current settings
--  * a 40-case (net, split) table asserting floor math, non-negative
--    buckets and buckets summing to net
create extension if not exists pgtap;

begin;

select plan(10);

-- ----------------------------------------------------------------
-- Fixtures
-- ----------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000',
   '81818181-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
   'u1@test.local', 'x', now(), '', '', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '81818181-0000-0000-0000-00000000000b', 'authenticated', 'authenticated',
   'u2@test.local', 'x', now(), '', '', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '81818181-0000-0000-0000-00000000000c', 'authenticated', 'authenticated',
   'u3@test.local', 'x', now(), '', '', now(), now());

insert into public.categories (id, user_id, bucket, name)
values
  ('ca810000-0000-0000-0000-000000000001',
   '81818181-0000-0000-0000-00000000000a', 'essential', 'U1 ess'),
  ('ca810000-0000-0000-0000-000000000002',
   '81818181-0000-0000-0000-00000000000c', 'essential', 'U3 ess'),
  ('ca810000-0000-0000-0000-000000000003',
   '81818181-0000-0000-0000-00000000000c', 'essential', 'U3 bills');

-- ----------------------------------------------------------------
-- Scope: closing U1's January must not count February entries or
-- another user's January entries.
-- ----------------------------------------------------------------
set role authenticated;
set "request.jwt.claim.sub" = '81818181-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"81818181-0000-0000-0000-00000000000a","role":"authenticated"}';

select public.open_month(2026::smallint, 1::smallint, 500000);
select public.open_month(2026::smallint, 2::smallint, 500000);
insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select '81818181-0000-0000-0000-00000000000a', m.id,
       'ca810000-0000-0000-0000-000000000001', v.amount, '2026-01-05'
from public.months m, (values (4000)) v(amount)
where m.user_id = '81818181-0000-0000-0000-00000000000a' and m.month = 1;
insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select '81818181-0000-0000-0000-00000000000a', m.id,
       'ca810000-0000-0000-0000-000000000001', v.amount, '2026-02-05'
from public.months m, (values (9000)) v(amount)
where m.user_id = '81818181-0000-0000-0000-00000000000a' and m.month = 2;

-- Another user's January entry must be invisible to U1's close.
set "request.jwt.claim.sub" = '81818181-0000-0000-0000-00000000000c';
set "request.jwt.claims" =
  '{"sub":"81818181-0000-0000-0000-00000000000c","role":"authenticated"}';
-- Opened in 2031 so it does not collide with the sweep's 2026-2029 months.
select public.open_month(2031::smallint, 1::smallint, 500000);
insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select '81818181-0000-0000-0000-00000000000c', m.id,
       'ca810000-0000-0000-0000-000000000002', 7777, '2031-01-05'
from public.months m
where m.user_id = '81818181-0000-0000-0000-00000000000c'
  and m.year = 2031 and m.month = 1;

set "request.jwt.claim.sub" = '81818181-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"81818181-0000-0000-0000-00000000000a","role":"authenticated"}';
select public.close_month(
  (select id from public.months
   where user_id = '81818181-0000-0000-0000-00000000000a' and month = 1), 0);

select is(
  (select ms.essential_spent_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where ms.user_id = '81818181-0000-0000-0000-00000000000a' and m.month = 1),
  4000::bigint, 'spent counts only the closed month, not other months');
select is(
  (select count(*)::int from public.month_summaries
   where user_id = '81818181-0000-0000-0000-00000000000a'),
  1, 'close_month wrote exactly one summary');

-- ----------------------------------------------------------------
-- Presets and edge nets (U2)
-- ----------------------------------------------------------------
set "request.jwt.claim.sub" = '81818181-0000-0000-0000-00000000000b';
set "request.jwt.claims" =
  '{"sub":"81818181-0000-0000-0000-00000000000b","role":"authenticated"}';

update public.budget_settings
set essential_pct = 60, fun_pct = 20, invest_pct = 20
where user_id = '81818181-0000-0000-0000-00000000000b';
select public.open_month(2030::smallint, 1::smallint, 10007);
select public.close_month(
  (select id from public.months
   where user_id = '81818181-0000-0000-0000-00000000000b'
     and year = 2030 and month = 1), 0);
select is(
  (select array[ms.essential_budget_cents, ms.fun_budget_cents, ms.invest_target_cents]
   from public.month_summaries ms join public.months m on m.id = ms.month_id
   where ms.user_id = '81818181-0000-0000-0000-00000000000b'
     and m.year = 2030 and m.month = 1),
  '{6004,2001,2002}'::bigint[], '60/20/20 on net 10007 (remainder to invest)');

update public.budget_settings
set essential_pct = 70, fun_pct = 20, invest_pct = 10
where user_id = '81818181-0000-0000-0000-00000000000b';
select public.open_month(2030::smallint, 2::smallint, 9999);
select public.close_month(
  (select id from public.months
   where user_id = '81818181-0000-0000-0000-00000000000b'
     and year = 2030 and month = 2), 0);
select is(
  (select array[ms.essential_budget_cents, ms.fun_budget_cents, ms.invest_target_cents]
   from public.month_summaries ms join public.months m on m.id = ms.month_id
   where ms.user_id = '81818181-0000-0000-0000-00000000000b'
     and m.year = 2030 and m.month = 2),
  '{6999,1999,1001}'::bigint[], '70/20/10 on net 9999');

-- Edge nets at 50/30/20
update public.budget_settings
set essential_pct = 50, fun_pct = 30, invest_pct = 20
where user_id = '81818181-0000-0000-0000-00000000000b';
select public.open_month(2030::smallint, 3::smallint, 0);
select public.open_month(2030::smallint, 4::smallint, 1);
select public.open_month(2030::smallint, 5::smallint, 99);
select public.close_month(
  (select id from public.months where user_id = '81818181-0000-0000-0000-00000000000b'
   and year = 2030 and month = 3), 0);
select public.close_month(
  (select id from public.months where user_id = '81818181-0000-0000-0000-00000000000b'
   and year = 2030 and month = 4), 0);
select public.close_month(
  (select id from public.months where user_id = '81818181-0000-0000-0000-00000000000b'
   and year = 2030 and month = 5), 0);

select is(
  (select array[ms.essential_budget_cents, ms.fun_budget_cents, ms.invest_target_cents]
   from public.month_summaries ms join public.months m on m.id = ms.month_id
   where ms.user_id = '81818181-0000-0000-0000-00000000000b'
     and m.year = 2030 and m.month = 3),
  '{0,0,0}'::bigint[], 'net 0 closes to all-zero buckets');
select is(
  (select array[ms.essential_budget_cents, ms.fun_budget_cents, ms.invest_target_cents]
   from public.month_summaries ms join public.months m on m.id = ms.month_id
   where ms.user_id = '81818181-0000-0000-0000-00000000000b'
     and m.year = 2030 and m.month = 4),
  '{0,0,1}'::bigint[], 'net 1 puts the cent in invest');
select is(
  (select array[ms.essential_budget_cents, ms.fun_budget_cents, ms.invest_target_cents]
   from public.month_summaries ms join public.months m on m.id = ms.month_id
   where ms.user_id = '81818181-0000-0000-0000-00000000000b'
     and m.year = 2030 and m.month = 5),
  '{49,29,21}'::bigint[], 'net 99 floors essential/fun, remainder to invest');

-- close_month uses the snapshot taken at open, not current settings.
select public.open_month(2030::smallint, 6::smallint, 10000);  -- opened at 50/30/20
update public.budget_settings
set essential_pct = 70, fun_pct = 20, invest_pct = 10
where user_id = '81818181-0000-0000-0000-00000000000b';
select public.close_month(
  (select id from public.months where user_id = '81818181-0000-0000-0000-00000000000b'
   and year = 2030 and month = 6), 0);
select is(
  (select array[ms.essential_budget_cents, ms.fun_budget_cents, ms.invest_target_cents]
   from public.month_summaries ms join public.months m on m.id = ms.month_id
   where ms.user_id = '81818181-0000-0000-0000-00000000000b'
     and m.year = 2030 and m.month = 6),
  '{5000,3000,2000}'::bigint[], 'close uses snapshotted split, not current settings');

-- ----------------------------------------------------------------
-- 40-case sweep (U3). Keep the VALUES list aligned with the
-- TypeScript computeBuckets tests.
-- ----------------------------------------------------------------
create temp table math_cases (
  yr smallint, mo smallint,
  net bigint, ep smallint, fp smallint, ip smallint
);
insert into math_cases values
  (2026,  1,   10003, 50, 30, 20), (2026,  2,    9999, 55, 25, 20),
  (2026,  3,       7, 60, 20, 20), (2026,  4,     101, 70, 20, 10),
  (2026,  5,  250001, 50, 30, 20), (2026,  6,   33333, 55, 25, 20),
  (2026,  7,       1, 60, 20, 20), (2026,  8,      99, 70, 20, 10),
  (2026,  9,   50000, 33, 33, 34), (2026, 10,  876543,  0, 50, 50),
  (2026, 11,      42, 100, 0,  0), (2026, 12,   77777,  1,  1, 98),
  (2027,  1,   10001, 50, 30, 20), (2027,  2,  200003, 55, 25, 20),
  (2027,  3,     999, 60, 20, 20), (2027,  4,   88888, 70, 20, 10),
  (2027,  5,       3, 25, 45, 30), (2027,  6,  999999, 80, 10, 10),
  (2027,  7,   54321, 50, 30, 20), (2027,  8,       0, 55, 25, 20),
  (2027,  9,      11, 60, 20, 20), (2027, 10,  123457, 70, 20, 10),
  (2027, 11,   60001, 33, 33, 34), (2027, 12,       5,  0, 50, 50),
  (2028,  1,   90001, 100, 0,  0), (2028,  2,      17,  1,  1, 98),
  (2028,  3,   44444, 50, 30, 20), (2028,  4,       2, 55, 25, 20),
  (2028,  5,  654321, 60, 20, 20), (2028,  6,  100000, 70, 20, 10),
  (2028,  7,      29, 25, 45, 30), (2028,  8,  765432, 80, 10, 10),
  (2028,  9,     100, 50, 30, 20), (2028, 10,   55555, 55, 25, 20),
  (2028, 11,   99999, 60, 20, 20), (2028, 12,       8, 70, 20, 10),
  (2029,  1,  300003, 50, 30, 20), (2029,  2,      13, 55, 25, 20),
  (2029,  3,  199999, 60, 20, 20), (2029,  4,     777, 70, 20, 10);

set "request.jwt.claim.sub" = '81818181-0000-0000-0000-00000000000c';
set "request.jwt.claims" =
  '{"sub":"81818181-0000-0000-0000-00000000000c","role":"authenticated"}';

do $$
declare
  r record;
  v_id uuid;
begin
  for r in select * from math_cases order by yr, mo loop
    update public.budget_settings
    set essential_pct = r.ep, fun_pct = r.fp, invest_pct = r.ip
    where user_id = '81818181-0000-0000-0000-00000000000c';
    perform public.open_month(r.yr, r.mo, r.net);
    select m.id into v_id from public.months m
    where m.user_id = '81818181-0000-0000-0000-00000000000c'
      and m.year = r.yr and m.month = r.mo;
    perform public.close_month(v_id, 0);
  end loop;
end $$;

select is(
  (select count(*)::int from public.month_summaries
   where user_id = '81818181-0000-0000-0000-00000000000c'),
  40, 'sweep closed all 40 case months');

select results_eq(
  $$ select m.year, m.month,
            ms.essential_budget_cents,
            ms.fun_budget_cents,
            ms.invest_target_cents,
            (ms.essential_budget_cents >= 0
             and ms.fun_budget_cents >= 0
             and ms.invest_target_cents >= 0) as nonneg,
            (ms.essential_budget_cents + ms.fun_budget_cents
             + ms.invest_target_cents = ms.net_income_cents) as sums_to_net,
            (ms.essential_budget_cents
             = m.net_income_cents * m.essential_pct / 100) as essential_ok,
            (ms.fun_budget_cents
             = m.net_income_cents * m.fun_pct / 100) as fun_ok
     from public.month_summaries ms
     join public.months m on m.id = ms.month_id
     join math_cases c on c.yr = m.year and c.mo = m.month
     where ms.user_id = '81818181-0000-0000-0000-00000000000c'
     order by m.year, m.month $$,
  $$ select yr, mo,
            (net * ep) / 100,
            (net * fp) / 100,
            net - (net * ep) / 100 - (net * fp) / 100,
            true, true, true, true
     from math_cases order by yr, mo $$,
  '40 cases: floor math holds, buckets non-negative and sum to net');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
