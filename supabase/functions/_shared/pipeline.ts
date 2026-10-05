// The ingestion pipeline (build plan 4.1):
// raw message -> parser -> normalizer -> dedup -> categorizer -> confidence -> transaction.
// Storage is behind IngestStore so the pipeline can be tested without a database.

import { type AiCategorizer, categorize, type CategoryStore, REVIEW_THRESHOLD } from "./categorizer.ts";
import { decideDuplicate, type DedupCandidate } from "./dedup.ts";
import { counterpartyKind, displayName, matchKey } from "./normalizer.ts";
import { parseMessage } from "./parsers/registry.ts";
import type { CounterpartyKind, Institution, TransactionType } from "./types.ts";

export type Channel = "shortcut" | "paste" | "android_sms";

export interface IngestRequest {
  userId: string;
  channel: Channel;
  text: string;
  sender: string | null;
  receivedAt: Date;
}

export type ReviewReason = "low_parse_confidence" | "low_category_confidence" | "possible_duplicate";

export interface NewTransaction {
  accountId: string;
  createdBy: string;
  sourceId: string;
  type: TransactionType;
  amount: number;
  fee: number;
  currency: string;
  occurredAt: Date;
  counterpartyName: string | null;
  counterpartyKind: CounterpartyKind;
  counterpartyAccount: string | null;
  description: string | null;
  referenceId: string | null;
  categoryId: string | null;
  categoryKey: string | null;
  categorySource: string;
  categoryConfidence: number;
  status: "confirmed" | "needs_review";
  reviewReason: ReviewReason | null;
  confidenceScore: number;
  fingerprint: string;
  duplicateOf: string | null;
}

export interface RawMessagePatch {
  parseStatus: "parsed" | "failed" | "ignored" | "duplicate";
  parserName?: string;
  parserVersion?: number;
  transactionId?: string | null;
  error?: string | null;
}

export interface IngestStore extends CategoryStore {
  saveRawMessage(
    userId: string,
    sourceId: string,
    ciphertext: string,
    sender: string | null,
    receivedAt: Date,
  ): Promise<string>;
  updateRawMessage(id: string, patch: RawMessagePatch): Promise<void>;
  sourceFor(userId: string, channel: Channel): Promise<string>;
  /** Finds the user's account for this bank (by masked number when known),
   * creating it on first sight. */
  resolveAccount(userId: string, institution: Institution, masked: string | null): Promise<string>;
  /** Live transactions on the account that could be the same money movement:
   * same amount within a few days, or the same bank reference. */
  duplicateCandidates(
    accountId: string,
    amount: number,
    around: Date,
    referenceId: string | null,
  ): Promise<DedupCandidate[]>;
  insertTransaction(tx: NewTransaction): Promise<{ id: string } | { conflict: true }>;
  /** Fills only the empty fields of an existing transaction. */
  enrichTransaction(
    id: string,
    fields: { counterpartyName: string; counterpartyKind: CounterpartyKind; description: string | null },
  ): Promise<void>;
}

export type IngestResult =
  | { status: "created"; transactionId: string; reviewReason: ReviewReason | null }
  | { status: "duplicate"; transactionId: string }
  | { status: "enriched"; transactionId: string }
  | { status: "ignored"; reason: string }
  | { status: "unrecognized" };

export interface IngestDeps {
  encrypt(plain: string): Promise<string>;
  ai?: AiCategorizer;
}

export const PARSE_REVIEW_THRESHOLD = 0.7;

export async function ingestMessage(store: IngestStore, req: IngestRequest, deps: IngestDeps): Promise<IngestResult> {
  const sourceId = await store.sourceFor(req.userId, req.channel);
  const rawId = await store.saveRawMessage(
    req.userId,
    sourceId,
    await deps.encrypt(req.text),
    req.sender,
    req.receivedAt,
  );

  const result = parseMessage({ text: req.text, sender: req.sender, receivedAt: req.receivedAt });

  if (result.status === "unrecognized") {
    await store.updateRawMessage(rawId, { parseStatus: "failed", error: "unrecognized" });
    return { status: "unrecognized" };
  }
  const meta = { parserName: result.parser, parserVersion: result.version };
  if (result.status === "ignored") {
    await store.updateRawMessage(rawId, { parseStatus: "ignored", ...meta, error: result.reason });
    return { status: "ignored", reason: result.reason };
  }

  const p = result.tx;
  const occurredAt = p.occurredAt ?? req.receivedAt;
  const name = displayName(p.counterpartyName);
  const key = matchKey(name);
  const kind = counterpartyKind(name, p.counterpartyKind);
  const accountId = await store.resolveAccount(req.userId, p.institution, p.accountMasked);

  const candidates = await store.duplicateCandidates(accountId, p.amount, occurredAt, p.referenceId);
  const dup = decideDuplicate(
    { kind: p.kind, type: p.type, amount: p.amount, occurredAt, referenceId: p.referenceId, counterpartyKey: key },
    candidates,
  );

  if (dup.kind === "exact") {
    await store.updateRawMessage(rawId, { parseStatus: "duplicate", ...meta, transactionId: dup.id });
    return { status: "duplicate", transactionId: dup.id };
  }
  if (dup.kind === "enrich" && name) {
    await store.enrichTransaction(dup.id, {
      counterpartyName: name,
      counterpartyKind: kind,
      description: p.description,
    });
    await store.updateRawMessage(rawId, { parseStatus: "duplicate", ...meta, transactionId: dup.id });
    return { status: "enriched", transactionId: dup.id };
  }

  const category = await categorize(
    {
      userId: req.userId,
      type: p.type,
      amount: p.amount,
      counterpartyName: name,
      counterpartyKey: key,
      counterpartyKind: kind,
      description: p.description,
    },
    store,
    deps.ai,
  );

  let reviewReason: ReviewReason | null = null;
  if (dup.kind === "probable") reviewReason = "possible_duplicate";
  else if (p.confidence < PARSE_REVIEW_THRESHOLD) reviewReason = "low_parse_confidence";
  else if (category.confidence < REVIEW_THRESHOLD) reviewReason = "low_category_confidence";

  const inserted = await store.insertTransaction({
    accountId,
    createdBy: req.userId,
    sourceId,
    type: p.type,
    amount: p.amount,
    fee: p.fee,
    currency: p.currency,
    occurredAt,
    counterpartyName: name,
    counterpartyKind: kind,
    counterpartyAccount: p.counterpartyAccount,
    description: p.description,
    referenceId: p.referenceId,
    categoryId: category.categoryId,
    categoryKey: category.categoryKey,
    categorySource: category.source,
    categoryConfidence: round3(category.confidence),
    status: reviewReason ? "needs_review" : "confirmed",
    reviewReason,
    confidenceScore: round3(p.confidence * category.confidence),
    fingerprint: [accountId, p.type, p.amount, Math.floor(occurredAt.getTime() / 60_000)].join(":"),
    duplicateOf: dup.kind === "probable" ? dup.id : null,
  });

  if ("conflict" in inserted) {
    // Another request stored the same bank reference first.
    const again = await store.duplicateCandidates(accountId, p.amount, occurredAt, p.referenceId);
    const id = again.find((c) => c.referenceId === p.referenceId)?.id ?? "";
    await store.updateRawMessage(rawId, { parseStatus: "duplicate", ...meta, transactionId: id || null });
    return { status: "duplicate", transactionId: id };
  }

  await store.updateRawMessage(rawId, { parseStatus: "parsed", ...meta, transactionId: inserted.id });
  return { status: "created", transactionId: inserted.id, reviewReason };
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}
