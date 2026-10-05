// Commercial Bank of Ethiopia (sender "CBE"). Samples C1–C9 in sms_samples.md.
// CBE messages carry no transaction date, so the SMS arrival time is used.
// Balances are not read: one real sample printed a wrong negative balance.

import type { MessageInput, ParsedTransaction, ParseResult, TransactionParser } from "../types.ts";
import { addisDate, addisDay, AMOUNT, amountFrom, draft, monthNumber, normalizeMasked, squash } from "./util.ts";

const ACCT = String.raw`([\d*]{6,})`;

// C1, C3
const RECEIVED = new RegExp(
  String.raw`You have received ETB ?${AMOUNT} from account ${ACCT} \((.+?)\) to your account ${ACCT}`,
);
// C2, C4
const TRANSFERRED = new RegExp(
  String.raw`You have successfully transferred ETB ?${AMOUNT} from account ${ACCT} to account ${ACCT} \((.+?)\)\s?\.`,
);
// C5, C6: "A debit transaction of ETB 25000.0. has occurred on your account 1********1234."
const DEBIT = new RegExp(
  String.raw`A debit transaction of ETB ?${AMOUNT}\.? has occurred on your account ${ACCT}`,
);
// C7: "your Account 1********1234 has been credited with ETB 8000.00."
const CREDITED = new RegExp(String.raw`your Account ${ACCT} has been credited with ETB ?${AMOUNT}`, "i");
// C8: "ETB 10620.00 is paid on 30 Sep, 2026 for Loan Id 175904."
const LOAN_PAID = new RegExp(
  String.raw`ETB ?${AMOUNT} is paid on (\d{1,2}) ([A-Za-z]{3,9}),? (\d{4}) for Loan Id (\w+)`,
);

const TOTAL = new RegExp(String.raw`with total of ETB ?${AMOUNT}`);
const RECEIPT_SLUG = /mbreciept\.cbe\.com\.et\/([\w-]+)/;
const BRANCH_REF = /BranchReceipt\/(FT\w+?)(?:&|\s|$)/;

function feeFromTotal(text: string, amount: number): number {
  const total = amountFrom(text.match(TOTAL), 1);
  return total !== null && total >= amount ? total - amount : 0;
}

function reference(text: string): string | null {
  return text.match(RECEIPT_SLUG)?.[1] ?? text.match(BRANCH_REF)?.[1] ?? null;
}

export const cbeParser: TransactionParser = {
  name: "cbe",
  version: 1,

  canParse(msg: MessageInput) {
    return msg.sender?.toUpperCase() === "CBE" || /Banking with CBE|CBE Fast Loan|cbe\.com\.et/i.test(msg.text);
  },

  parse(msg: MessageInput): ParseResult | null {
    const text = squash(msg.text);
    const parsed = (tx: ParsedTransaction): ParseResult => ({
      status: "parsed",
      parser: this.name,
      version: this.version,
      tx,
    });

    let m = text.match(RECEIVED);
    if (m) {
      return parsed(draft({
        type: "income",
        amount: amountFrom(m, 1)!,
        institution: "cbe",
        counterpartyAccount: normalizeMasked(m[3]),
        counterpartyName: m[4],
        accountMasked: normalizeMasked(m[5]),
        referenceId: reference(text),
      }));
    }

    m = text.match(TRANSFERRED);
    if (m) {
      const amount = amountFrom(m, 1)!;
      return parsed(draft({
        type: "expense",
        amount,
        fee: feeFromTotal(text, amount),
        institution: "cbe",
        accountMasked: normalizeMasked(m[3]),
        counterpartyAccount: normalizeMasked(m[4]),
        counterpartyName: m[5],
        referenceId: reference(text),
      }));
    }

    m = text.match(DEBIT);
    if (m) {
      const amount = amountFrom(m, 1)!;
      return parsed(draft({
        type: "expense",
        amount,
        fee: feeFromTotal(text, amount),
        institution: "cbe",
        accountMasked: normalizeMasked(m[3]),
        referenceId: reference(text),
        // No counterparty in this template, so the category will need review.
        confidence: 0.9,
      }));
    }

    m = text.match(CREDITED);
    if (m) {
      return parsed(draft({
        type: "income",
        amount: amountFrom(m, 2)!,
        institution: "cbe",
        accountMasked: normalizeMasked(m[1]),
        description: /BranchReceipt/i.test(text) ? "Branch deposit" : null,
        referenceId: reference(text),
        confidence: 0.9,
      }));
    }

    m = text.match(LOAN_PAID);
    if (m && /Fast Loan/i.test(text)) {
      const day = Number(m[3]);
      const month = monthNumber(m[4]);
      const year = Number(m[5]);
      let occurredAt: Date | null = null;
      if (month) {
        const stated = addisDate(year, month, day, 12);
        // Date only: keep the arrival time when it is the same day.
        occurredAt = addisDay(stated) === addisDay(msg.receivedAt) ? null : stated;
      }
      return parsed(draft({
        kind: "debit_notice",
        type: "expense",
        amount: amountFrom(m, 1)!,
        institution: "cbe",
        occurredAt,
        counterpartyName: "CBE Fast Loan",
        counterpartyKind: "business",
        description: `CBE Fast Loan repayment (loan ${m[6]})`,
      }));
    }

    return null;
  },
};
