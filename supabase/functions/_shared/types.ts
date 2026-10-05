// Shared types for the ingestion pipeline. Amounts are always integers in
// santim (minor units): 2,500.00 ETB = 250000.

export type Institution =
  | "cbe"
  | "cbo"
  | "awash"
  | "dashen"
  | "abyssinia"
  | "telebirr"
  | "cash"
  | "other";

export type TransactionType = "expense" | "income" | "transfer";

export type CounterpartyKind = "person" | "business" | "unknown";

/** What a message describes, beyond a plain debit or credit. */
export type ParsedKind =
  /** A normal money movement on the user's account. */
  | "transaction"
  /** A notice that explains a debit the bank also reports separately
   * (CBE Fast Loan repayment). Enriches the matching debit if one exists. */
  | "debit_notice";

export interface ParsedTransaction {
  kind: ParsedKind;
  type: TransactionType;
  amount: number;
  /** Charges on top of amount (service fee + VAT + other levies), in santim. */
  fee: number;
  currency: "ETB";
  /** When the bank says it happened; null when the message has no date
   * (CBE, BOA), in which case the SMS arrival time is used. */
  occurredAt: Date | null;
  institution: Institution;
  /** The user's own account, normalized to "****1234". Null for wallets
   * (telebirr) or when the message doesn't say. */
  accountMasked: string | null;
  counterpartyName: string | null;
  counterpartyAccount: string | null;
  counterpartyKind: CounterpartyKind;
  /** Free text such as "Service Fee" or "CBE Fast Loan repayment". */
  description: string | null;
  /** The bank's own transaction reference, used for exact duplicate checks. */
  referenceId: string | null;
  /** 0..1, how sure the parser is that it read the message correctly. */
  confidence: number;
}

export type ParseResult =
  | { status: "parsed"; parser: string; version: number; tx: ParsedTransaction }
  | { status: "ignored"; parser: string; version: number; reason: IgnoreReason }
  | { status: "unrecognized" };

export type IgnoreReason =
  | "otp"
  | "promo"
  | "bonus"
  | "security_notice"
  | "credit_line_drawdown"
  | "no_amount";

export interface MessageInput {
  text: string;
  /** SMS sender id when known (e.g. "127", "CBE", "CBO", "BOA"). */
  sender?: string | null;
  /** When the phone received the message. */
  receivedAt: Date;
}

export interface TransactionParser {
  name: string;
  version: number;
  /** Cheap check: does this message look like it came from this bank? */
  canParse(msg: MessageInput): boolean;
  /** Full parse. Returning null means "mine, but not a template I know";
   * the registry then falls through to the generic parser. */
  parse(msg: MessageInput): ParseResult | null;
}
