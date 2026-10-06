import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import type { AiCategorizeInput, AiCategorizer, AiSuggestion } from "../categorizer.ts";
import { decryptText, encryptText, importKey } from "../crypto.ts";
import type { DedupCandidate } from "../dedup.ts";
import { matchKey } from "../normalizer.ts";
import { addisDate } from "../parsers/util.ts";
import {
  type Channel,
  ingestMessage,
  type IngestRequest,
  type IngestStore,
  type NewTransaction,
  type RawMessagePatch,
} from "../pipeline.ts";
import type { CounterpartyKind, Institution } from "../types.ts";
import { SMS } from "./fixtures.ts";

const USER = "user-1";

/** In-memory IngestStore mirroring what the database enforces. */
class MemoryStore implements IngestStore {
  raw = new Map<string, { ciphertext: string } & Partial<RawMessagePatch>>();
  accounts: { id: string; institution: Institution; masked: string | null }[] = [];
  sources = new Map<string, string>();
  txs: (NewTransaction & { id: string })[] = [];
  rules = new Map<string, string>();
  cache = new Map<string, AiSuggestion>();
  private n = 0;
  private id(prefix: string) {
    return `${prefix}-${++this.n}`;
  }

  saveRawMessage(_u: string, _s: string, ciphertext: string) {
    const id = this.id("raw");
    this.raw.set(id, { ciphertext });
    return Promise.resolve(id);
  }
  updateRawMessage(id: string, patch: RawMessagePatch) {
    Object.assign(this.raw.get(id)!, patch);
    return Promise.resolve();
  }
  sourceFor(_u: string, channel: Channel) {
    if (!this.sources.has(channel)) this.sources.set(channel, this.id("src"));
    return Promise.resolve(this.sources.get(channel)!);
  }
  resolveAccount(_u: string, institution: Institution, masked: string | null) {
    let acct = this.accounts.find((a) => a.institution === institution && (masked === null || a.masked === masked));
    if (!acct && masked) {
      acct = this.accounts.find((a) => a.institution === institution && a.masked === null);
      if (acct) acct.masked = masked;
    }
    if (!acct) {
      acct = { id: this.id("acct"), institution, masked };
      this.accounts.push(acct);
    }
    return Promise.resolve(acct.id);
  }
  duplicateCandidates(accountId: string, amount: number, around: Date, referenceId: string | null) {
    const out: DedupCandidate[] = this.txs
      .filter((t) =>
        t.accountId === accountId &&
        ((t.amount === amount && Math.abs(t.occurredAt.getTime() - around.getTime()) <= 3 * 86_400_000) ||
          (referenceId !== null && t.referenceId === referenceId))
      )
      .map((t) => ({
        id: t.id,
        type: t.type,
        amount: t.amount,
        occurredAt: t.occurredAt,
        referenceId: t.referenceId,
        counterpartyKey: matchKey(t.counterpartyName),
      }));
    return Promise.resolve(out);
  }
  insertTransaction(tx: NewTransaction) {
    if (tx.referenceId && this.txs.some((t) => t.accountId === tx.accountId && t.referenceId === tx.referenceId)) {
      return Promise.resolve({ conflict: true as const });
    }
    const id = this.id("tx");
    this.txs.push({ ...tx, id });
    return Promise.resolve({ id });
  }
  enrichTransaction(
    id: string,
    f: { counterpartyName: string; counterpartyKind: CounterpartyKind; description: string | null },
  ) {
    const t = this.txs.find((t) => t.id === id)!;
    t.counterpartyName ??= f.counterpartyName;
    if (t.counterpartyKind === "unknown") t.counterpartyKind = f.counterpartyKind;
    t.description ??= f.description;
    return Promise.resolve();
  }
  userRuleCategoryId(_u: string, key: string) {
    return Promise.resolve(this.rules.get(key) ?? null);
  }
  cachedSuggestion(key: string) {
    return Promise.resolve(this.cache.get(key) ?? null);
  }
  saveSuggestion(key: string, s: AiSuggestion) {
    this.cache.set(key, s);
    return Promise.resolve();
  }
}

