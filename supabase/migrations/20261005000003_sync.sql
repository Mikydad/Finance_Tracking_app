-- Sync API for the phone (Isar outbox <-> Postgres).
--
-- Pull: sync_pull(since) returns every row the caller can see whose
--   server_version is greater than `since`, oldest first, including
--   soft-deleted rows (tombstones). The client keeps the returned cursor.
-- Push: sync_push(ops) applies a batch of upserts/deletes from the outbox.
--   Ids are generated on the device, so replaying a batch is safe.
--
-- Both run as the caller (security invoker), so RLS decides what is visible
-- and writable.
--
-- Known limitation: server_version comes from a sequence, so a write that
-- commits after a later-numbered one can be skipped by a client whose cursor
-- already passed it. Upserts are idempotent, so the fix (pulling with a small
-- overlap, or a commit-ordered cursor) can be added without schema changes.

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

-- Columns the client may write, per table. Anything else (server_version,
-- timestamps, created_by, category keys) is server-owned.
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
  end;
$$;

-- ops: [{ "table": "transactions", "op": "upsert" | "delete", "row": {...} }]
-- Returns { results: [{ table, id, ok, error? }] } in the same order.
create or replace function public.sync_push(p_ops jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_op jsonb;
  v_table text;
  v_kind text;
  v_row jsonb;
  v_id uuid;
  v_cols text[];
  v_list text;
  v_set text;
  v_count int;
  v_results jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if jsonb_typeof(p_ops) <> 'array' then
    raise exception 'ops must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_ops) > 500 then
    raise exception 'too many ops in one batch (max 500)' using errcode = '22023';
  end if;

  for v_op in select value from jsonb_array_elements(p_ops)
  loop
    v_table := v_op ->> 'table';
    v_kind := coalesce(v_op ->> 'op', 'upsert');
    v_row := coalesce(v_op -> 'row', '{}'::jsonb);
    v_id := null;

    begin
      v_cols := public.sync_writable_columns(v_table);
      if v_cols is null then
        raise exception 'table % cannot be synced', v_table using errcode = '22023';
      end if;

      if v_table = 'profiles' then
        -- A profile always exists (created at sign-up); only update it.
        v_id := auth.uid();
        select string_agg(format('%I = r.%I', c, c), ', ')
          into v_set
          from unnest(v_cols) c where v_row ? c;
        if v_set is not null then
          execute format(
            'update public.profiles p set %s from jsonb_populate_record(null::public.profiles, $1) r where p.id = $2',
            v_set) using v_row, v_id;
        end if;

      else
        v_id := (v_row ->> 'id')::uuid;
        if v_id is null then
          raise exception 'row.id is required' using errcode = '22023';
        end if;

        if v_kind = 'delete' then
          execute format('update public.%I set deleted_at = now() where id = $1 and deleted_at is null', v_table)
            using v_id;
        elsif v_kind = 'upsert' then
          -- Update first so a partial row (only changed fields) works; the
          -- insert path needs a complete row. Not INSERT ... ON CONFLICT,
          -- because RLS would check the partial row as if it were inserted.
          select string_agg(format('%I', c), ', '),
                 string_agg(format('%I = r.%I', c, c), ', ') filter (where c <> 'id')
            into v_list, v_set
            from unnest(v_cols) c where v_row ? c;

          execute format(
            'update public.%I t set %s from jsonb_populate_record(null::public.%I, $1) r where t.id = $2',
            v_table, coalesce(v_set, 'id = t.id'), v_table)
            using v_row, v_id;
          get diagnostics v_count = row_count;

          if v_count = 0 then
            execute format(
              'insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1)',
              v_table, v_list, v_list, v_table)
              using v_row;
          end if;
        else
          raise exception 'unknown op %', v_kind using errcode = '22023';
        end if;
      end if;

      get diagnostics v_count = row_count;
      if v_count = 0 and v_kind <> 'delete' then
        raise exception 'row % not found or not writable', v_id using errcode = '42501';
      end if;
      v_results := v_results || jsonb_build_object('table', v_table, 'id', v_id, 'ok', true);
    exception when others then
      v_results := v_results || jsonb_build_object(
        'table', v_table, 'id', v_id, 'ok', false, 'error', sqlerrm, 'code', sqlstate);
    end;
  end loop;

  return jsonb_build_object('results', v_results);
end;
$$;

revoke execute on function public.sync_pull(bigint, int) from public, anon;
revoke execute on function public.sync_push(jsonb) from public, anon;
grant execute on function public.sync_pull(bigint, int) to authenticated;
grant execute on function public.sync_push(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Raw message retention
-- ---------------------------------------------------------------------------

create or replace function public.purge_expired_raw_messages()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted int;
begin
  delete from public.raw_messages where expires_at < now();
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke execute on function public.purge_expired_raw_messages() from public, anon, authenticated;

-- Schedule the purge daily where pg_cron is available (it is on Supabase).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('purge-expired-raw-messages', '15 3 * * *',
      'select public.purge_expired_raw_messages()');
  end if;
end;
$$;

-- Let the app subscribe to "something changed" nudges for its transactions
-- (Realtime still applies RLS per subscriber).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.transactions;
  end if;
end;
$$;
