// IngestStore backed by Supabase, used by the ingest function with the
// service role. The service role bypasses RLS, so every query here is
// scoped to the user explicitly.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { AiSuggestion } from "./categorizer.ts";
import type { DedupCandidate } from "./dedup.ts";
import { matchKey } from "./normalizer.ts";
import type { Channel, IngestStore, NewTransaction, RawMessagePatch } from "./pipeline.ts";
import type { CounterpartyKind, Institution } from "./types.ts";

const ACCOUNT_LABELS: Record<Institution, string> = {
  cbe: "CBE",
  cbo: "Coop Bank of Oromia",
  abyssinia: "Bank of Abyssinia",
  awash: "Awash Bank",
  dashen: "Dashen Bank",
  telebirr: "telebirr",
  cash: "Cash",
  other: "Other bank",
};

const DAY_MS = 86_400_000;

function check<T>(res: { data: T; error: { message: string; code?: string } | null }): T {
  if (res.error) throw new Error(`${res.error.code ?? ""} ${res.error.message}`.trim());
  return res.data;
}

/** Like check(), for queries that must return a row. */
function row<T>(res: { data: T; error: { message: string; code?: string } | null }): NonNullable<T> {
  const data = check(res);
  if (data === null || data === undefined) throw new Error("expected a row");
  return data;
}

export class SupabaseIngestStore implements IngestStore {
  private categoryIds = new Map<string, string>();

  constructor(private db: SupabaseClient) {}

  async saveRawMessage(userId: string, sourceId: string, ciphertext: string, sender: string | null, receivedAt: Date) {
    const saved = row(
      await this.db.from("raw_messages").insert({
        user_id: userId,
        source_id: sourceId,
        body_ciphertext: ciphertext,
        sender,
        received_at: receivedAt.toISOString(),
      }).select("id").single(),
    );
    return saved.id as string;
  }

  async updateRawMessage(id: string, patch: RawMessagePatch) {
    check(
      await this.db.from("raw_messages").update({
        parse_status: patch.parseStatus,
        parser_name: patch.parserName ?? null,
        parser_version: patch.parserVersion ?? null,
        transaction_id: patch.transactionId ?? null,
        error: patch.error ?? null,
      }).eq("id", id),
    );
  }

  async sourceFor(userId: string, channel: Channel): Promise<string> {
    const type = channel === "shortcut" ? "shortcut" : "sms";
    const existing = check(
      await this.db.from("transaction_sources").select("id")
        .eq("user_id", userId).eq("type", type).eq("provider", channel).is("deleted_at", null)
        .limit(1).maybeSingle(),
    );
    if (existing) return existing.id as string;

    const created = await this.db.from("transaction_sources")
      .insert({ user_id: userId, type, provider: channel }).select("id").single();
    if (created.error?.code === "23505") return await this.sourceFor(userId, channel);
    return row(created).id as string;
  }

  async resolveAccount(userId: string, institution: Institution, masked: string | null): Promise<string> {
    let query = this.db.from("financial_accounts").select("id")
      .eq("owner_type", "user").eq("owner_id", userId).eq("institution", institution).is("deleted_at", null);
    // Without a masked number, use the account for this bank the user has
    // used most recently (telebirr has only one wallet).
    query = masked ? query.eq("masked_number", masked) : query.order("updated_at", { ascending: false });
    const existing = check(await query.limit(1).maybeSingle());
    if (existing) return existing.id as string;

    // A message without an account number (e.g. CBE Fast Loan) may already
    // have created an account for this bank; claim it now that we know the number.
    if (masked) {
      const unnumbered = check(
        await this.db.from("financial_accounts").select("id")
          .eq("owner_type", "user").eq("owner_id", userId).eq("institution", institution)
          .is("masked_number", null).is("deleted_at", null).limit(1).maybeSingle(),
      );
      if (unnumbered) {
        check(
          await this.db.from("financial_accounts")
            .update({ masked_number: masked, name: `${ACCOUNT_LABELS[institution]} ${masked}` })
            .eq("id", unnumbered.id),
        );
        return unnumbered.id as string;
      }
    }

    const created = await this.db.from("financial_accounts").insert({
      owner_type: "user",
      owner_id: userId,
      institution,
      masked_number: masked,
      name: masked ? `${ACCOUNT_LABELS[institution]} ${masked}` : ACCOUNT_LABELS[institution],
    }).select("id").single();
    if (created.error?.code === "23505") return await this.resolveAccount(userId, institution, masked);
    return row(created).id as string;
  }

