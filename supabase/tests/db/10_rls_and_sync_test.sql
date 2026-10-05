-- Schema, RLS and sync tests. Run by scripts/test-db.sh after the stub and
-- all migrations. Any failed assertion aborts with a non-zero exit.

\set ON_ERROR_STOP on

-- Two users. The sign-up trigger gives each a profile, Cash account and manual source.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'alice@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'bob@example.com');

create function pg_temp.as_user(p_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_id::text, false);
  execute 'set role authenticated';
end;
$$;

create function pg_temp.as_admin() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', false);
end;
$$;

-- ---------------------------------------------------------------------------
\echo 'sign-up creates profile, Cash account and manual source'
do $$
begin
  assert (select count(*) from public.profiles) = 2, 'expected 2 profiles';
  assert (select count(*) from public.financial_accounts where institution = 'cash') = 2, 'expected 2 cash accounts';
  assert (select count(*) from public.transaction_sources where type = 'manual') = 2, 'expected 2 manual sources';
  assert (select count(*) from public.categories where user_id is null) = 21, 'expected 21 default categories';
end;
$$;

-- ---------------------------------------------------------------------------
\echo 'alice can write and read her own transaction'
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');

insert into public.transactions (id, account_id, type, amount, occurred_at, counterparty_name, category_id)
select '10000000-0000-0000-0000-000000000001', a.id, 'expense', 250000, now(), 'Abc Shop',
       (select id from public.categories where key = 'shopping')
from public.financial_accounts a;

do $$
begin
  assert (select count(*) from public.transactions) = 1, 'alice should see her transaction';
  assert (select created_by from public.transactions) = '00000000-0000-0000-0000-00000000000a',
    'created_by should default to the caller';
  assert (select server_version from public.transactions) > 0, 'server_version should be stamped';
  assert (select count(*) from public.financial_accounts) = 1, 'alice sees only her account';
  assert (select count(*) from public.profiles) = 1, 'alice sees only her profile';
  assert (select count(*) from public.categories) = 21, 'alice sees the defaults';
end;
$$;

-- ---------------------------------------------------------------------------
\echo 'bob cannot see or touch alice''s data'
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$
begin
  assert (select count(*) from public.transactions) = 0, 'bob must not see alice''s transaction';
  -- RLS hides the row, so this updates nothing.
  update public.transactions set amount = 1 where id = '10000000-0000-0000-0000-000000000001';
end;
$$;

select pg_temp.as_admin();
do $$
begin
  assert (select amount from public.transactions where id = '10000000-0000-0000-0000-000000000001') = 250000,
    'bob''s update must not reach alice''s row';
end;
$$;

\echo 'bob cannot insert into alice''s account'
select pg_temp.as_admin();
create temp table alice_account as
  select id from public.financial_accounts where owner_id = '00000000-0000-0000-0000-00000000000a';
grant select on alice_account to authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$
begin
  begin
    insert into public.transactions (account_id, type, amount, occurred_at)
    values ((select id from alice_account), 'expense', 100, now());
    raise exception 'insert into another user''s account should fail';
  exception when insufficient_privilege then
    null; -- expected: RLS with check
  end;
end;
$$;

\echo 'bob cannot use another user''s category'
select pg_temp.as_admin();
insert into public.categories (id, user_id, name)
values ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Alice private');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$
begin
  begin
    insert into public.transactions (account_id, type, amount, occurred_at, category_id)
    select a.id, 'expense', 100, now(), '20000000-0000-0000-0000-000000000001'
    from public.financial_accounts a;
    raise exception 'using another user''s category should fail';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo 'clients cannot read server-only tables or token hashes'
do $$
begin
  begin
    perform 1 from public.raw_messages;
    raise exception 'raw_messages should not be readable';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.merchant_category_cache;
    raise exception 'merchant_category_cache should not be readable';
  exception when insufficient_privilege then null;
  end;
  begin
    perform token_hash from public.ingestion_tokens;
    raise exception 'token_hash should not be readable';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.transactions;
    raise exception 'hard delete should not be allowed';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
\echo 'ingestion tokens: created once, hash stored, owner can list'
do $$
declare
  v_token text;
begin
  select token into v_token from public.create_ingestion_token('Miko iPhone');
  assert v_token like 'fin\_%', 'token should have the fin_ prefix';
  assert length(v_token) = 68, 'token should be fin_ + 64 hex chars';
  assert (select count(*) from public.ingestion_tokens) = 1, 'bob should see his token';
end;
$$;
select pg_temp.as_admin();
do $$
begin
  assert (select token_hash from public.ingestion_tokens limit 1) ~ '^[0-9a-f]{64}$', 'hash should be sha256 hex';
end;
$$;

-- ---------------------------------------------------------------------------
\echo 'sync_push: upsert, update, delete, and rejection of foreign rows'
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$
declare
  v_account uuid := (select id from public.financial_accounts);
  v_result jsonb;