class FakeAi implements AiCategorizer {
  calls: AiCategorizeInput[] = [];
  constructor(private answer: AiSuggestion) {}
  categorize(input: AiCategorizeInput) {
    this.calls.push(input);
    return Promise.resolve(this.answer);
  }
}

const deps = { encrypt: (s: string) => Promise.resolve(`enc(${s.length})`) };

function req(id: string, receivedAt = addisDate(2026, 10, 5, 15, 0, 0), text = SMS[id].text): IngestRequest {
  return { userId: USER, channel: "shortcut", text, sender: SMS[id].sender, receivedAt };
}

Deno.test("telebirr transfer: created, money to a person goes to review", async () => {
  const store = new MemoryStore();
  const r = await ingestMessage(store, req("T1"), deps);
  assert(r.status === "created");
  assertEquals(r.reviewReason, "low_category_confidence");

  const tx = store.txs[0];
  assertEquals(tx.amount, 47_500);
  assertEquals(tx.fee, 200);
  assertEquals(tx.counterpartyName, "Hana Girma");
  assertEquals(tx.categoryKey, "transfer");
  assertEquals(tx.status, "needs_review");
  assertEquals(store.accounts[0].institution, "telebirr");
  assertEquals([...store.raw.values()][0].parseStatus, "parsed");
});

Deno.test("the same SMS twice is an exact duplicate", async () => {
  const store = new MemoryStore();
  const first = await ingestMessage(store, req("T1"), deps);
  const second = await ingestMessage(store, req("T1"), deps);
  assert(first.status === "created");
  assertEquals(second, { status: "duplicate", transactionId: first.transactionId });
  assertEquals(store.txs.length, 1);
});

Deno.test("two CBE debits of the same amount with different receipts are both kept", async () => {
  const store = new MemoryStore();
  const other = SMS.C5.text.replace("v2-hfHCxHe5Wx4RbJt9Np", "v2-hfHCxHe5Wx4RbJt0Zz");
  await ingestMessage(store, req("C5"), deps);
  const r = await ingestMessage(store, req("C5", undefined, other), deps);
  assert(r.status === "created");
  assertNotEquals(r.reviewReason, "possible_duplicate");
  assertEquals(store.txs.length, 2);
});

Deno.test("CBE accounts are matched by masked number", async () => {
  const store = new MemoryStore();
  await ingestMessage(store, req("C1"), deps);
  await ingestMessage(store, req("C2"), deps);
  assertEquals(store.accounts.length, 1);
  assertEquals(store.accounts[0].masked, "****1234");
});

Deno.test("business payee matched by the merchant map is confirmed", async () => {
  const store = new MemoryStore();
  const r = await ingestMessage(store, req("C4"), deps);
  assert(r.status === "created");
  assertEquals(r.reviewReason, null);
  assertEquals(store.txs[0].categoryKey, "health");
  assertEquals(store.txs[0].counterpartyKind, "business");
});

Deno.test("CBE Fast Loan notice enriches the debit it explains", async () => {
  const store = new MemoryStore();
  const debit = await ingestMessage(store, req("C6", addisDate(2026, 9, 30, 10, 0, 0)), deps);
  const notice = await ingestMessage(store, req("C8", addisDate(2026, 9, 30, 10, 1, 0)), deps);
  assert(debit.status === "created");
  assertEquals(notice, { status: "enriched", transactionId: debit.transactionId });
  assertEquals(store.txs.length, 1);
  assertEquals(store.txs[0].counterpartyName, "CBE Fast Loan");
  assertEquals(store.txs[0].description, "CBE Fast Loan repayment (loan 175904)");
});

Deno.test("CBE Fast Loan notice first, debit second: debit is flagged as a possible duplicate", async () => {
  const store = new MemoryStore();
  const notice = await ingestMessage(store, req("C8", addisDate(2026, 9, 30, 10, 0, 0)), deps);
  const debit = await ingestMessage(store, req("C6", addisDate(2026, 9, 30, 10, 2, 0)), deps);
  assert(notice.status === "created" && debit.status === "created");
  assertEquals(debit.reviewReason, "possible_duplicate");
  assertEquals(store.txs[1].duplicateOf, notice.transactionId);
});