  async duplicateCandidates(accountId: string, amount: number, around: Date, referenceId: string | null) {
    const cols = "id, type, amount, occurred_at, reference_id, counterparty_name";
    const nearby = check(
      await this.db.from("transactions").select(cols)
        .eq("account_id", accountId).eq("amount", amount).is("deleted_at", null)
        .gte("occurred_at", new Date(around.getTime() - 3 * DAY_MS).toISOString())
        .lte("occurred_at", new Date(around.getTime() + 3 * DAY_MS).toISOString())
        .limit(50),
    ) ?? [];
    const byRef = referenceId
      ? check(
        await this.db.from("transactions").select(cols)
          .eq("account_id", accountId).eq("reference_id", referenceId).is("deleted_at", null).limit(1),
      ) ?? []
      : [];

    const seen = new Set<string>();
    const out: DedupCandidate[] = [];
    for (const r of [...byRef, ...nearby]) {
      if (seen.has(r.id)) continue;
      seen.add(r.id);
      out.push({
        id: r.id,
        type: r.type,
        amount: Number(r.amount),
        occurredAt: new Date(r.occurred_at),
        referenceId: r.reference_id,
        counterpartyKey: matchKey(r.counterparty_name),
      });
    }
    return out;
  }

  private async categoryIdForKey(key: string | null): Promise<string | null> {
    if (!key) return null;
    if (!this.categoryIds.has(key)) {
      const category = check(
        await this.db.from("categories").select("id").eq("key", key).is("user_id", null).maybeSingle(),
      );
      if (!category) return null;
      this.categoryIds.set(key, category.id);
    }
    return this.categoryIds.get(key)!;
  }

  async insertTransaction(tx: NewTransaction) {
    const res = await this.db.from("transactions").insert({
      account_id: tx.accountId,
      created_by: tx.createdBy,
      source_id: tx.sourceId,
      type: tx.type,
      amount: tx.amount,
      fee: tx.fee,
      currency: tx.currency,
      occurred_at: tx.occurredAt.toISOString(),
      counterparty_name: tx.counterpartyName,
      counterparty_kind: tx.counterpartyKind,
      counterparty_account: tx.counterpartyAccount,
      description: tx.description,
      reference_id: tx.referenceId,
      category_id: tx.categoryId ?? await this.categoryIdForKey(tx.categoryKey),
      category_source: tx.categorySource,
      category_confidence: tx.categoryConfidence,
      status: tx.status,
      review_reason: tx.reviewReason,
      confidence_score: tx.confidenceScore,
      fingerprint: tx.fingerprint,
      duplicate_of: tx.duplicateOf,
    }).select("id").single();
    if (res.error?.code === "23505") return { conflict: true as const };
    return { id: row(res).id as string };
  }

  async enrichTransaction(
    id: string,
    fields: { counterpartyName: string; counterpartyKind: CounterpartyKind; description: string | null },
  ) {
    const current = row(
      await this.db.from("transactions").select("counterparty_name, counterparty_kind, description").eq("id", id)
        .single(),
    );
    const patch: Record<string, unknown> = {};
    if (!current.counterparty_name) patch.counterparty_name = fields.counterpartyName;
    if (!current.counterparty_kind || current.counterparty_kind === "unknown") {
      patch.counterparty_kind = fields.counterpartyKind;
    }
    if (!current.description && fields.description) patch.description = fields.description;
    if (Object.keys(patch).length) check(await this.db.from("transactions").update(patch).eq("id", id));
  }

  async userRuleCategoryId(userId: string, counterpartyKey: string) {
    const rule = check(
      await this.db.from("categorization_rules").select("category_id")
        .eq("user_id", userId).eq("match_field", "counterparty").eq("match_value", counterpartyKey)
        .is("deleted_at", null).maybeSingle(),
    );
    return (rule?.category_id as string | undefined) ?? null;
  }

  async cachedSuggestion(counterpartyKey: string): Promise<AiSuggestion | null> {
    const cached = check(
      await this.db.from("merchant_category_cache").select("category_key, confidence, model")
        .eq("normalized_counterparty", counterpartyKey).maybeSingle(),
    );
    return cached
      ? { categoryKey: cached.category_key, confidence: Number(cached.confidence), model: cached.model }
      : null;
  }

  async saveSuggestion(counterpartyKey: string, s: AiSuggestion) {
    check(
      await this.db.from("merchant_category_cache").upsert({
        normalized_counterparty: counterpartyKey,
        category_key: s.categoryKey,
        confidence: s.confidence,
        model: s.model,
      }),
    );
  }
}
