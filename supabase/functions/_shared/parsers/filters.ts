// Messages that are never transactions, checked after the bank parsers and
// before the generic parser: OTPs (O2), bonuses (T7), Amharic promos and
// notices (C9, B5, B6), security warnings.

import type { IgnoreReason, MessageInput } from "../types.ts";
import { hasEthiopic } from "./util.ts";

const MONEY_VERB = /\b(debited|credited|transferred|received|paid|deposited|withdrawn)\b/i;

export function rejectReason(msg: MessageInput): IgnoreReason | null {
  const text = msg.text;
  if (/one[- ]time password|\bOTP\b|verification code/i.test(text)) return "otp";
  if (/\bbonus\b/i.test(text) && !MONEY_VERB.test(text)) return "bonus";
  if (/phishing|fraud|scam|never share your|do not share your/i.test(text) && !MONEY_VERB.test(text)) {
    return "security_notice";
  }
  // Bank messages with real money movement are in English; Ethiopic-script
  // texts seen so far are promos and notices.
  if (hasEthiopic(text) && !MONEY_VERB.test(text)) return "promo";
  return null;
}
