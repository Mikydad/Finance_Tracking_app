// telebirr (Ethio telecom, sender "127"). Samples T1–T7 in sms_samples.md.

import type { MessageInput, ParseResult, TransactionParser } from "../types.ts";
import { addisDate, AMOUNT, amountFrom, draft, squash } from "./util.ts";

const DATE = String.raw`(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2}):(\d{2})`;

// T1–T4: "You have transferred ETB 475.00 to Hana Girma (2519****1122) on 05/10/2026 21:05:39."
const TRANSFERRED = new RegExp(
  String.raw`You have transferred ETB ?${AMOUNT} to (.+?) ?\(([\d*]+)\) on ${DATE}`,
);
// T5: "You have paid ETB 5,200.00 for Service Fee from 412763 - MERON TESFAYE BEKELE on 05/10/2026 14:37:10."
const PAID = new RegExp(
  String.raw`You have paid ETB ?${AMOUNT} for (.+?) from (\d+) ?- ?(.+?) on ${DATE}`,
);
// Not in the samples yet; assumed mirror of the transfer template, so it is
// parsed with low confidence and goes to review.
const RECEIVED = new RegExp(
  String.raw`You have received ETB ?${AMOUNT} from (.+?) ?\(([\d*]+)\) on ${DATE}`,
);

const TXN_NUMBER = /transaction number is ?([A-Z0-9]{8,12})\b/;
const SERVICE_FEE = new RegExp(String.raw`service fee is ETB ?${AMOUNT}`);
const VAT = new RegExp(String.raw`VAT on the service fee is ETB ?${AMOUNT}`);

function dateFrom(m: RegExpMatchArray, i: number): Date {
  const [d, mo, y, h, mi, s] = m.slice(i, i + 6).map(Number);
  return addisDate(y, mo, d, h, mi, s);
}

export const telebirrParser: TransactionParser = {
  name: "telebirr",
  version: 1,

  canParse(msg: MessageInput) {
    return msg.sender === "127" || /telebirr|ethiotelecom/i.test(msg.text);
  },

  parse(msg: MessageInput): ParseResult | null {
    const text = squash(msg.text);
    const meta = { parser: this.name, version: this.version };

    // T6: Endekise is a credit line; the borrowed money funds a transfer that
    // is reported in its own message, so this is not income.
    if (/using Endekise/i.test(text)) {
      return { status: "ignored", ...meta, reason: "credit_line_drawdown" };
    }

    const reference = text.match(TXN_NUMBER)?.[1] ?? null;
    const fee = (amountFrom(text.match(SERVICE_FEE), 1) ?? 0) + (amountFrom(text.match(VAT), 1) ?? 0);

    let m = text.match(TRANSFERRED);
    if (m) {
      return {
        status: "parsed",
        ...meta,
        tx: draft({
          type: "expense",
          amount: amountFrom(m, 1)!,
          fee,
          institution: "telebirr",
          occurredAt: dateFrom(m, 5),
          counterpartyName: m[3],
          counterpartyAccount: m[4],
          counterpartyKind: "person",
          referenceId: reference,
        }),
      };
    }

    m = text.match(PAID);
    if (m) {
      return {
        status: "parsed",
        ...meta,
        tx: draft({
          type: "expense",
          amount: amountFrom(m, 1)!,
          fee,
          institution: "telebirr",
          occurredAt: dateFrom(m, 6),
          counterpartyName: m[5],
          counterpartyAccount: m[4],
          counterpartyKind: "business",
          description: m[3],
          referenceId: reference,
        }),
      };
    }

    m = text.match(RECEIVED);
    if (m) {
      return {
        status: "parsed",
        ...meta,
        tx: draft({
          type: "income",
          amount: amountFrom(m, 1)!,
          institution: "telebirr",
          occurredAt: dateFrom(m, 5),
          counterpartyName: m[3],
          counterpartyAccount: m[4],
          counterpartyKind: "person",
          referenceId: reference,
          confidence: 0.6,
        }),
      };
    }

    // T7: airtime/package bonus notices.
    if (/bonus/i.test(text)) {
      return { status: "ignored", ...meta, reason: "bonus" };
    }

    return null;
  },
};
