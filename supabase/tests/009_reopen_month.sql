-- reopen_month: guarded closed -> open transition.
-- Covers the round trip (open -> close -> reopen -> re-close), the deleted
-- summary, restored entry editability, and every rejection path.
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
   '92929292-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
   'u@reopen.test', 'x', now(), '', '', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '92929292-0000-0000-0000-00000000000b', 'authenticated', 'authenticated',
   'v@reopen.test', 'x', now(), '', '', now(), now());

insert into public.categories (id, user_id, bucket, name)
values
  ('ca920000-0000-0000-0000-000000000001',
   '92929292-0000-0000-0000-00000000000a', 'essential', 'U ess');

set role authenticated;
set "request.jwt.claim.sub" = '92929292-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"92929292-0000-0000-0000-00000000000a","role":"authenticated"}';

-- U: open September with an entry, then close it.
select public.open_month(2026::smallint, 9::smallint, 100000);
insert into public.entries (user_id, month_id, category_id, amount_cents, paid_on)
select '92929292-0000-0000-0000-00000000000a', m.id,
       'ca920000-0000-0000-0000-000000000001', 1000, '2026-09-05'
from public.months m
where m.user_id = '92929292-0000-0000-0000-00000000000a' and m.month = 9;
select public.close_month(
  (select id from public.months
   where user_id = '92929292-0000-0000-0000-00000000000a' and month = 9), 5000);

-- Reopening an OPEN month is rejected. October is U's open month.
select public.open_month(2026::smallint, 10::smallint, 100000);
select throws_ok(
  $$ select public.reopen_month(
    (select id from public.months
     where user_id = '92929292-0000-0000-0000-00000000000a' and month = 10)) $$,
  'P0001', 'month is not closed',
  'reopen_month rejects an open month');

-- Reopen the closed September.
select lives_ok(
  $$ select public.reopen_month(
    (select id from public.months
     where user_id = '92929292-0000-0000-0000-00000000000a' and month = 9)) $$,
  'reopen_month succeeds on a closed month');

select is(
  (select status = 'open' and closed_at is null and invested_cents is null
   from public.months
   where user_id = '92929292-0000-0000-0000-00000000000a' and month = 9),
  true,
  'reopened month is open with closed_at and invested_cents cleared');

select is(
  (select count(*)::int from public.month_summaries
   where user_id = '92929292-0000-0000-0000-00000000000a'),
  0, 'reopen deletes the summary row');

-- Entries are fully editable again on the reopened month.
select lives_ok(
  $$ insert into public.entries
    (user_id, month_id, category_id, amount_cents, paid_on)
    select '92929292-0000-0000-0000-00000000000a', m.id,
           'ca920000-0000-0000-0000-000000000001', 2500, '2026-09-10'
    from public.months m
    where m.user_id = '92929292-0000-0000-0000-00000000000a' and m.month = 9 $$,
  'entries can be inserted again after reopen');

select lives_ok(
  $$ update public.entries set amount_cents = 2600
     where user_id = '92929292-0000-0000-0000-00000000000a'
       and amount_cents = 2500 $$,
  'entries can be updated again after reopen');

-- Re-close works and writes a fresh summary (now with 2 entries spent).
select lives_ok(
  $$ select public.close_month(
    (select id from public.months
     where user_id = '92929292-0000-0000-0000-00000000000a' and month = 9), 3000) $$,
  're-close works after reopen');

select is(
  (select ms.essential_spent_cents from public.month_summaries ms
   join public.months m on m.id = ms.month_id
   where ms.user_id = '92929292-0000-0000-0000-00000000000a' and m.month = 9),
  3600::bigint, 're-closed summary recomputes from current entries');

-- Direct client update closed -> open is still blocked.
select throws_ok(
  $$ update public.months set status = 'open', closed_at = null, invested_cents = null
     where user_id = '92929292-0000-0000-0000-00000000000a' and month = 9 $$,
  'P0001', 'closed months are read-only',
  'client cannot reopen a month without the RPC');

-- V's closed month: captured by id, invisible and uncloseable to U.
reset role;
insert into public.categories (id, user_id, bucket, name)
values ('ca920000-0000-0000-0000-000000000002',
        '92929292-0000-0000-0000-00000000000b', 'essential', 'V ess');
set role authenticated;
set "request.jwt.claim.sub" = '92929292-0000-0000-0000-00000000000b';
set "request.jwt.claims" =
  '{"sub":"92929292-0000-0000-0000-00000000000b","role":"authenticated"}';
select public.open_month(2026::smallint, 9::smallint, 50000);
select public.close_month(
  (select id from public.months
   where user_id = '92929292-0000-0000-0000-00000000000b' and month = 9), 0);

-- U tries to reopen V's month by its real id (captured as superuser).
reset role;
create temp table v_month as
select id from public.months
where user_id = '92929292-0000-0000-0000-00000000000b' and month = 9;
grant select on v_month to authenticated;
set role authenticated;
set "request.jwt.claim.sub" = '92929292-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"92929292-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok(
  $$ select public.reopen_month((select id from v_month)) $$,
  'P0001', 'month not found',
  'reopen_month rejects another user''s month');

-- RLS hides V's month from U, so the "still closed" check runs as superuser.
reset role;
select is(
  (select status from public.months
   where user_id = '92929292-0000-0000-0000-00000000000b' and month = 9),
  'closed'::public.month_status, 'foreign month stays closed');

-- anon cannot execute reopen_month at all.
reset role;
set role anon;
select throws_ok(
  $$ select public.reopen_month(gen_random_uuid()) $$,
  '42501', null,
  'anon cannot execute reopen_month');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
