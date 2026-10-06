-- Recurring templates get the same optional-category treatment as entries:
-- a template may carry a bucket directly ("óculos em 6x" into Essencial
-- without inventing a category). When a category IS set it stays the
-- source of truth and a trigger syncs bucket from it.

alter table public.recurring_templates
  alter column category_id drop not null,
  add column bucket public.bucket;

update public.recurring_templates t set bucket = c.bucket
from public.categories c
where t.category_id = c.id;

create or replace function public.sync_template_bucket()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_bucket public.bucket;
begin
  if new.category_id is not null then
    select c.bucket into v_bucket
    from public.categories c
    where c.user_id = new.user_id and c.id = new.category_id;
    if not found then
      raise exception 'category not found' using errcode = '23503';
    end if;
    new.bucket := v_bucket;
  end if;
  return new;
end;
$$;

create trigger recurring_templates_sync_bucket
  before insert or update on public.recurring_templates
  for each row execute function public.sync_template_bucket();

-- Every template must land in a bucket; with a category the trigger fills
-- it before this check runs.
alter table public.recurring_templates
  add constraint recurring_templates_bucket_req check (bucket is not null);

-- open_month: same generation as before plus bucket on generated entries
-- and a left join so category-less templates still generate.
create or replace function public.open_month(
  year smallint,
  month smallint,
  net_income_cents bigint
)
returns public.months
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_month public.months;
  v_settings public.budget_settings;
  v_last_day int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if month is null or month < 1 or month > 12 then
    raise exception 'month must be between 1 and 12';
  end if;
  if net_income_cents is null or net_income_cents < 0 then
    raise exception 'net_income_cents must be >= 0';
  end if;

  select bs.* into v_settings
  from public.budget_settings bs
  where bs.user_id = v_uid;
  if not found then
    raise exception 'budget_settings not found for current user';
  end if;

  -- ON CONFLICT ON CONSTRAINT is used (rather than a column list) because
  -- the parameter names year/month would shadow the arbiter columns under
  -- #variable_conflict use_variable.
  insert into public.months
    (user_id, year, month, net_income_cents, essential_pct, fun_pct, invest_pct)
  values
    (v_uid, year, month, net_income_cents,
     v_settings.essential_pct, v_settings.fun_pct, v_settings.invest_pct)
  on conflict on constraint months_user_id_year_month_key do nothing
  returning * into v_month;

  if v_month.id is null then
    -- The month already existed: return it unchanged (net_income_cents is
    -- ignored) and generate nothing. Recurring generation only happens on
    -- creation so user edits/deletions are never resurrected.
    select m.* into v_month
    from public.months m
    where m.user_id = v_uid and m.year = year and m.month = month;
    if v_month.id is null then
      raise exception 'failed to create month';
    end if;
    if v_month.status = 'closed' then
      raise exception 'month %-% is already closed', year, month;
    end if;
    return v_month;
  end if;

  v_last_day := extract(day from
    (date_trunc('month', make_date(year::int, month::int, 1)) + interval '1 month - 1 day'))::int;

  insert into public.entries
    (user_id, month_id, category_id, bucket, amount_cents, paid_on, note,
     recurring_template_id, installment_index)
  select
    v_uid,
    v_month.id,
    t.category_id,
    t.bucket,
    t.amount_cents,
    make_date(year::int, month::int, least(t.day_of_month, v_last_day)),
    t.label,
    t.id,
    case
      when t.installments_total is null then null
      else (year::int * 12 + month::int)
           - (t.first_year::int * 12 + t.first_month::int) + 1
    end
  from public.recurring_templates t
  left join public.categories c
    on c.user_id = t.user_id and c.id = t.category_id
  where t.user_id = v_uid and t.active
    and (t.category_id is null or not c.archived)
    and (
      t.installments_total is null
      or (year::int * 12 + month::int)
         - (t.first_year::int * 12 + t.first_month::int) + 1
         between 1 and t.installments_total
    )
  on conflict (month_id, recurring_template_id)
    where recurring_template_id is not null
    do nothing;

  return v_month;
