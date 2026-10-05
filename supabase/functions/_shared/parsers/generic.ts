// Fallback for banks without their own parser. Low confidence by design, so
// whatever it produces lands in the review queue.

import type { MessageInput, ParseResult, TransactionParser, TransactionType } from "../types.ts";
import { AMOUNT, draft, normalizeMasked, squash, toSantim } from "./util.ts";

const ETB_FIRST = new RegExp(String.raw`(?:ETB|Birr|Br\.?)\s?${AMOUNT}`, "i");
const ETB_AFTER = new RegExp(String.raw`${AMOUNT}\s?(?:ETB|Birr)\b`, "i");
const EXPENSE = /\b(debited|withdrawn|paid|sent|transferred|purchase[d]?)\b/i;
const INCOME = /\b(credited|received|deposited)\b/i;
const ACCOUNT = /\b(?:account|acct|a\/c)\.?\s?(?:no\.?\s?)?([\d*]{4,})/i;
const REF = /\b(?:Ref(?:erence)?|Txn ID|Transaction ID|transaction number is)[:.]?\s?([A-Z0-9]{6,})/i;

export const genericParser: TransactionParser = {
  name: "generic",
  version: 1,

  canParse() {
    return true;
  },

  parse(msg: MessageInput): ParseResult | null {
    const text = squash(msg.text);
    const meta = { parser: this.name, version: this.version };

    const am = text.match(ETB_FIRST) ?? text.match(ETB_AFTER);
    if (!am) return { status: "ignored", ...meta, reason: "no_amount" };

    const out = text.search(EXPENSE);
    const inc = text.search(INCOME);
    if (out < 0 && inc < 0) return null;
    const type: TransactionType = inc < 0 || (out >= 0 && out < inc) ? "expense" : "income";

    const amount = toSantim(am[1], am[2]);
    if (amount <= 0) return { status: "ignored", ...meta, reason: "no_amount" };

    return {
      status: "parsed",
      ...meta,
      tx: draft({
        type,
        amount,
        institution: "other",
        accountMasked: normalizeMasked(text.match(ACCOUNT)?.[1]),
        referenceId: text.match(REF)?.[1] ?? null,
        confidence: 0.5,
      }),
    };
  },
};