begin
  v_result := public.sync_push(jsonb_build_array(
    jsonb_build_object('table', 'transactions', 'op', 'upsert', 'row', jsonb_build_object(
      'id', '30000000-0000-0000-0000-000000000001', 'account_id', v_account,
      'type', 'expense', 'amount', 50000, 'occurred_at', now(), 'counterparty_name', 'Meron Cafe')),
    jsonb_build_object('table', 'transactions', 'op', 'upsert', 'row', jsonb_build_object(
      'id', '30000000-0000-0000-0000-000000000001', 'notes', 'coffee with Abebe')),
    jsonb_build_object('table', 'transactions', 'op', 'upsert', 'row', jsonb_build_object(
      'id', '10000000-0000-0000-0000-000000000001', 'amount', 1)),
    jsonb_build_object('table', 'raw_messages', 'op', 'upsert', 'row', jsonb_build_object('id', gen_random_uuid())),
    jsonb_build_object('table', 'profiles', 'op', 'upsert', 'row', jsonb_build_object('display_name', 'Bob B'))
  ));

  assert (v_result -> 'results' -> 0 ->> 'ok')::boolean, 'insert should succeed: ' || (v_result -> 'results' -> 0)::text;
  assert (v_result -> 'results' -> 1 ->> 'ok')::boolean, 'partial update should succeed: ' || (v_result -> 'results' -> 1)::text;
  assert not (v_result -> 'results' -> 2 ->> 'ok')::boolean, 'updating alice''s row must fail';
  assert not (v_result -> 'results' -> 3 ->> 'ok')::boolean, 'raw_messages must not be syncable';
  assert (v_result -> 'results' -> 4 ->> 'ok')::boolean, 'profile update should succeed: ' || (v_result -> 'results' -> 4)::text;

  assert (select amount from public.transactions where id = '30000000-0000-0000-0000-000000000001') = 50000,
    'partial update must keep other columns';
  assert (select notes from public.transactions where id = '30000000-0000-0000-0000-000000000001') = 'coffee with Abebe',
    'partial update must set notes';
  assert (select display_name from public.profiles) = 'Bob B', 'profile should be updated';

  v_result := public.sync_push(jsonb_build_array(
    jsonb_build_object('table', 'transactions', 'op', 'delete', 'row', jsonb_build_object(
      'id', '30000000-0000-0000-0000-000000000001'))));
  assert (v_result -> 'results' -> 0 ->> 'ok')::boolean, 'delete should succeed';
  assert (select deleted_at from public.transactions where id = '30000000-0000-0000-0000-000000000001') is not null,
    'delete should set deleted_at';
end;
$$;

-- ---------------------------------------------------------------------------
\echo 'sync_pull: paging, cursor and tombstones'
do $$
declare
  v_page jsonb;
  v_cursor bigint := 0;
  v_seen int := 0;
  v_pages int := 0;
  v_tombstone boolean := false;
  v_change jsonb;
begin
  loop
    v_page := public.sync_pull(v_cursor, 5);
    v_pages := v_pages + 1;
    for v_change in select value from jsonb_array_elements(v_page -> 'changes') loop
      v_seen := v_seen + 1;
      if v_change ->> 'table' = 'transactions' and v_change -> 'row' ->> 'deleted_at' is not null then
        v_tombstone := true;
      end if;
      assert v_change ->> 'table' <> 'transactions'
        or v_change -> 'row' ->> 'id' <> '10000000-0000-0000-0000-000000000001',
        'bob must never pull alice''s transaction';
    end loop;
    assert (v_page ->> 'cursor')::bigint >= v_cursor, 'cursor must not go backwards';
    v_cursor := (v_page ->> 'cursor')::bigint;
    exit when not (v_page ->> 'has_more')::boolean;
  end loop;

  -- bob: 1 profile + 1 account + 1 source + 21 categories + 1 transaction
  assert v_seen = 25, 'expected 25 visible rows, got ' || v_seen;
  assert v_pages = 5, 'expected 5 pages of 5, got ' || v_pages;
  assert v_tombstone, 'deleted transaction should come through as a tombstone';

  v_page := public.sync_pull(v_cursor, 5);
  assert jsonb_array_length(v_page -> 'changes') = 0, 'nothing new after the last cursor';
  assert (v_page ->> 'cursor')::bigint = v_cursor, 'cursor stays put when nothing changed';
end;
$$;

\echo 'anonymous callers get nothing'
select pg_temp.as_admin();
set role anon;
do $$
begin
  begin
    perform 1 from public.transactions;
    raise exception 'anon should not read transactions';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.sync_pull(0, 10);
    raise exception 'anon should not call sync_pull';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

\echo 'raw message purge'
insert into public.raw_messages (user_id, body_ciphertext, received_at, expires_at)
values ('00000000-0000-0000-0000-00000000000a', 'x', now(), now() - interval '1 day'),
       ('00000000-0000-0000-0000-00000000000a', 'y', now(), now() + interval '1 day');
do $$
begin
  assert public.purge_expired_raw_messages() = 1, 'one expired message should be purged';
  assert (select count(*) from public.raw_messages) = 1, 'unexpired message should remain';
end;
$$;

\echo 'ALL DB TESTS PASSED'