Deno.test("OTP and Endekise are stored as ignored, no transaction", async () => {
  const store = new MemoryStore();
  assertEquals(await ingestMessage(store, req("O2"), deps), { status: "ignored", reason: "otp" });
  assertEquals(await ingestMessage(store, req("T6"), deps), { status: "ignored", reason: "credit_line_drawdown" });
  assertEquals(store.txs.length, 0);
  assert([...store.raw.values()].every((r) => r.parseStatus === "ignored"));
});

Deno.test("raw text is only handed to the store encrypted", async () => {
  const store = new MemoryStore();
  await ingestMessage(store, req("T1"), deps);
  const stored = [...store.raw.values()][0].ciphertext;
  assert(!stored.includes("Hana"), "plaintext must not reach the store");
});

Deno.test("a user's rule beats everything, including AI", async () => {
  const store = new MemoryStore();
  store.rules.set("meron tesfaye bekele", "cat-education");
  const ai = new FakeAi({ categoryKey: "food.restaurants", confidence: 0.95, model: "fake" });
  const r = await ingestMessage(store, req("T5"), { ...deps, ai });
  assert(r.status === "created");
  assertEquals(store.txs[0].categoryId, "cat-education");
  assertEquals(store.txs[0].categorySource, "rule");
  assertEquals(ai.calls.length, 0);
});

Deno.test("AI categorizes an unknown merchant once, then the cache answers", async () => {
  const store = new MemoryStore();
  const ai = new FakeAi({ categoryKey: "education", confidence: 0.9, model: "fake" });
  const first = await ingestMessage(store, req("T5"), { ...deps, ai });
  const again = SMS.T5.text.replaceAll("DJ54RW2HXK", "DJ59AAAAAA");
  const second = await ingestMessage(store, req("T5", undefined, again), { ...deps, ai });

  assert(first.status === "created" && second.status === "created");
  assertEquals(first.reviewReason, null);
  assertEquals(store.txs[0].categoryKey, "education");
  assertEquals(store.txs[0].categorySource, "ai");
  assertEquals(ai.calls.length, 1, "second payment uses the cache");

  // Privacy: only the merchant, type, amount, description and category list.
  assertEquals(Object.keys(ai.calls[0]).sort(), ["amountEtb", "categoryKeys", "counterparty", "description", "type"]);
  assertEquals(ai.calls[0].counterparty, "Meron Tesfaye Bekele");
});

Deno.test("an unsure AI guess goes to review", async () => {
  const store = new MemoryStore();
  const ai = new FakeAi({ categoryKey: "shopping", confidence: 0.55, model: "fake" });
  const r = await ingestMessage(store, req("T5"), { ...deps, ai });
  assert(r.status === "created");
  assertEquals(r.reviewReason, "low_category_confidence");
  assertEquals(store.txs[0].categoryKey, "shopping");
});

Deno.test("when the AI call fails, the transaction is still saved for review and nothing is cached", async () => {
  const store = new MemoryStore();
  const ai: AiCategorizer = { categorize: () => Promise.reject(new Error("OpenAI 500")) };
  const r = await ingestMessage(store, req("T5"), { ...deps, ai });
  assert(r.status === "created");
  assertEquals(r.reviewReason, "low_category_confidence");
  assertEquals(store.txs[0].categoryKey, "other");
  assertEquals(store.txs[0].categorySource, "fallback");
  assertEquals(store.cache.size, 0);
});

Deno.test("AI is never asked about money sent to a person", async () => {
  const store = new MemoryStore();
  const ai = new FakeAi({ categoryKey: "food", confidence: 0.99, model: "fake" });
  await ingestMessage(store, req("T1"), { ...deps, ai });
  await ingestMessage(store, req("C2"), { ...deps, ai });
  assertEquals(ai.calls.length, 0);
});

Deno.test("raw message encryption round-trips and is not plaintext", async () => {
  const key = await importKey(btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))));
  const sealed = await encryptText(key, SMS.C1.text);
  assert(sealed.startsWith("v1:"));
  assert(!sealed.includes("Tekle"));
  assertEquals(await decryptText(key, sealed), SMS.C1.text);
});
