-- reopen_month: a guarded closed -> open transition for when a month was
-- closed prematurely. Deletes the month_summaries row (a fresh one is
-- written on the next close_month) and clears closed_at/invested_cents.
-- The months guard allows exactly this shape only while the
-- app.reopen_month transaction-local flag is set by the RPC.

create or replace function public.guard_month_closed()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    -- Cascaded deletes (auth.users -> ...) fire this trigger at depth > 1;
    -- the block applies only to direct client deletes.
    if pg_trigger_depth() = 1 and old.status = 'closed' then
      raise exception 'closed months cannot be deleted';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'open' then
      raise exception 'new months must be open; use close_month() to close';
    end if;
    return new;
  end if;
  if old.status = 'closed' then
    -- reopen_month() sets app.reopen_month and performs exactly this
    -- transition: closed -> open with closed_at/invested_cents cleared.
    -- Every other update to a closed month is rejected.
    if new.status = 'open'
       and new.closed_at is null
       and new.invested_cents is null
       and coalesce(current_setting('app.reopen_month', true), '') = 'on' then
      return new;
    end if;
    raise exception 'closed months are read-only';
  end if;
  if new.status = 'closed'
     and coalesce(current_setting('app.close_month', true), '') <> 'on' then
    raise exception 'use close_month() to close a month';
  end if;
  return new;
end;
$$;

create or replace function public.reopen_month(
  month_id uuid
)
returns public.months
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_month public.months;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select m.* into v_month
  from public.months m
  where m.id = month_id and m.user_id = v_uid
  for update;

  if not found then
    raise exception 'month not found';
  end if;
  if v_month.status <> 'closed' then
    raise exception 'month is not closed';
  end if;

  -- The summary is derived data; a fresh row is written on the next close.
  delete from public.month_summaries ms
  where ms.user_id = v_uid and ms.month_id = month_id;

  perform set_config('app.reopen_month', 'on', true);

  update public.months m
  set status = 'open',
      closed_at = null,
      invested_cents = null
  where m.id = month_id
  returning * into v_month;

  perform set_config('app.reopen_month', 'off', true);

  return v_month;
end;
$$;

revoke all on function public.reopen_month(uuid) from public, anon, authenticated;
grant execute on function public.reopen_month(uuid) to authenticated;
