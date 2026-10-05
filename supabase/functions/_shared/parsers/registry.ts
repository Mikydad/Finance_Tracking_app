// Parser registry: bank parsers first (strict templates), then the
// never-a-transaction filters, then the generic fallback.

import type { MessageInput, ParseResult, TransactionParser } from "../types.ts";
import { boaParser } from "./boa.ts";
import { cboParser } from "./cbo.ts";
import { cbeParser } from "./cbe.ts";
import { rejectReason } from "./filters.ts";
import { genericParser } from "./generic.ts";
import { telebirrParser } from "./telebirr.ts";

export const BANK_PARSERS: TransactionParser[] = [telebirrParser, cbeParser, cboParser, boaParser];

export function parseMessage(msg: MessageInput, parsers = BANK_PARSERS): ParseResult {
  for (const parser of parsers) {
    if (!parser.canParse(msg)) continue;
    const result = parser.parse(msg);
    if (result) return result;
  }

  const reason = rejectReason(msg);
  if (reason) return { status: "ignored", parser: "filters", version: 1, reason };

  return genericParser.parse(msg) ?? { status: "unrecognized" };
}
