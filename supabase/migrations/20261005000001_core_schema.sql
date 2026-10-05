-- Core schema for the Transaction engine.
--
-- Owner -> FinancialAccount -> Transaction. Every synced table carries
-- server_version (stamped from one global sequence) and deleted_at (soft
-- delete), which is what the phone's pull-based sync reads.
-- Money is stored as bigint minor units (santim): 2,500.00 ETB = 250000.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Sync plumbing
-- ---------------------------------------------------------------------------

create sequence public.sync_version_seq;

create or replace function public.stamp_sync_columns()
returns trigger
language plpgsql
as $$
begin
  new.server_version := nextval('public.sync_version_seq');
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.created_at := coalesce(new.created_at, now());
  else
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Profiles (the PRD's User). One row per auth.users row.
-- ---------------------------------------------------------------------------

create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  display_name      text,
  phone             text,
  default_currency  char(3) not null default 'ETB',
  timezone          text not null default 'Africa/Addis_Ababa',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  server_version    bigint not null default 0
);

-- ---------------------------------------------------------------------------
-- Financial accounts: what transactions hang off. owner_type is only 'user'
-- in V1; 'business' is reserved for the team feature.
-- ---------------------------------------------------------------------------

create table public.financial_accounts (
  id              uuid primary key default gen_random_uuid(),
  owner_type      text not null default 'user' check (owner_type in ('user', 'business')),
  owner_id        uuid not null,
  name            text not null,
  institution     text not null default 'other'
                  check (institution in ('cbe', 'cbo', 'abyssinia', 'awash', 'dashen', 'telebirr', 'cash', 'other')),
  masked_number   text,
  currency        char(3) not null default 'ETB',
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  server_version  bigint not null default 0
);

create index financial_accounts_owner_idx on public.financial_accounts (owner_type, owner_id);
create unique index financial_accounts_masked_unique
  on public.financial_accounts (owner_type, owner_id, institution, masked_number)
  where masked_number is not null and deleted_at is null;

-- ---------------------------------------------------------------------------
-- Transaction sources: where a transaction came from.
-- ---------------------------------------------------------------------------

create table public.transaction_sources (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  type            text not null check (type in ('manual', 'sms', 'shortcut', 'bank', 'other')),
  provider        text,
  identifier      text,
  metadata        jsonb not null default '{}'::jsonb,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  server_version  bigint not null default 0
);

create index transaction_sources_user_idx on public.transaction_sources (user_id);
create unique index transaction_sources_unique
  on public.transaction_sources (user_id, type, coalesce(provider, ''), coalesce(identifier, ''))
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- Categories. user_id null = built-in default, visible to everyone.
-- key is a stable slug for defaults ("food.coffee") used by the categorizer.
-- ---------------------------------------------------------------------------

create table public.categories (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users (id) on delete cascade,
  parent_id       uuid references public.categories (id),
  key             text,
  name            text not null,
  icon            text,
  color           text,
  kind            text not null default 'expense' check (kind in ('expense', 'income', 'both')),
  sort_order      int not null default 0,
  is_archived     boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  server_version  bigint not null default 0
);

create index categories_user_idx on public.categories (user_id);
create unique index categories_default_key_unique on public.categories (key) where user_id is null;

-- ---------------------------------------------------------------------------
-- Transactions: the core entity.
-- ---------------------------------------------------------------------------

