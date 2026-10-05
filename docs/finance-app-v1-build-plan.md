# Finance App V1: Build Plan

Companion to [finance-app-v1-prd.md](finance-app-v1-prd.md). Written 2026-10-05.

This plan keeps the PRD's architecture (Transaction engine as the core, local-first Flutter app, PostgreSQL as the source of truth, parser per bank) and turns it into concrete build steps. Decisions made since the PRD: the backend is **Supabase** instead of FastAPI, the local DB is the **Isar community fork**, and **AI categorization is in V1**. Where the PRD leaves something open or where I'd change a detail, it's called out in **Section 2** so it can be decided before code is written.

---

## 1. What the PRD gets right (keep as is)

* `Transaction` as the core entity, with `counterpartyName` instead of "merchant".
* `TransactionSource` as an abstraction from day one.
* One ingestion pipeline that every input (Shortcut, Android SMS, manual, future bank API) feeds into.
* A parser interface with one parser per bank, plus a generic fallback.
* Structured search underneath any natural-language layer; AI is never the source of truth (AI suggests categories, the database and the user's corrections decide).
* Local-first with an outbox, so the app works offline.
* Measuring success by the share of transactions captured automatically.

---

## 2. Gaps and changes to decide before building

### 2.1 Add `FinancialAccount` now, not later

Section 22 says "Owner → Financial Account → Transactions", but the data model in Section 5 hangs `Transaction` directly off `userId`. Retrofitting this later means migrating every row and every query.

Recommendation: add the account layer in V1, even though each user only has personal accounts.

```
FinancialAccount
- id
- ownerType        (user | business; only "user" in V1)
- ownerId
- name             ("CBE ****1234", "Telebirr", "Cash")
- institution      (cbe | awash | dashen | telebirr | cash | other)
- maskedNumber
- currency
- createdAt / updatedAt
```

`Transaction` gets `accountId` (required) and keeps `userId` only as a denormalized "created by" field. Queries filter by the accounts a user can see, which is exactly what the business/team feature needs later. Parsers can usually fill `accountId` from the masked account number in the SMS ("account 1234").

### 2.2 Missing models

The PRD references these but doesn't define them:

```
Category
- id
- userId           (null = built-in default)
- parentId         (Food → Restaurants)
- name, icon, color
- kind             (expense | income | both)
- isArchived

CategorizationRule          ("merchant memory", Section 13)
- id
- userId
- matchField       (counterparty | description)
- matchValue       (normalized, e.g. "meron cafe")
- categoryId
- source           (user_correction | system)
- hitCount, updatedAt

MerchantCategoryCache       (shared AI results, see 4.3)
- normalizedCounterparty
- categoryKey      (default category, e.g. "food.coffee")
- confidence
- model, createdAt

RawMessage                  (see 2.4)
- id, userId, sourceId
- body (encrypted), receivedAt
- parseStatus      (parsed | failed | ignored)
- parserName, parserVersion
- transactionId
- expiresAt
```

`Transaction` also needs: `fingerprint`, `deletedAt` (soft delete for sync), `version` (for sync conflicts), plus `categorySource` (user | rule | merchant_map | keyword | ai | fallback) and `categoryConfidence` so the review queue knows how confident a category is.

### 2.3 Store money as integers

`amount` should be an integer in minor units (santim; 2,500.00 ETB = 250000) or a fixed-precision decimal, never a float. Sign comes from `type`, so `amount` is always positive.

### 2.4 Move raw SMS out of `Transaction`

Section 5 puts `rawData` on `Transaction`, but Section 24 says raw SMS must not become the permanent data model. Keep raw text in `RawMessage`, encrypted, with a retention window (suggest 30 days) so it can be re-parsed when a parser improves, then deleted by a scheduled job. `Transaction` keeps only extracted fields plus `referenceId`.

### 2.5 Duplicate detection needs two tiers

A pure fingerprint will miss real duplicates (a manual entry at 14:00 and the bank SMS at 14:32 for the same purchase) and can wrongly merge real repeats (two 50 ETB taxis on the same day).

* **Exact**: same account + same bank `referenceId` → ignore silently.
* **Probable**: same account (or no account), same amount and direction, within a time window (e.g. ±3 hours), similar counterparty → create, but mark `needs_review` with "Looks like a duplicate of …" and let the user merge.

This changes Section 14's "Yes → Ignore" to "Exact → ignore, probable → ask".

### 2.6 Isar is a risk worth weighing

The PRD names Isar. Upstream Isar development largely stalled after 2023 and the community now maintains a fork (`isar_community`); worth confirming the current state at setup. The app's core reads are relational aggregations ("sum by category this month", filters, search), which SQLite does natively.

**Decided (2026-10-05): Isar community fork (`isar_community`)**, matching the PRD. Drift was the alternative considered.

Implications to handle in the build:
* Pin the package version and keep all Isar access behind the repository layer, so the DB could be swapped later without touching features.
* Write category totals and monthly summaries as repository methods (query + sum in Dart), covered by tests.
* Encryption at rest: Isar has no built-in encryption, so store sensitive fields encrypted (key in flutter_secure_storage) or rely on OS file protection; decide in Phase 1.

### 2.7 iPhone Shortcut realities

* Since iOS 17 a personal automation can trigger on "Message contains …" and run without asking. That covers bank SMS.
* The Shortcut posts straight to the API, so it needs its own credential: a per-device **ingestion token** created in the app (Settings → Connect iPhone Shortcut), scoped to the `ingest` Edge Function only, stored hashed in an `ingestion_tokens` table, revocable.
* If the phone is offline when the SMS arrives, the Shortcut's request fails and the message is lost. Mitigations: a "Paste bank SMS" box in the app that sends text through the same pipeline, and a later "import recent SMS" flow.
* Ship the Shortcut as an iCloud share link so setup is one tap plus pasting the token.

### 2.8 Android SMS permission (later phase)

Google Play restricts `READ_SMS`/`RECEIVE_SMS`. Apps must file a permissions declaration and fit an allowed use case; SMS-based money management is one of the listed exceptions, but approval isn't guaranteed. Plan for the declaration and keep the "paste SMS" fallback.

### 2.9 Where parsing runs

Parsing stays on the server as the PRD says, now in a Supabase Edge Function (TypeScript), so parsers can be fixed without an app release. Manual transactions are created locally first and synced, and never go through the parser.

### 2.10 Backend and authentication

**Decided (2026-10-05): Supabase** instead of FastAPI, and **Supabase Auth** for login.

* Supabase is PostgreSQL underneath, so the data model in this plan is unchanged.
* Supabase Auth gives email, Google and Apple sign-in (phone OTP later). A `profiles` row (the PRD's `User`) is created for each `auth.users` row by a trigger.
* Row Level Security on every table: a user can only read and write rows belonging to `financial_accounts` they own. This is also the hook for business/team access later.
* The phone talks to Postgres directly through the Supabase client for simple reads and writes; anything with logic (SMS ingestion, AI categorization, sync batches) runs in Edge Functions or Postgres functions.
* The SMS pipeline is written in TypeScript (Deno) instead of Python.

---

## 3. Tech stack

| Layer | Choice |
|---|---|
| Mobile | Flutter (iOS first, Android later), Riverpod for state, go_router |
| Local DB | Isar community fork (decided, see 2.6) |
| Secure storage | flutter_secure_storage for session tokens and the field-encryption key |
| Backend | Supabase (decided): Postgres + Row Level Security, Edge Functions (TypeScript/Deno) for ingestion and AI, Postgres functions (RPC) for sync |
| Database | Supabase PostgreSQL; schema as SQL migrations via the Supabase CLI |
| Auth | Supabase Auth (decided): email, Google, Apple |
| AI | LLM call from an Edge Function for categorizing unknown merchants (default model: Claude Haiku 4.5, cheap and fast; key kept in Supabase secrets) |
| Background jobs | pg_cron for raw SMS expiry and re-parse runs |
| Hosting | Supabase cloud, EU (Frankfurt) region as the closest to Ethiopia. Free tier for development; Pro before real use, since free projects pause when idle |
| Local dev | `supabase start` (local Postgres, Auth, Functions in Docker) |
| CI | GitHub Actions: `deno test` + lint for functions, migration check, Flutter analyze + tests |

### Repository layout (one monorepo)

```
finance-app/
├── docs/                 PRD, this plan, ADRs
├── supabase/
│   ├── migrations/       SQL: tables, RLS policies, sync RPCs, pg_cron jobs
│   ├── seed.sql          default categories, merchant seed map
│   └── functions/
│       ├── ingest/       entry point for Shortcut / paste SMS
│       ├── categorize/   AI categorization for unknown merchants
│       └── _shared/
│           ├── pipeline.ts
│           ├── parsers/  base.ts, cbe.ts, telebirr.ts, generic.ts, ...
│           ├── normalizer.ts
│           ├── dedup.ts
│           ├── categorizer.ts
│           ├── ai.ts
│           └── tests/fixtures/sms/  anonymized real SMS samples per bank
└── mobile/
    └── lib/
        ├── data/         Isar, repositories, sync/outbox, Supabase client
        ├── domain/       models, use cases
        └── features/     home, transactions, add_transaction, review, search, settings
```

---

## 4. Key designs

### 4.1 Ingestion pipeline (Edge Function)

```
POST functions/v1/ingest  { sourceType, text, receivedAt, deviceId }
   (auth: user session from the app, or ingestion token from the Shortcut)
   ↓
Save RawMessage (encrypted)
   ↓
Parser registry: try each parser's can_parse(); first match wins, else GenericParser
   ↓
ParsedTransaction { amount, currency, direction, counterparty, accountHint,
                    referenceId, occurredAt, balanceAfter, confidence }
   ↓
Normalizer   (title-case counterparty, strip noise, resolve account by masked number)
   ↓
Dedup        (exact → stop; probable → flag)
   ↓
Categorizer  (user rules → merchant map → AI cache → AI call → "Other"; see 4.3)
   ↓
Confidence   (parser confidence × category confidence → confirmed or needs_review)
   ↓
Transaction saved, version bumped → picked up by the next device sync
```

Parser contract:

```ts
interface TransactionParser {
  name: string;
  version: number;
  canParse(text: string, sender?: string): boolean;
  parse(text: string, receivedAt: Date): ParsedTransaction | null;
}
// amounts in ParsedTransaction are integers in santim
```

Every parser is tested against a folder of real, anonymized SMS samples with expected output (golden tests). Non-transaction SMS (OTP codes, promos) must return `None` and be marked `ignored`.

### 4.2 Sync

* IDs are UUIDv7, generated on the device, so offline creation needs no server round trip and retries are idempotent.
* **Push**: the local Isar outbox holds pending create/update/delete operations; the client sends them in batches to a Postgres function `sync_push(ops)` (called via Supabase RPC, RLS still applies). It upserts each row by its client-generated id, and a trigger stamps a `server_version` from a sequence.
* **Pull**: `sync_pull(since)` returns every row (transactions, categories, rules, accounts) with `server_version > since`, including soft-deleted tombstones. The client stores the highest version as its cursor.
* Supabase Realtime on the user's transactions can tell the app "something changed, pull now", so SMS-ingested transactions appear without waiting for the next app open.
* **Conflicts**: last write wins per record, compared by server version; user edits always beat automated updates to the same field (for example a category the user set is never overwritten by the categorizer).
* Triggers: app start, app resume, after a local write, pull-to-refresh, and the Realtime nudge while the app is open.

### 4.3 Categorization

AI categorization is in V1 (decided 2026-10-05). Order of precedence:

1. **The user's own rule** for this counterparty (created automatically when they correct a category). Always wins; AI never overrides it.
2. **Merchant seed map**: common Ethiopian merchants and keywords (cafe, hotel, taxi/ride, fuel, Ethio telecom, EEU, …). Free and instant.
3. **AI cache**: if this normalized merchant was already classified by AI (for any user), reuse that result. Keeps cost and latency low.
4. **AI call** (`categorize` Edge Function) for unknown merchants. Input: normalized counterparty, transaction type, amount, a short description, and the list of category keys. Output, as structured JSON: `{ categoryKey, confidence }`. The result is written to the cache and mapped to the user's category.
5. **Fallback** "Other" with low confidence if AI is unavailable or errors.

Confidence threshold (start at 0.8, tune on real data):
* At or above → `confirmed`, `categorySource = ai`.
* Below → `needs_review`, with the AI's guess pre-selected on the review card.

Privacy rules for the AI call:
* Never send raw SMS, account numbers, balances or the user's name.
* Transfers to people (e.g. "Abebe") skip AI: they go to review or to a person-based rule, since a name says nothing about the category.
* Manual transactions already have a user-chosen category; AI can suggest one while typing when online, but never sets it silently.

The categorizer interface stays the same, so a better model or a per-user model can replace step 4 later.

### 4.4 Review queue

Transactions land in review when parser confidence is low, the category came from the fallback, or dedup flagged a probable duplicate. The review card asks one question ("What was this?" with 4 category chips, or "Same as …? Merge / Keep both"). Answering writes a `CategorizationRule` so the same counterparty is handled automatically next time.

### 4.5 Search

V1 ships structured search: a search box over counterparty and notes, plus filters (date range, category, type, account, amount range) and a totals line ("12 transactions · 4,250 ETB"). Natural-language questions come after, as a thin layer that turns a sentence into the same filter object, which the server validates before running.

---

## 5. Build phases

These follow the PRD's six phases, with one change: the parser work starts as soon as SMS samples exist, because automatic capture is the success metric and it's the part with the most unknowns.

### Phase 0 — Setup and inputs

* Create the GitHub repo and the monorepo skeleton above.
* Create the Supabase project (dev) and set up local dev with the Supabase CLI.
* Collect real bank SMS samples (see Section 6). This unblocks Phase 3.
* CI running function tests, migration checks and Flutter checks on every PR.

Done when: a hello-world Edge Function deploys, migrations apply cleanly, and an empty Flutter app signs in with Supabase Auth on iOS.

### Phase 1 — Foundation

* Database: profiles, financial_accounts, transactions, categories, transaction_sources tables as SQL migrations; RLS policies; `server_version` trigger; `sync_push` / `sync_pull` functions.
* Default category seed.
* Tests that RLS blocks one user from reading another's data.
* Mobile: auth screens, local DB schema mirroring the backend, transaction repository, outbox, sync push/pull.

Done when: a transaction created offline on the phone appears in Supabase after reconnecting, and a row inserted on the server appears on the phone after a pull.

### Phase 2 — Manual tracking

* Add transaction screen built for speed: amount keypad first, category chips, everything else optional.
* Edit and delete (soft delete, synced).
* Transaction history feed grouped by day.
* Category management (rename, add custom, archive).

Done when: manual tracking works end to end on one device and survives reinstall via sync.

### Phase 3 — Automated ingestion

* `raw_messages` table and the `ingest` Edge Function.
* Parser interface, registry, `CBEParser`, `TelebirrParser` (if samples allow), `GenericParser`.
* Normalizer, two-tier dedup, confidence scoring.
* Golden tests from the SMS sample set.
* "Paste bank SMS" in the app as the first real input source.

Done when: every collected sample parses correctly or is deliberately ignored, and pasting a CBE SMS produces the right transaction on the phone.

### Phase 4 — iPhone Shortcut

* Ingestion tokens (create, list, revoke) in Settings.
* Shared Shortcut: automation on messages containing ETB/Birr/debited/credited, posts text + time to the `ingest` function with the token.
* Setup guide screen in the app.

Done when: a real bank SMS on Miko's iPhone shows up in the app without opening it.

### Phase 5 — Intelligence

* Categorizer with user rules, merchant seed map and keywords.
* AI categorization: `categorize` Edge Function, merchant cache, confidence threshold, privacy rules (4.3).
* Correction → rule learning.
* Review queue screen, showing the AI's guess when it was unsure.
* Basic insights: month-over-month by category, largest expense this week, category totals.

Done when: an unknown merchant gets a sensible category from AI, low-confidence guesses land in review, and correcting a counterparty once means its next transaction is categorized correctly with no AI call and no review.

### Phase 6 — Polish

* Home screen per PRD Section 16.
* Search and filters (4.5).
* Empty states, error handling, onboarding (connect Shortcut, pick currency).
* Delete account / delete all data.
* Raw SMS expiry job.
* Capture-rate metric: share of transactions created by automation vs manually, and share categorized without review, shown internally.

Done when: Miko uses it as their only expense tracker for a month.

### Later (not V1)

Android SMS listener (needs the Play permission declaration), natural-language search, per-user AI personalization, push notifications for new transactions, business accounts on the `FinancialAccount` layer.

---

## 6. What's needed from Miko

1. **Real bank SMS samples**: 10 or more per bank you use (CBE, Telebirr, Awash, Dashen, …), covering debit, credit, transfer in/out, and a few non-transaction messages (OTP, promos). Replace names and account digits with fake ones but keep the exact format, spacing and punctuation.
2. **A GitHub repository** for the code, connected to this project.
3. **An AI API key** when Phase 5 starts (stored only in Supabase secrets).

Decided so far: Isar community fork (local DB), Supabase (backend, auth, hosting), AI categorization in V1.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Bank SMS formats vary or change without notice | Parser per bank, golden tests, raw messages kept 30 days for re-parsing, generic fallback, review queue |
| Shortcut fails offline and the SMS is lost | "Paste SMS" fallback; later an SMS import flow |
| Duplicates from multiple sources | Two-tier dedup with review for probable matches |
| Sensitive data exposure | Row Level Security on every table, encrypted sensitive fields in the local DB, TLS, no raw SMS sent to AI, encrypted raw messages with expiry, scoped revocable ingestion tokens, delete-everything option |
| Android SMS permission rejected on Play | Declaration prepared early; paste fallback; Shortcut-style flows don't depend on it |
| AI miscategorizes or costs grow | User rules always win, low-confidence goes to review, shared merchant cache means each merchant is classified once, cheap model by default |
| Supabase lock-in | It's standard Postgres: schema and data export with pg_dump; only Edge Functions and Auth are Supabase-specific |
| Local DB library maintenance | Isar fork pinned and wrapped behind repositories so it can be swapped (2.6) |
