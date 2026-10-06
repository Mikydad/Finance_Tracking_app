// AI step of the categorizer (build plan 4.3, step 4): asks an OpenAI model
// to pick one of the default category keys for a merchant we haven't seen.
// Only what AiCategorizeInput carries is sent: merchant name, type, amount,
// the parser's short description and the key list. Never raw SMS, account
// numbers, balances or the user's identity.

import type { AiCategorizeInput, AiCategorizer, AiSuggestion } from "./categorizer.ts";

/** The cheapest current OpenAI model with structured outputs (Oct 2026). */
export const DEFAULT_OPENAI_MODEL = "gpt-6-luna";

const ENDPOINT = "https://api.openai.com/v1/chat/completions";

/** What each key means, so the model isn't guessing from the key alone. */
const KEY_HINTS: Record<string, string> = {
  "food": "food and drink that fits no subcategory",
  "food.restaurants": "restaurants, fast food, bars, hotels' restaurants, delivery",
  "food.groceries": "supermarkets, grocery shops, markets, bakeries, butchers",
  "food.coffee": "cafes, coffee and tea houses, juice bars",
  "transport": "transport that fits no subcategory",
  "transport.taxi": "taxis and ride-hailing (Ride, Feres, Yango)",
  "transport.fuel": "fuel stations",
  "transport.public": "buses, light rail, minibus, airlines and train tickets",
  "shopping": "clothes, electronics, household goods, general retail",
  "bills": "utilities and bills that fit no subcategory, rent",
  "bills.internet": "internet and Wi-Fi providers",
  "bills.phone": "airtime, mobile packages, Ethio telecom, Safaricom",
  "bills.electricity": "Ethiopian Electric Utility",
  "entertainment": "cinema, events, games, sport, leisure",
  "health": "pharmacies, hospitals, clinics, labs, gyms",
  "education": "schools, universities, courses, books, tuition",
  "family": "support sent to family members",
  "subscriptions": "recurring digital services (streaming, software, app stores)",
  "income": "money received",
  "transfer": "moving money between people or own accounts, a private person's name",
  "other": "none of the above",
};

const SYSTEM_PROMPT = [
  "You categorize transactions from Ethiopian bank and telebirr SMS for a personal finance app.",
  "You get the merchant name as the bank wrote it, the transaction type, the amount in Ethiopian birr (ETB)",
  "and sometimes a short description. Pick the single best category key from the list.",
  "Confidence is your probability (0 to 1) that the key is right.",
  "Use 0.8 or more only when the merchant name clearly says what it sells.",
  "If the name looks like a private person, or you don't recognize it, use a low confidence (0.5 or less)",
  "and pick 'transfer' for a person or your best guess otherwise.",
].join(" ");

export interface OpenAiOptions {
  model?: string;
  timeoutMs?: number;
  /** Injected in tests. */
  fetch?: typeof fetch;
}

export class OpenAiCategorizer implements AiCategorizer {
  private readonly model: string;
  private readonly timeoutMs: number;
  private readonly fetch: typeof fetch;

  constructor(private readonly apiKey: string, opts: OpenAiOptions = {}) {
    this.model = opts.model || DEFAULT_OPENAI_MODEL;
    this.timeoutMs = opts.timeoutMs ?? 8000;
    this.fetch = opts.fetch ?? fetch;
  }

  async categorize(input: AiCategorizeInput): Promise<AiSuggestion | null> {
    const res = await this.fetch(ENDPOINT, {
      method: "POST",
      headers: { "authorization": `Bearer ${this.apiKey}`, "content-type": "application/json" },
      body: JSON.stringify(this.requestBody(input)),
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    if (!res.ok) {
      // The error body never contains the key; keep it short in the logs.
      const detail = (await res.text()).slice(0, 300);
      throw new Error(`OpenAI ${res.status}: ${detail}`);
    }

    const data = await res.json();
    const choice = data?.choices?.[0];
    const content = choice?.message?.content;
    if (choice?.finish_reason !== "stop" || typeof content !== "string") return null;

    let parsed: { categoryKey?: unknown; confidence?: unknown };
    try {
      parsed = JSON.parse(content);
    } catch {
      return null;
    }
    const key = parsed.categoryKey;
    const confidence = Number(parsed.confidence);
    if (typeof key !== "string" || !input.categoryKeys.includes(key) || !Number.isFinite(confidence)) return null;

    return {
      categoryKey: key,
      confidence: Math.min(1, Math.max(0, confidence)),
      model: typeof data.model === "string" ? data.model : this.model,
    };
  }

  requestBody(input: AiCategorizeInput) {
    const categories = input.categoryKeys.map((k) => `${k}: ${KEY_HINTS[k] ?? k}`).join("\n");
    const transaction = {
      merchant: input.counterparty,
      type: input.type,
      amountEtb: input.amountEtb,
      description: input.description,
    };
    return {
      model: this.model,
      reasoning_effort: "none",
      max_completion_tokens: 100,
      messages: [
        { role: "system", content: `${SYSTEM_PROMPT}\n\nCategories:\n${categories}` },
        { role: "user", content: JSON.stringify(transaction) },
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "category",
          strict: true,
          schema: {
            type: "object",
            properties: {
              categoryKey: { type: "string", enum: input.categoryKeys },
              confidence: { type: "number" },
            },
            required: ["categoryKey", "confidence"],
            additionalProperties: false,
          },
        },
      },
    };
  }
}
