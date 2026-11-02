-- pace_snapshots: per-(month, kind, scope, period) fixed allowance rows
-- written by plain client upsert under RLS.
create extension if not exists pgtap;

begin;

select plan(7);

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        'a8a8a8a8-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
        'u@pace.test', 'x', now(), '', '', now(), now()),
       ('00000000-0000-0000-0000-000000000000',
        'a8a8a8a8-0000-0000-0000-00000000000b', 'authenticated', 'authenticated',
        'v@pace.test', 'x', now(), '', '', now(), now());

set role authenticated;
set "request.jwt.claim.sub" = 'a8a8a8a8-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"a8a8a8a8-0000-0000-0000-00000000000a","role":"authenticated"}';

select public.open_month(2026::smallint, 11::smallint, 1000000);

-- Round-trip: a day + a week row for the 'all' scope.
insert into public.pace_snapshots
  (month_id, kind, scope, period_start, user_id, allowance_cents)
select m.id, v.kind, 'all', v.start,
       'a8a8a8a8-0000-0000-0000-00000000000a', 10000
from public.months m,
     (values ('day'::text, '2026-11-02'::date),
             ('week'::text, '2026-11-02'::date)) as v(kind, start)
where m.year = 2026 and m.month = 11;

select is(
  (select count(*)::int from public.pace_snapshots),
  2, 'day and week snapshots insert for a scope');

-- Ensure semantics: duplicate insert does nothing, first write wins.
insert into public.pace_snapshots
  (month_id, kind, scope, period_start, user_id, allowance_cents)
select m.id, 'day', 'all', '2026-11-02',
       'a8a8a8a8-0000-0000-0000-00000000000a', 99999
from public.months m where m.year = 2026 and m.month = 11
on conflict (month_id, kind, scope, period_start) do nothing;

select is(
  (select allowance_cents from public.pace_snapshots where kind = 'day'),
  10000::bigint, 'ignore-duplicates upsert keeps the first allowance');

-- Recalc semantics: overwriting upsert replaces the figure.
insert into public.pace_snapshots
  (month_id, kind, scope, period_start, user_id, allowance_cents)
select m.id, 'day', 'all', '2026-11-02',
       'a8a8a8a8-0000-0000-0000-00000000000a', 5000
from public.months m where m.year = 2026 and m.month = 11
on conflict (month_id, kind, scope, period_start)
  do update set allowance_cents = excluded.allowance_cents,
                computed_at = now();

select is(
  (select allowance_cents from public.pace_snapshots where kind = 'day'),
  5000::bigint, 'recalc upsert overwrites the allowance');

-- Scope is part of the key: a different scope gets its own row.
insert into public.pace_snapshots
  (month_id, kind, scope, period_start, user_id, allowance_cents)
select m.id, 'day', 'fun', '2026-11-02',
       'a8a8a8a8-0000-0000-0000-00000000000a', 3000
from public.months m where m.year = 2026 and m.month = 11;

select is(
  (select count(*)::int from public.pace_snapshots
   where kind = 'day' and period_start = '2026-11-02'),
  2, 'each scope holds its own fixed figure');

select throws_ok(
  $$ insert into public.pace_snapshots
       (month_id, kind, scope, period_start, user_id, allowance_cents)
     select m.id, 'month', 'all', '2026-11-02',
            'a8a8a8a8-0000-0000-0000-00000000000a', 1
     from public.months m where m.year = 2026 and m.month = 11 $$,
  '23514', null, 'kind is constrained to day/week');

-- RLS: the second user sees nothing and cannot write into my month.
set "request.jwt.claim.sub" = 'a8a8a8a8-0000-0000-0000-00000000000b';
set "request.jwt.claims" =
  '{"sub":"a8a8a8a8-0000-0000-0000-00000000000b","role":"authenticated"}';

select is(
  (select count(*)::int from public.pace_snapshots),
  0, 'second user sees no snapshots');

set "request.jwt.claim.sub" = 'a8a8a8a8-0000-0000-0000-00000000000a';
set "request.jwt.claims" =
  '{"sub":"a8a8a8a8-0000-0000-0000-00000000000a","role":"authenticated"}';

-- Deleting the open month cascades its snapshots.
delete from public.months where year = 2026 and month = 11;

select is(
  (select count(*)::int from public.pace_snapshots),
  0, 'deleting the month cascades its snapshots');

reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select * from finish();
rollback;
