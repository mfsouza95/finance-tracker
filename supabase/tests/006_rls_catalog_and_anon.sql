-- Catalog check: every ordinary table in public must have RLS enabled.
-- Anon role: reads return zero rows and writes touch zero rows on EVERY
-- public table — asserted dynamically so new tables are covered without
-- updating this file. Inserts fail at the grant level (42501); one
-- representative per policy shape is enough.
create extension if not exists pgtap;

begin;

select plan(6);

-- One fixture user with data so the anon read check is not vacuous.
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, confirmation_token, recovery_token,
   created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000',
        '60606060-0000-0000-0000-00000000000a', 'authenticated', 'authenticated',
        'anon-fixture@test.local', 'x', now(), '', '', now(), now());
insert into public.categories (user_id, bucket, name)
values ('60606060-0000-0000-0000-00000000000a', 'essential', 'fixture');
insert into public.months
  (user_id, year, month, net_income_cents, essential_pct, fun_pct, invest_pct)
values ('60606060-0000-0000-0000-00000000000a', 2026, 1, 1000, 50, 30, 20);
insert into public.entries
  (user_id, month_id, category_id, amount_cents, paid_on)
select '60606060-0000-0000-0000-00000000000a', m.id, c.id, 100, '2026-01-01'
from public.months m, public.categories c
where m.user_id = '60606060-0000-0000-0000-00000000000a'
  and c.user_id = '60606060-0000-0000-0000-00000000000a';

select is_empty(
  $$ select c.relname::text from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
     order by 1 $$,
  'every table in public has RLS enabled');

set role anon;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

-- Every public table returns zero rows to anon. Raises (naming the table)
-- on the first leak, so lives_ok fails with a useful message.
select lives_ok(
  $test$
  do $$
  declare r record; v_count bigint;
  begin
    for r in select c.relname from pg_class c
             join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relkind = 'r' loop
      execute format('select count(*) from public.%I', r.relname) into v_count;
      if v_count > 0 then
        raise exception 'anon can read rows from %', r.relname;
      end if;
    end loop;
  end $$;
  $test$,
  'anon reads zero rows from every public table');

-- Every public table: update and delete affect zero rows (RLS hides rows
-- even where grants exist). user_id = user_id is a valid no-op on all of
-- our tables since they all carry user_id.
select lives_ok(
  $test$
  do $$
  declare r record; v_n bigint;
  begin
    for r in select c.relname from pg_class c
             join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relkind = 'r' loop
      execute format('update public.%I set user_id = user_id', r.relname);
      get diagnostics v_n = row_count;
      if v_n > 0 then
        raise exception 'anon update affected rows in %', r.relname;
      end if;
      execute format('delete from public.%I', r.relname);
      get diagnostics v_n = row_count;
      if v_n > 0 then
        raise exception 'anon delete affected rows in %', r.relname;
      end if;
    end loop;
  end $$;
  $test$,
  'anon update/delete affect zero rows in every public table');

-- Inserts are denied at the grant level. One representative per policy
-- shape: FOR ALL (months), select+update only (profiles), select-only
-- (month_summaries).
select throws_ok(
  $$ insert into months
       (user_id, year, month, net_income_cents, essential_pct, fun_pct, invest_pct)
     values ('60606060-0000-0000-0000-00000000000a', 2026, 3, 1, 50, 30, 20) $$,
  '42501', null, 'anon cannot insert into a FOR ALL table');
select throws_ok(
  $$ insert into profiles (user_id)
     values ('60606060-0000-0000-0000-00000000000a') $$,
  '42501', null, 'anon cannot insert into a select+update table');
select throws_ok(
  $$ insert into month_summaries
       (month_id, user_id, net_income_cents,
        essential_budget_cents, essential_spent_cents, essential_rest_cents,
        fun_budget_cents, fun_spent_cents, fun_rest_cents,
        invest_target_cents, invested_cents)
     values ('60606060-0000-0000-0000-00000000000a'::uuid,
             '60606060-0000-0000-0000-00000000000a',
             1, 1, 1, 0, 1, 1, 0, 1, 1) $$,
  '42501', null, 'anon cannot insert into a select-only table');

reset role;

select * from finish();
rollback;
