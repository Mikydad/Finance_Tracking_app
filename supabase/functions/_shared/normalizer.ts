// Turns parser output into display names and matching keys.

import type { CounterpartyKind } from "./types.ts";

const BUSINESS_WORDS =
  /\b(p\.?l\.?c|s\.?c|plc|ltd|share company|services?|trading|enterprise|import|export|hotel|cafe|caf[eé]|restaurant|supermarket|market|pharmacy|clinic|hospital|bank|banks|payable|telecom|school|academy|university|college|shop|store|mart|agency|company|co\.)\b/i;

/** "YONAS ALEMU" -> "Yonas Alemu", "ABC SHOP" -> "Abc Shop". Mixed-case
 * names are already how the bank wants them shown and are left alone. */
export function displayName(raw: string | null): string | null {
  if (!raw) return null;
  const name = raw.replace(/\s+/g, " ").trim();
  if (!name) return null;
  const letters = name.replace(/[^A-Za-z]/g, "");
  const shouting = letters.length > 0 && (letters === letters.toUpperCase() || letters === letters.toLowerCase());
  if (!shouting) return name;
  return name.toLowerCase().replace(/(^|[\s(/-])([a-z])/g, (_, sep: string, c: string) => sep + c.toUpperCase());
}

/** Lowercase, punctuation-free key used for rules, the AI cache and dedup. */
export function matchKey(raw: string | null): string | null {
  if (!raw) return null;
  const key = raw.toLowerCase().replace(/[^a-z0-9ሀ-፿]+/g, " ").trim();
  return key || null;
}

/** Keeps the parser's answer when it has one; otherwise guesses from the name. */
export function counterpartyKind(name: string | null, fromParser: CounterpartyKind): CounterpartyKind {
  if (fromParser !== "unknown") return fromParser;
  if (!name) return "unknown";
  if (BUSINESS_WORDS.test(name)) return "business";
  const words = name.trim().split(/\s+/);
  // Ethiopian personal names: given name + father's (+ grandfather's) name.
  if (words.length >= 2 && words.length <= 4 && words.every((w) => /^[A-Za-z][A-Za-z/.'-]*$/.test(w))) {
    return "person";
  }
  return "unknown";
}
