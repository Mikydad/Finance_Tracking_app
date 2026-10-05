// Small helpers shared by the bank parsers.

import type { ParsedTransaction } from "../types.ts";

/** Ethiopia is UTC+3 all year (no daylight saving). */
const ADDIS_OFFSET_MINUTES = 3 * 60;

/** Matches the number part of an amount: "100,000.00", "100000.00",
 * "25000.0", "20", "1523.40". */
export const AMOUNT = String.raw`(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?`;

/** "ETB 100,000.00", "ETB100000.00", "ETB 25000.0." (trailing period is
 * sentence punctuation), "ETB-98,539.15". */
export const ETB_AMOUNT = String.raw`ETB\s?-?` + AMOUNT;

/** Converts captured amount groups to santim. */
export function toSantim(whole: string, fraction: string | undefined): number {
  const units = Number(whole.replaceAll(",", ""));
  const frac = (fraction ?? "").padEnd(2, "0").slice(0, 2);
  return units * 100 + Number(frac || "0");
}

/** Parses a single amount string ("ETB 2,500.00", "5023.00") to santim. */
export function parseAmount(text: string): number | null {
  const m = text.match(new RegExp(AMOUNT));
  return m ? toSantim(m[1], m[2]) : null;
}

/** Runs `pattern` and converts the named amount groups to santim. The
 * pattern must capture whole/fraction as consecutive groups starting at
 * `group`. */
export function amountFrom(m: RegExpMatchArray | null, group: number): number | null {
  if (!m || m[group] === undefined) return null;
  return toSantim(m[group], m[group + 1]);
}

/** "1********1234" -> "****1234", "7*****45" -> "****45", "****6612" -> "****6612". */
export function normalizeMasked(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const m = raw.match(/\*+\s*(\d{2,6})\s*$/);
  if (m) return "****" + m[1];
  const digits = raw.replace(/\D/g, "");
  return digits.length >= 2 ? "****" + digits.slice(-4) : null;
}

/** Builds a Date from Addis Ababa local wall-clock parts. */
export function addisDate(
  year: number,
  month: number, // 1-12
  day: number,
  hour = 0,
  minute = 0,
  second = 0,
): Date {
  const utc = Date.UTC(year, month - 1, day, hour, minute, second);
  return new Date(utc - ADDIS_OFFSET_MINUTES * 60_000);
}

/** The Addis Ababa calendar date (yyyy-mm-dd) of an instant. */
export function addisDay(d: Date): string {
  return new Date(d.getTime() + ADDIS_OFFSET_MINUTES * 60_000).toISOString().slice(0, 10);
}

const MONTHS: Record<string, number> = {
  jan: 1,
  feb: 2,
  mar: 3,
  apr: 4,
  may: 5,
  jun: 6,
  jul: 7,
  aug: 8,
  sep: 9,
  oct: 10,
  nov: 11,
  dec: 12,
};

export function monthNumber(name: string): number | null {
  return MONTHS[name.slice(0, 3).toLowerCase()] ?? null;
}

/** Collapses runs of whitespace so templates with stray double spaces match. */
export function squash(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

/** Ethiopic script (Amharic, Afaan Oromo in Ge'ez, Tigrinya). */
export function hasEthiopic(text: string): boolean {
  return /[ሀ-፿]/.test(text);
}

/** A ParsedTransaction with neutral defaults, for parsers to fill in. */
export function draft(
  fields: Pick<ParsedTransaction, "type" | "amount" | "institution"> & Partial<ParsedTransaction>,
): ParsedTransaction {
  return {
    kind: "transaction",
    fee: 0,
    currency: "ETB",
    occurredAt: null,
    accountMasked: null,
    counterpartyName: null,
    counterpartyAccount: null,
    counterpartyKind: "unknown",
    description: null,
    referenceId: null,
    confidence: 0.95,
    ...fields,
  };
}
