// Cooperative Bank of Oromia (sender "CBO"). Sample O1 in sms_samples.md.
// The message never names the bank, so the sender id or the exact template
// is what identifies it.

import type { MessageInput, ParseResult, TransactionParser } from "../types.ts";
import { addisDate, AMOUNT, amountFrom, draft, monthNumber, normalizeMasked, squash } from "./util.ts";

// O1: "Dear Customer your Account ****6612 has been Debited with ETB5000.00 Service Charge of ETB20
//      and VAT(15%) of ETB3.00 a Total amount of 5023.00 Ref: FT26271MQ8RD ON 28 SEP 2026 14:58
//      TO OMNI Banks Payable. Your Current Balance is ETB 142608.25."
const MOVED = new RegExp(
  String.raw`your Account ([\d*]{4,}) has been (Debited|Credited) with ETB ?${AMOUNT}`,
  "i",
);
const TOTAL = new RegExp(String.raw`Total amount of (?:ETB ?)?${AMOUNT}`, "i");
const REF = /Ref: ?(FT\w+)/i;
const WHEN = /\bON (\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2})/;
const COUNTERPARTY = /\b(?:TO|FROM) (.+?)\. Your Current Balance/;

export const cboParser: TransactionParser = {
  name: "cbo",
  version: 1,

  canParse(msg: MessageInput) {
    return msg.sender?.toUpperCase() === "CBO" ||
      /Cooperative Bank of Oromia|coopbank/i.test(msg.text) ||
      (MOVED.test(squash(msg.text)) && REF.test(msg.text));
  },

  parse(msg: MessageInput): ParseResult | null {
    const text = squash(msg.text);
    const m = text.match(MOVED);
    if (!m) return null;

    const debit = m[2].toLowerCase() === "debited";
    const amount = amountFrom(m, 3)!;
    const total = amountFrom(text.match(TOTAL), 1);

    let occurredAt: Date | null = null;
    const w = text.match(WHEN);
    const month = w ? monthNumber(w[2]) : null;
    if (w && month) {
      occurredAt = addisDate(Number(w[3]), month, Number(w[1]), Number(w[4]), Number(w[5]));
    }

    return {
      status: "parsed",
      parser: this.name,
      version: this.version,
      tx: draft({
        type: debit ? "expense" : "income",
        amount,
        fee: total !== null && total >= amount ? total - amount : 0,
        institution: "cbo",
        occurredAt,
        accountMasked: normalizeMasked(m[1]),
        counterpartyName: text.match(COUNTERPARTY)?.[1] ?? null,
        referenceId: text.match(REF)?.[1] ?? null,
        // Only the debit template has been seen so far.
        confidence: debit ? 0.95 : 0.6,
      }),
    };
  },
};
