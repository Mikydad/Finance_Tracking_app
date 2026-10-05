import { assert, assertEquals } from "jsr:@std/assert@1";
import { parseMessage } from "../parsers/registry.ts";
import { addisDate, parseAmount } from "../parsers/util.ts";
import type { IgnoreReason, ParsedTransaction } from "../types.ts";
import { SMS } from "./fixtures.ts";

// Arrival time used for templates without a date: 5 Oct 2026, 15:00 in Addis.
const RECEIVED_AT = addisDate(2026, 10, 5, 15, 0, 0);

function parse(id: string, receivedAt = RECEIVED_AT) {
  const f = SMS[id];
  return parseMessage({ text: f.text, sender: f.sender, receivedAt });
}

function parsed(id: string, receivedAt = RECEIVED_AT): ParsedTransaction & { parser: string } {
  const r = parse(id, receivedAt);
  assert(r.status === "parsed", `${id} should parse, got ${JSON.stringify(r)}`);
  return { ...r.tx, parser: r.parser };
}

function expectIgnored(id: string, reason: IgnoreReason) {
  const r = parse(id);
  assert(r.status === "ignored", `${id} should be ignored, got ${JSON.stringify(r)}`);
  assertEquals(r.reason, reason, id);
}

Deno.test("amount formats seen in real messages", () => {
  assertEquals(parseAmount("ETB 100,000.00"), 10_000_000);
  assertEquals(parseAmount("ETB100000.00"), 10_000_000);
  assertEquals(parseAmount("ETB 25000.0."), 2_500_000);
  assertEquals(parseAmount("ETB20"), 2_000);
  assertEquals(parseAmount("5023.00"), 502_300);
  assertEquals(parseAmount("ETB 0.26"), 26);
});

// ---------------------------------------------------------------------------
// telebirr
// ---------------------------------------------------------------------------

Deno.test("telebirr T1–T4: transfers to people, with fee + VAT", () => {
  const cases: [string, number, number, string, string, string][] = [
    ["T1", 47_500, 200, "Hana Girma", "DJ50KQ3RTA", "2026-10-05T18:05:39.000Z"],
    ["T2", 58_000, 400, "Hana Girma", "DJ40MB7WXE", "2026-10-04T17:28:26.000Z"],
    ["T3", 6_000, 100, "YONAS ALEMU", "DJ42PH8CNV", "2026-10-04T16:32:22.000Z"],
    ["T4", 50_000, 200, "SAMUEL HAILE", "DJ41TZ6LMQ", "2026-10-04T17:24:56.000Z"],
  ];
  for (const [id, amount, fee, name, ref, at] of cases) {
    const tx = parsed(id);
    assertEquals(tx.parser, "telebirr", id);
    assertEquals(tx.type, "expense", id);
    assertEquals(tx.amount, amount, id);
    assertEquals(tx.fee, fee, id);
    assertEquals(tx.counterpartyName, name, id);
    assertEquals(tx.counterpartyKind, "person", id);
    assertEquals(tx.referenceId, ref, id);
    assertEquals(tx.occurredAt?.toISOString(), at, id);
    assertEquals(tx.institution, "telebirr", id);
    assertEquals(tx.accountMasked, null, id);
  }
  assertEquals(parsed("T1").counterpartyAccount, "2519****1122");
});

Deno.test("telebirr T5: merchant payment", () => {
  const tx = parsed("T5");
  assertEquals(tx.type, "expense");
  assertEquals(tx.amount, 520_000);
  assertEquals(tx.fee, 0);
  assertEquals(tx.counterpartyName, "MERON TESFAYE BEKELE");
  assertEquals(tx.counterpartyAccount, "412763");
  assertEquals(tx.counterpartyKind, "business");
  assertEquals(tx.description, "Service Fee");
  assertEquals(tx.referenceId, "DJ54RW2HXK");
  assertEquals(tx.occurredAt?.toISOString(), "2026-10-05T11:37:10.000Z");
});

Deno.test("telebirr T6: Endekise credit drawdown is not income", () => {
  expectIgnored("T6", "credit_line_drawdown");
});

Deno.test("telebirr T7: bonus notice is ignored", () => {
  expectIgnored("T7", "bonus");
});

Deno.test("telebirr received (assumed template) goes to review", () => {
  const tx = parsed("T_RECEIVED");
  assertEquals(tx.type, "income");
  assertEquals(tx.amount, 100_000);
  assertEquals(tx.counterpartyName, "Hana Girma");
  assert(tx.confidence < 0.7);
});

// ---------------------------------------------------------------------------
// CBE
// ---------------------------------------------------------------------------

Deno.test("CBE C1, C3: received from a person", () => {
  const c1 = parsed("C1");
  assertEquals(c1.parser, "cbe");
  assertEquals(c1.type, "income");
  assertEquals(c1.amount, 10_000_000);
  assertEquals(c1.counterpartyName, "Tekle G/mariam Berhe");
  assertEquals(c1.counterpartyAccount, "****5521");
  assertEquals(c1.accountMasked, "****1234");
  assertEquals(c1.referenceId, "v2-hfHCxHa8Rk2LmPq7Wn");
  assertEquals(c1.occurredAt, null, "CBE has no date; arrival time is used");

  const c3 = parsed("C3");
  assertEquals(c3.amount, 2_500_000);
  assertEquals(c3.counterpartyName, "Selam Worku Abebe");
});

