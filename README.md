# Finance Tracking App

A personal finance app that captures transactions automatically from Ethiopian bank and telebirr SMS,
so tracking spending takes almost no effort. See [docs/finance-app-v1-prd.md](docs/finance-app-v1-prd.md)
for the product and [docs/finance-app-v1-build-plan.md](docs/finance-app-v1-build-plan.md) for how it is built.

**Stack:** Flutter + Isar on the phone (coming in `mobile/`), Supabase for the backend
(Postgres with Row Level Security, Auth, Edge Functions in TypeScript).

## Layout

```
supabase/
  migrations/            schema, security rules, sync functions, default categories
  functions/
    ingest/              POST endpoint for bank SMS (iPhone Shortcut, paste, Android later)
    _shared/
      parsers/           one parser per sender: telebirr, cbe, cbo, boa, plus generic
      pipeline.ts        parse -> normalize -> dedup -> categorize -> save
      categorizer.ts     user rules -> merchant map -> AI (cached) -> fallback
      tests/             golden tests from real (anonymized) SMS samples
  tests/db/              RLS and sync tests, run on plain Postgres
scripts/test-db.sh       runs migrations + database tests
docs/                    PRD and build plan
```

## Data model in one paragraph

Everything hangs off `financial_accounts` (owner → account → transactions), so business/team
accounts can be added later without migrating data. Amounts are integers in santim
(2,500.00 ETB = `250000`), with bank fees in a separate `fee` column. Every synced table has a
`server_version` from one sequence and a `deleted_at` tombstone; the phone pulls with
`sync_pull(since)` and pushes its outbox with `sync_push(ops)`. Raw SMS is stored encrypted
in `raw_messages` for 30 days only.

## Running the tests

```sh
deno task test         # parsers and pipeline (Deno 2)
deno task check        # type-check the ingest function
scripts/test-db.sh     # migrations + RLS/sync tests on a throwaway Postgres
# or against an empty database you provide:
DATABASE_URL=postgresql://postgres@localhost:5432/postgres scripts/test-db.sh
```

## Running locally with Supabase

```sh
supabase start                       # needs Docker
supabase functions serve ingest --env-file supabase/.env.local
```

`supabase/.env.local` needs `RAW_MESSAGE_KEY` (32 random bytes, base64: `openssl rand -base64 32`).

## The ingest endpoint

```
POST /functions/v1/ingest
Authorization: Bearer <user JWT>   or   Bearer fin_<ingestion token>
{ "text": "<SMS body>", "sender": "CBE", "receivedAt": "2026-10-05T12:00:00Z", "channel": "shortcut" }
```

Ingestion tokens for the iPhone Shortcut are created in the app via `create_ingestion_token(name)`;
only their SHA-256 hash is stored.

Responses: `created` (with `reviewReason` when it needs the user's eye), `duplicate`, `enriched`
(a notice such as a CBE Fast Loan repayment that explained an existing debit), `ignored`
(OTP, promo, credit-line drawdown), or `unrecognized`.
