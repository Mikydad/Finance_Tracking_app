-- Finance goals: "spend at most 5,000 this week", "earn 100,000 this month",
-- "save 20,000 this month", optionally for one category (spending only).
-- A goal repeats every week or month; progress is computed on the phone from
-- the transactions, in the calendar the user chose (Gregorian or Ethiopian).
-- Synced like every other table: client-generated ids, soft delete,
-- server_version stamping, RLS per user.

create table public.finance_goals (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind            text not null check (kind in ('spend_max', 'earn_min', 'save_min')),
  period          text not null check (period in ('week', 'month')),
  amount          bigint not null check (amount > 0),                 -- santim
  category_id     uuid references public.categories (id) on delete set null,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  server_version  bigint not null default 0,
  constraint finance_goals_category_only_for_spending check (category_id is null or kind = 'spend_max')
);

create index finance_goals_user_idx on public.finance_goals (user_id);
create index finance_goals_server_version_idx on public.finance_goals (server_version);

create trigger finance_goals_stamp before insert or update on public.finance_goals
  for each row execute function public.stamp_sync_columns();

alter table public.finance_goals enable row level security;
create policy finance_goals_all on public.finance_goals
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke delete on public.finance_goals from authenticated;
revoke all on public.finance_goals from anon;

-- Sync: goals are pulled and pushed like the other tables.
create or replace function public.sync_writable_columns(p_table text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case p_table
    when 'profiles' then array['display_name', 'phone', 'default_currency', 'timezone']
    when 'financial_accounts' then array['id', 'owner_type', 'owner_id', 'name', 'institution',
      'masked_number', 'currency', 'is_active', 'deleted_at']
    when 'transaction_sources' then array['id', 'user_id', 'type', 'provider', 'identifier',
      'metadata', 'is_active', 'deleted_at']
    when 'categories' then array['id', 'user_id', 'parent_id', 'name', 'icon', 'color', 'kind',
      'sort_order', 'is_archived', 'deleted_at']
    when 'transactions' then array['id', 'account_id', 'type', 'amount', 'fee', 'currency', 'occurred_at',
      'merchant_name', 'counterparty_name', 'counterparty_kind', 'counterparty_account', 'category_id', 'category_source', 'category_confidence',
      'source_id', 'description', 'notes', 'reference_id', 'status', 'review_reason',
      'confidence_score', 'duplicate_of', 'deleted_at']
    when 'categorization_rules' then array['id', 'user_id', 'match_field', 'match_value',
      'category_id', 'source', 'hit_count', 'deleted_at']
    when 'finance_goals' then array['id', 'user_id', 'kind', 'period', 'amount', 'category_id',
      'is_active', 'deleted_at']
  end;
$$;

create or replace function public.sync_pull(p_since bigint default 0, p_limit int default 500)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 500), 1), 2000);
  v_changes jsonb;
  v_cursor bigint;
  v_has_more boolean;
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  with changes as (
    select 'profiles' as tbl, t.server_version as v, to_jsonb(t) as row
      from public.profiles t where t.server_version > p_since
    union all
    select 'financial_accounts', t.server_version, to_jsonb(t)
      from public.financial_accounts t where t.server_version > p_since
    union all
    select 'transaction_sources', t.server_version, to_jsonb(t)
      from public.transaction_sources t where t.server_version > p_since
    union all
    select 'categories', t.server_version, to_jsonb(t)
      from public.categories t where t.server_version > p_since
    union all
    select 'transactions', t.server_version, to_jsonb(t)
      from public.transactions t where t.server_version > p_since
    union all
    select 'categorization_rules', t.server_version, to_jsonb(t)
      from public.categorization_rules t where t.server_version > p_since
    union all
    select 'finance_goals', t.server_version, to_jsonb(t)
      from public.finance_goals t where t.server_version > p_since
  ),
  page as (
    select * from changes order by v limit v_limit + 1
  ),
  numbered as (
    select *, row_number() over (order by v) as n from page
  )
  select
    coalesce(jsonb_agg(jsonb_build_object('table', tbl, 'row', row) order by v) filter (where n <= v_limit), '[]'::jsonb),
    coalesce(max(v) filter (where n <= v_limit), p_since),
    count(*) > v_limit
  into v_changes, v_cursor, v_has_more
  from numbered;

  return jsonb_build_object('changes', v_changes, 'cursor', v_cursor, 'has_more', v_has_more);
end;
$$;