Deno.test("CBE C2, C4: transfers out, fee from the total", () => {
  const c2 = parsed("C2");
  assertEquals(c2.type, "expense");
  assertEquals(c2.amount, 10_000_000);
  assertEquals(c2.fee, 600);
  assertEquals(c2.counterpartyName, "Kidus Alemayehu Desta");
  assertEquals(c2.accountMasked, "****1234");
  assertEquals(c2.counterpartyAccount, "****3307");

  const c4 = parsed("C4");
  assertEquals(c4.amount, 210_000);
  assertEquals(c4.fee, 120);
  assertEquals(c4.counterpartyName, "Nova Health Services P.l.c");
});

Deno.test("CBE C5, C6: generic debit without counterparty", () => {
  const c5 = parsed("C5");
  assertEquals(c5.type, "expense");
  assertEquals(c5.amount, 2_500_000);
  assertEquals(c5.fee, 1_800);
  assertEquals(c5.counterpartyName, null);
  assertEquals(c5.accountMasked, "****1234");

  const c6 = parsed("C6");
  assertEquals(c6.amount, 1_062_000);
  assertEquals(c6.fee, 0);
});

Deno.test("CBE C7: branch credit", () => {
  const c7 = parsed("C7");
  assertEquals(c7.type, "income");
  assertEquals(c7.amount, 800_000);
  assertEquals(c7.accountMasked, "****1234");
  assertEquals(c7.referenceId, "FT26273XKD4P");
  assertEquals(c7.description, "Branch deposit");
});

Deno.test("CBE C8: Fast Loan repayment is a notice for the matching debit", () => {
  // Arrived on 30 Sep: keeps the arrival time.
  const sameDay = addisDate(2026, 9, 30, 10, 12, 0);
  const c8 = parsed("C8", sameDay);
  assertEquals(c8.kind, "debit_notice");
  assertEquals(c8.amount, 1_062_000);
  assertEquals(c8.counterpartyName, "CBE Fast Loan");
  assertEquals(c8.occurredAt, null);

  // Arrived later: uses the stated date at noon.
  const later = parsed("C8", RECEIVED_AT);
  assertEquals(later.occurredAt?.toISOString(), "2026-09-30T09:00:00.000Z");
});

Deno.test("CBE C9: Amharic greeting is ignored", () => {
  expectIgnored("C9", "promo");
});

// ---------------------------------------------------------------------------
// CBO
// ---------------------------------------------------------------------------

Deno.test("CBO O1: debit with fee, reference and date", () => {
  const o1 = parsed("O1");
  assertEquals(o1.parser, "cbo");
  assertEquals(o1.type, "expense");
  assertEquals(o1.amount, 500_000);
  assertEquals(o1.fee, 2_300);
  assertEquals(o1.accountMasked, "****6612");
  assertEquals(o1.referenceId, "FT26271MQ8RD");
  assertEquals(o1.counterpartyName, "OMNI Banks Payable");
  assertEquals(o1.occurredAt?.toISOString(), "2026-09-28T11:58:00.000Z");
});

Deno.test("CBO O1 is recognized by template even without the sender", () => {
  const r = parseMessage({ text: SMS.O1.text, receivedAt: RECEIVED_AT });
  assert(r.status === "parsed" && r.parser === "cbo");
});

Deno.test("CBO O2: OTP is ignored", () => {
  expectIgnored("O2", "otp");
});

// ---------------------------------------------------------------------------
// BOA
// ---------------------------------------------------------------------------

Deno.test("BOA B1, B2: debits", () => {
  const b1 = parsed("B1");
  assertEquals(b1.parser, "boa");
  assertEquals(b1.type, "expense");
  assertEquals(b1.amount, 2_501_800);
  assertEquals(b1.accountMasked, "****45");
  assertEquals(b1.referenceId, "FT26274R7KPN81047");
  assertEquals(b1.institution, "abyssinia");

  assertEquals(parsed("B2").amount, 201_080);
});

Deno.test("BOA B3: credit from another account", () => {
  const b3 = parsed("B3");
  assertEquals(b3.type, "income");
  assertEquals(b3.amount, 18_680);
  assertEquals(b3.description, "Credit Int From Another Acc");
  assertEquals(b3.referenceId, "318264095-20260930");
});

Deno.test("BOA B4: debit with a cut-off opening line", () => {
  const b4 = parsed("B4_FULL");
  assertEquals(b4.type, "expense");
  assertEquals(b4.amount, 150_000);
  assertEquals(b4.referenceId, "FT26264QW8ER81047");

  // The transcription itself lost the amount, so there is nothing to record.
  const partial = parse("B4");
  assert(partial.status !== "parsed");
});

Deno.test("BOA B5, B6: Amharic promo and fraud warning are ignored", () => {
  expectIgnored("B5", "promo");
  expectIgnored("B6", "promo");
});

// ---------------------------------------------------------------------------
// Generic
// ---------------------------------------------------------------------------

Deno.test("unknown bank falls back to the generic parser with low confidence", () => {
  const tx = parsed("UNKNOWN_BANK");
  assertEquals(tx.parser, "generic");
  assertEquals(tx.type, "expense");
  assertEquals(tx.amount, 75_000);
  assertEquals(tx.referenceId, "TT26278ABC12");
  assert(tx.confidence < 0.7);
});

Deno.test("plain chat text is not a transaction", () => {
  const r = parseMessage({ text: "See you at 5 near the cafe", receivedAt: RECEIVED_AT });
  assert(r.status === "ignored" || r.status === "unrecognized");
});
