// Bank of Abyssinia (sender "BOA"). Samples B1–B6 in sms_samples.md.
// No transaction date in the body, so the SMS arrival time is used. The
// match is not anchored to "Dear ...", because one real debit (B4) arrived
// with a different opening line.

import type { MessageInput, ParseResult, TransactionParser } from "../types.ts";
import { AMOUNT, amountFrom, draft, normalizeMasked, squash } from "./util.ts";

const MOVED = new RegExp(
  String.raw`your account ([\d*]{4,}) was (debited|credited) with ETB ?${AMOUNT}(?:\.? by (.+?)\. Available)?`,
  "i",
);
const TRX = /slip\/\?trx=([\w-]+)/;

export const boaParser: TransactionParser = {
  name: "boa",
  version: 1,

  canParse(msg: MessageInput) {
    return msg.sender?.toUpperCase() === "BOA" || /bankofabyssinia|Bank of Abyssinia/i.test(msg.text);
  },

  parse(msg: MessageInput): ParseResult | null {
    const text = squash(msg.text);
    const m = text.match(MOVED);
    if (!m) return null;

    return {
      status: "parsed",
      parser: this.name,
      version: this.version,
      tx: draft({
        type: m[2].toLowerCase() === "debited" ? "expense" : "income",
        amount: amountFrom(m, 3)!,
        institution: "abyssinia",
        accountMasked: normalizeMasked(m[1]),
        description: m[5] ?? null,
        referenceId: text.match(TRX)?.[1] ?? null,
        confidence: 0.9,
      }),
    };
  },
};
