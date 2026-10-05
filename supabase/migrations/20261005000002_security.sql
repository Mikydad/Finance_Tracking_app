-- Row Level Security: a user only reaches rows that belong to them, and
-- transactions are reached through the financial accounts they own. That
-- account-based check is where business/team access will plug in later.

-- Owner check used by transaction policies. security definer so the policy
-- can look at financial_accounts without recursing through its own RLS.
create or replace function public.owns_account(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.financial_accounts a
    where a.id = p_account_id
      and a.owner_type = 'user'
      and a.owner_id = auth.uid()
  );
$$;

alter table public.profiles               enable row level security;
alter table public.financial_accounts     enable row level security;
alter table public.transaction_sources    enable row level security;
alter table public.categories             enable row level security;
alter table public.transactions           enable row level security;
alter table public.categorization_rules   enable row level security;
alter table public.merchant_category_cache enable row level security;
alter table public.raw_messages           enable row level security;
alter table public.ingestion_tokens       enable row level security;

-- Profiles
create policy profiles_select on public.profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_update on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Financial accounts
create policy financial_accounts_select on public.financial_accounts
  for select to authenticated using (owner_type = 'user' and owner_id = auth.uid());
create policy financial_accounts_insert on public.financial_accounts
  for insert to authenticated with check (owner_type = 'user' and owner_id = auth.uid());
create policy financial_accounts_update on public.financial_accounts
  for update to authenticated
  using (owner_type = 'user' and owner_id = auth.uid())
  with check (owner_type = 'user' and owner_id = auth.uid());

-- Transaction sources
create policy transaction_sources_all on public.transaction_sources
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Categories: defaults are readable by everyone signed in; custom ones are private.
create policy categories_select on public.categories
  for select to authenticated using (user_id is null or user_id = auth.uid());
create policy categories_insert on public.categories
  for insert to authenticated with check (user_id = auth.uid());
create policy categories_update on public.categories
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Transactions
create policy transactions_select on public.transactions
  for select to authenticated using (public.owns_account(account_id));
create policy transactions_insert on public.transactions
  for insert to authenticated with check (public.owns_account(account_id));
create policy transactions_update on public.transactions
  for update to authenticated
  using (public.owns_account(account_id))
  with check (public.owns_account(account_id));

-- Categorization rules
create policy categorization_rules_all on public.categorization_rules
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Ingestion tokens: users can list and revoke their own, but never read the
-- hash. Creation goes through create_ingestion_token().
create policy ingestion_tokens_select on public.ingestion_tokens
  for select to authenticated using (user_id = auth.uid());
create policy ingestion_tokens_update on public.ingestion_tokens
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.ingestion_tokens from anon, authenticated;
grant select (id, name, last_used_at, revoked_at, created_at) on public.ingestion_tokens to authenticated;
grant update (revoked_at) on public.ingestion_tokens to authenticated;

-- merchant_category_cache and raw_messages have RLS on and no policies:
-- only the service role (Edge Functions) can touch them.
revoke all on public.merchant_category_cache from anon, authenticated;
revoke all on public.raw_messages from anon, authenticated;

-- Hard deletes are not part of sync (rows are soft-deleted via deleted_at),
-- and nothing is readable without signing in.
revoke delete on public.profiles, public.financial_accounts, public.transaction_sources,
  public.categories, public.transactions, public.categorization_rules from authenticated;
revoke all on public.profiles, public.financial_accounts, public.transaction_sources,
  public.categories, public.transactions, public.categorization_rules from anon;

-- Clients cannot forge sync bookkeeping: stamp_sync_columns() overwrites
-- server_version, created_at and updated_at on every write.

-- ---------------------------------------------------------------------------
-- Reference checks: a transaction may only point at a category, source and
-- duplicate that its account owner can see. RLS on the referenced tables does
-- not apply to foreign keys, so this closes that gap.
-- ---------------------------------------------------------------------------

create or replace function public.check_transaction_refs()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  select a.owner_id into v_owner
  from public.financial_accounts a
  where a.id = new.account_id and a.owner_type = 'user';

  if new.category_id is not null and not exists (
    select 1 from public.categories c
    where c.id = new.category_id and (c.user_id is null or c.user_id = v_owner)
  ) then
    raise exception 'category % is not available to this account', new.category_id
      using errcode = '42501';
  end if;

  if new.source_id is not null and not exists (
    select 1 from public.transaction_sources s
    where s.id = new.source_id and s.user_id = v_owner
  ) then
    raise exception 'source % is not available to this account', new.source_id
      using errcode = '42501';
  end if;

  if new.duplicate_of is not null and not exists (
    select 1 from public.transactions t
    join public.financial_accounts a on a.id = t.account_id
    where t.id = new.duplicate_of and a.owner_type = 'user' and a.owner_id = v_owner
  ) then
    raise exception 'duplicate_of % is not available to this account', new.duplicate_of
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger transactions_check_refs before insert or update on public.transactions
  for each row execute function public.check_transaction_refs();

create or replace function public.check_rule_refs()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.categories c
    where c.id = new.category_id and (c.user_id is null or c.user_id = new.user_id)
  ) then
    raise exception 'category % is not available to this user', new.category_id
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger categorization_rules_check_refs before insert or update on public.categorization_rules
  for each row execute function public.check_rule_refs();

-- ---------------------------------------------------------------------------
-- New user setup: profile, a Cash account and a manual source.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)));

  insert into public.financial_accounts (owner_type, owner_id, name, institution)
  values ('user', new.id, 'Cash', 'cash');

  insert into public.transaction_sources (user_id, type, provider)
  values (new.id, 'manual', 'app');

  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Ingestion tokens for the iPhone Shortcut. Returns the plain token once.
-- ---------------------------------------------------------------------------

create or replace function public.create_ingestion_token(p_name text)
returns table (id uuid, token text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := 'fin_' || encode(extensions.gen_random_bytes(32), 'hex');
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  insert into public.ingestion_tokens (user_id, name, token_hash)
  values (auth.uid(), coalesce(nullif(trim(p_name), ''), 'iPhone Shortcut'),
          encode(extensions.digest(v_token, 'sha256'), 'hex'))
  returning ingestion_tokens.id into v_id;

  return query select v_id, v_token;
end;
$$;

revoke execute on function public.create_ingestion_token(text) from public, anon;
grant execute on function public.create_ingestion_token(text) to authenticated;