create table public.transactions (
  id                   uuid primary key default gen_random_uuid(),
  account_id           uuid not null references public.financial_accounts (id) on delete cascade,
  created_by           uuid references auth.users (id) on delete set null default auth.uid(),
  type                 text not null check (type in ('expense', 'income', 'transfer')),
  amount               bigint not null check (amount > 0),
  fee                  bigint not null default 0 check (fee >= 0),   -- bank/telebirr charges incl. VAT
  currency             char(3) not null default 'ETB',
  occurred_at          timestamptz not null,
  merchant_name        text,
  counterparty_name    text,
  counterparty_kind    text check (counterparty_kind in ('person', 'business', 'unknown')),
  counterparty_account text,                                          -- masked, e.g. 2519****1122
  category_id          uuid references public.categories (id) on delete set null,
  category_source      text check (category_source in ('user', 'rule', 'merchant_map', 'keyword', 'ai', 'fallback')),
  category_confidence  numeric(4, 3) check (category_confidence between 0 and 1),
  source_id            uuid references public.transaction_sources (id) on delete set null,
  description          text,
  notes                text,
  reference_id         text,
  status               text not null default 'confirmed' check (status in ('pending', 'confirmed', 'needs_review')),
  review_reason        text check (review_reason in ('low_parse_confidence', 'low_category_confidence', 'possible_duplicate')),
  confidence_score     numeric(4, 3) check (confidence_score between 0 and 1),
  fingerprint          text,
  duplicate_of         uuid references public.transactions (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  server_version       bigint not null default 0
);

create index transactions_account_occurred_idx on public.transactions (account_id, occurred_at desc);
create index transactions_server_version_idx on public.transactions (server_version);
create index transactions_category_idx on public.transactions (category_id);
-- Exact-duplicate guard: one live transaction per bank reference per account.
create unique index transactions_reference_unique
  on public.transactions (account_id, reference_id)
  where reference_id is not null and deleted_at is null;

-- ---------------------------------------------------------------------------
-- Categorization rules ("merchant memory"). Written when a user corrects a
-- category; always wins over every other categorizer step.
-- ---------------------------------------------------------------------------

create table public.categorization_rules (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  match_field     text not null default 'counterparty' check (match_field in ('counterparty', 'description')),
  match_value     text not null,
  category_id     uuid not null references public.categories (id) on delete cascade,
  source          text not null default 'user_correction' check (source in ('user_correction', 'system')),
  hit_count       int not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  server_version  bigint not null default 0
);

create unique index categorization_rules_unique
  on public.categorization_rules (user_id, match_field, match_value)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- Server-only tables (no client access; used by Edge Functions with the
-- service role).
-- ---------------------------------------------------------------------------

-- Shared AI results: one classification per normalized merchant.
create table public.merchant_category_cache (
  normalized_counterparty  text primary key,
  category_key             text not null,
  confidence               numeric(4, 3) not null check (confidence between 0 and 1),
  model                    text not null,
  created_at               timestamptz not null default now()
);

-- Raw bank messages, encrypted by the ingest function, kept only long enough
-- to re-parse when a parser improves.
create table public.raw_messages (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  source_id        uuid references public.transaction_sources (id) on delete set null,
  body_ciphertext  text not null,
  sender           text,
  received_at      timestamptz not null,
  parse_status     text not null default 'pending' check (parse_status in ('pending', 'parsed', 'failed', 'ignored', 'duplicate')),
  parser_name      text,
  parser_version   int,
  transaction_id   uuid references public.transactions (id) on delete set null,
  error            text,
  expires_at       timestamptz not null default now() + interval '30 days',
  created_at       timestamptz not null default now()
);

create index raw_messages_expires_idx on public.raw_messages (expires_at);

-- Per-device tokens the iPhone Shortcut uses to call the ingest function.
-- Only the SHA-256 hash is stored; the plain token is shown once at creation.
create table public.ingestion_tokens (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  name          text not null,
  token_hash    text not null unique,
  last_used_at  timestamptz,
  revoked_at    timestamptz,
  created_at    timestamptz not null default now()
);

create index ingestion_tokens_user_idx on public.ingestion_tokens (user_id);

-- ---------------------------------------------------------------------------
-- Sync stamping triggers
-- ---------------------------------------------------------------------------

create trigger profiles_stamp before insert or update on public.profiles
  for each row execute function public.stamp_sync_columns();
create trigger financial_accounts_stamp before insert or update on public.financial_accounts
  for each row execute function public.stamp_sync_columns();
create trigger transaction_sources_stamp before insert or update on public.transaction_sources
  for each row execute function public.stamp_sync_columns();
create trigger categories_stamp before insert or update on public.categories
  for each row execute function public.stamp_sync_columns();
create trigger transactions_stamp before insert or update on public.transactions
  for each row execute function public.stamp_sync_columns();
create trigger categorization_rules_stamp before insert or update on public.categorization_rules
  for each row execute function public.stamp_sync_columns();
