// Picks a category for a parsed transaction (build plan 4.3):
//   1. the user's own rule for this counterparty (always wins)
//   2. built-in merchant map
//   3. shared AI cache for this merchant
//   4. AI call for unknown merchants (never for people, never raw SMS)
//   5. fallback with low confidence -> review queue

import type { CounterpartyKind, TransactionType } from "./types.ts";

export type CategorySource = "user" | "rule" | "merchant_map" | "keyword" | "ai" | "fallback";

export interface CategoryChoice {
  /** Default category key ("food.coffee") or null when a user rule points
   * straight at a category id. */
  categoryKey: string | null;
  categoryId: string | null;
  source: CategorySource;
  confidence: number;
}

export interface CategorizeInput {
  userId: string;
  type: TransactionType;
  amount: number;
  counterpartyName: string | null;
  counterpartyKey: string | null;
  counterpartyKind: CounterpartyKind;
  description: string | null;
}

export interface AiSuggestion {
  categoryKey: string;
  confidence: number;
  model: string;
}

/** What the AI step is allowed to see. No raw SMS, account numbers,
 * balances or the user's identity. */
export interface AiCategorizeInput {
  counterparty: string;
  type: TransactionType;
  amountEtb: number;
  description: string | null;
  categoryKeys: string[];
}

export interface AiCategorizer {
  categorize(input: AiCategorizeInput): Promise<AiSuggestion | null>;
}

export interface CategoryStore {
  userRuleCategoryId(userId: string, counterpartyKey: string): Promise<string | null>;
  cachedSuggestion(counterpartyKey: string): Promise<AiSuggestion | null>;
  saveSuggestion(counterpartyKey: string, suggestion: AiSuggestion): Promise<void>;
}

export const DEFAULT_CATEGORY_KEYS = [
  "food",
  "food.restaurants",
  "food.groceries",
  "food.coffee",
  "transport",
  "transport.taxi",
  "transport.fuel",
  "transport.public",
  "shopping",
  "bills",
  "bills.internet",
  "bills.phone",
  "bills.electricity",
  "entertainment",
  "health",
  "education",
  "family",
  "subscriptions",
  "income",
  "transfer",
  "other",
];

/** Common Ethiopian merchants and merchant words. Grows from real data. */
const MERCHANT_MAP: [RegExp, string][] = [
  [/ethio ?telecom|safaricom|airtime/i, "bills.phone"],
  [/ethiopian electric|\beeu\b|\beepco\b/i, "bills.electricity"],
  [/\bwifi\b|internet|broadband/i, "bills.internet"],
  [/\bride\b|feres|zayride|yango|\btaxi\b/i, "transport.taxi"],
  [/\btotal ?energies\b|\bnoc\b|oilibya|\bfuel\b|petrol|gas station/i, "transport.fuel"],
  [/\bcaf[eé]\b|coffee|\bbuna\b|kaldi/i, "food.coffee"],
  [/restaurant|pizza|burger|kitchen|\bgrill\b|\bbar\b|lounge/i, "food.restaurants"],
  [/supermarket|grocery|\bmini ?market\b|shoa|queens/i, "food.groceries"],
  [/pharmacy|hospital|clinic|health|medical|diagnostic/i, "health"],
  [/school|university|college|academy|tuition/i, "education"],
  [/netflix|spotify|youtube|apple\.com|google|showmax|dstv/i, "subscriptions"],
  [/cinema|theat(er|re)|game|\bclub\b/i, "entertainment"],
];

export const REVIEW_THRESHOLD = 0.8;

export async function categorize(
  input: CategorizeInput,
  store: CategoryStore,
  ai?: AiCategorizer,
): Promise<CategoryChoice> {
  const key = input.counterpartyKey;

  // 1. User rules
  if (key) {
    const ruleCategory = await store.userRuleCategoryId(input.userId, key);
    if (ruleCategory) return { categoryKey: null, categoryId: ruleCategory, source: "rule", confidence: 1 };
  }

  if (input.type === "income") {
    return { categoryKey: "income", categoryId: null, source: "keyword", confidence: 0.9 };
  }

  // 2. Merchant map, on the name first, then the description
  const haystack = [input.counterpartyName, input.description].filter(Boolean).join(" ");
  for (const [pattern, categoryKey] of MERCHANT_MAP) {
    if (haystack && pattern.test(haystack)) {
      return { categoryKey, categoryId: null, source: "merchant_map", confidence: 0.85 };
    }
  }

  // Money sent to a person: a name says nothing about what it was for, so ask.
  if (input.counterpartyKind === "person") {
    return { categoryKey: "transfer", categoryId: null, source: "fallback", confidence: 0.5 };
  }

  // 3–4. AI for merchants we haven't seen
  if (key && input.counterpartyName) {
    const cached = await store.cachedSuggestion(key);
    if (cached) {
      return { categoryKey: cached.categoryKey, categoryId: null, source: "ai", confidence: cached.confidence };
    }

    if (ai) {
      try {
        const suggestion = await ai.categorize({
          counterparty: input.counterpartyName,
          type: input.type,
          amountEtb: input.amount / 100,
          description: input.description,
          categoryKeys: DEFAULT_CATEGORY_KEYS,
        });
        if (suggestion && DEFAULT_CATEGORY_KEYS.includes(suggestion.categoryKey)) {
          await store.saveSuggestion(key, suggestion);
          return {
            categoryKey: suggestion.categoryKey,
            categoryId: null,
            source: "ai",
            confidence: suggestion.confidence,
          };
        }
      } catch (err) {
        console.warn("AI categorization failed; falling back", err);
      }
    }
  }

  // 5. Fallback
  return { categoryKey: "other", categoryId: null, source: "fallback", confidence: 0.3 };
}