end;
$$;

-- create_recurring_template gains p_bucket for category-less templates.
-- The old signature is replaced outright (the app is the only caller).
drop function public.create_recurring_template(uuid, text, bigint, smallint, smallint, smallint, smallint);

create function public.create_recurring_template(
  p_label text,
  p_amount_cents bigint,
  p_day_of_month smallint,
  p_category_id uuid default null,
  p_bucket public.bucket default null,
  p_installments_total smallint default null,
  p_first_year smallint default null,
  p_first_month smallint default null
)
returns public.recurring_templates
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_t public.recurring_templates;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_label is null or btrim(p_label) = '' then
    raise exception 'label must not be empty';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'amount_cents must be > 0';
  end if;
  if p_day_of_month is null or p_day_of_month < 1 or p_day_of_month > 31 then
    raise exception 'day_of_month must be between 1 and 31';
  end if;
  if p_installments_total is not null then
    if p_installments_total < 2 then
      raise exception 'installments_total must be >= 2';
    end if;
    if p_first_year is null or p_first_month is null then
      p_first_year := extract(year from current_date)::smallint;
      p_first_month := extract(month from current_date)::smallint;
    end if;
  else
    p_first_year := null;
    p_first_month := null;
  end if;

  if p_category_id is not null then
    -- The composite FK would enforce ownership; this check exists so
    -- archived and foreign categories fail with a readable error instead
    -- of a 23503.
    if not exists (
      select 1 from public.categories c
      where c.user_id = v_uid and c.id = p_category_id and not c.archived
    ) then
      raise exception 'category not found or archived';
    end if;
  elsif p_bucket is null then
    raise exception 'bucket is required when category is not set';
  end if;

  insert into public.recurring_templates
    (user_id, category_id, bucket, label, amount_cents, day_of_month,
     installments_total, first_year, first_month)
  values
    (v_uid, p_category_id, p_bucket, btrim(p_label), p_amount_cents,
     p_day_of_month, p_installments_total, p_first_year, p_first_month)
  returning * into v_t;

  insert into public.entries
    (user_id, month_id, category_id, bucket, amount_cents, paid_on, note,
     recurring_template_id, installment_index)
  select
    v_uid,
    m.id,
    v_t.category_id,
    v_t.bucket,
    v_t.amount_cents,
    make_date(m.year::int, m.month::int,
      least(v_t.day_of_month::int,
        extract(day from (date_trunc('month', make_date(m.year::int, m.month::int, 1))
          + interval '1 month - 1 day'))::int)),
    v_t.label,
    v_t.id,
    case
      when v_t.installments_total is null then null
      else (m.year::int * 12 + m.month::int)
           - (v_t.first_year::int * 12 + v_t.first_month::int) + 1
    end
  -- Bounded plans: any open month inside the window (covers backfill when a
  -- past month was opened late). Unbounded templates start at creation time,
  -- so only open months from the creation month onward get an entry — a
  -- reopened past month must not gain a retroactive entry.
  from public.months m
  where m.user_id = v_uid
    and m.status = 'open'
    and (
      case
        when v_t.installments_total is null
          then (m.year::int * 12 + m.month::int)
               >= (extract(year from current_date)::int * 12
                   + extract(month from current_date)::int)
        else (m.year::int * 12 + m.month::int)
             - (v_t.first_year::int * 12 + v_t.first_month::int) + 1
             between 1 and v_t.installments_total
      end
    )
  on conflict (month_id, recurring_template_id)
    where recurring_template_id is not null
    do nothing;

  return v_t;
end;
$$;

revoke all on function public.create_recurring_template(text, bigint, smallint, uuid, public.bucket, smallint, smallint, smallint)
  from public, anon, authenticated;
grant execute on function public.create_recurring_template(text, bigint, smallint, uuid, public.bucket, smallint, smallint, smallint)
  to authenticated;
