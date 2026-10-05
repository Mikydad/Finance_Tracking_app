// Two-tier duplicate detection (build plan 2.5):
// - exact: the same bank reference on the same account -> drop the message.
// - probable: same direction and amount close in time -> keep, but flag for review.
// A debit notice (CBE Fast Loan repayment) instead enriches the debit it explains.

import type { ParsedKind, TransactionType } from "./types.ts";

export interface DedupCandidate {
  id: string;
  type: TransactionType;
  amount: number;
  occurredAt: Date;
  referenceId: string | null;
  counterpartyKey: string | null;
}

export interface DedupInput {
  kind: ParsedKind;
  type: TransactionType;
  amount: number;
  occurredAt: Date;
  referenceId: string | null;
  counterpartyKey: string | null;
}

export type DedupDecision =
  | { kind: "none" }
  | { kind: "exact"; id: string }
  | { kind: "probable"; id: string }
  | { kind: "enrich"; id: string };

const HOUR = 3_600_000;
export const PROBABLE_WINDOW_MS = 3 * HOUR;
export const NOTICE_WINDOW_MS = 3 * 24 * HOUR;

export function decideDuplicate(tx: DedupInput, candidates: DedupCandidate[]): DedupDecision {
  if (tx.referenceId) {
    const same = candidates.find((c) => c.referenceId === tx.referenceId);
    if (same) return { kind: "exact", id: same.id };
  }

  const near = (c: DedupCandidate, window: number) =>
    c.type === tx.type && c.amount === tx.amount &&
    Math.abs(c.occurredAt.getTime() - tx.occurredAt.getTime()) <= window;

  const closest = (list: DedupCandidate[]) =>
    list.sort((a, b) =>
      Math.abs(a.occurredAt.getTime() - tx.occurredAt.getTime()) -
      Math.abs(b.occurredAt.getTime() - tx.occurredAt.getTime())
    )[0];

  if (tx.kind === "debit_notice") {
    const debits = candidates.filter((c) => near(c, NOTICE_WINDOW_MS));
    // Prefer a debit that doesn't say who it was for yet.
    const target = closest(debits.filter((c) => !c.counterpartyKey)) ?? closest(debits);
    return target ? { kind: "enrich", id: target.id } : { kind: "none" };
  }

  const probable = candidates.filter((c) =>
    near(c, PROBABLE_WINDOW_MS) &&
    // Two different bank references mean two real transactions.
    !(c.referenceId && tx.referenceId) &&
    (!c.counterpartyKey || !tx.counterpartyKey || c.counterpartyKey === tx.counterpartyKey)
  );
  const match = closest(probable);
  return match ? { kind: "probable", id: match.id } : { kind: "none" };
}
