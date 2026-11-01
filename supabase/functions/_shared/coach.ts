// The AI coach: turns the phone's summary of the user's money (periods,
// categories, people, goals and their progress) into a short assessment and
// concrete suggestions. The phone computes every number; the model only reads
// them, so it never has to do arithmetic over raw transactions.

export interface CoachAdvice {
  headline: string;
  assessment: string;
  suggestions: { title: string; detail: string }[];
  goalNotes: { goal: string; note: string }[];
}

export const MAX_SUMMARY_BYTES = 48_000;

export const SYSTEM_PROMPT = [
  "You are a personal finance coach inside a money-tracking app used in Ethiopia.",
  "Amounts are Ethiopian birr (ETB). You get a JSON summary the app computed from the user's real transactions:",
  "this and last week/month totals, spending by category, top people and shops, biggest expenses with reasons,",
  "and the user's goals with progress (status, amount so far, days left, allowed spending per day).",
  "Rules:",
  "- Use the actual numbers and names from the summary; never invent figures or transactions.",
  "- Lead with the goals: say plainly whether each is on track and what it takes to hit it.",
  "- Give 2 to 4 concrete, specific suggestions (e.g. which category or person to cut, by how much, per day).",
  "- Point out unusual changes versus the previous period, and fees if they are significant.",
  "- If there are no goals, suggest one sensible goal based on their spending.",
  "- Be warm and direct, no lectures, no generic tips like 'make a budget'. Short sentences.",
  "- Transfers between the user's own accounts are not spending.",
].join("\n");

export const RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["headline", "assessment", "suggestions", "goal_notes"],
  properties: {
    headline: { type: "string", description: "One short line, at most 80 characters." },
    assessment: { type: "string", description: "Two to four sentences on how the user is doing." },
    suggestions: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["title", "detail"],
        properties: { title: { type: "string" }, detail: { type: "string" } },
      },
    },
    goal_notes: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["goal", "note"],
        properties: { goal: { type: "string" }, note: { type: "string" } },
      },
    },
  },
} as const;

/** Throws when the model's JSON doesn't have the promised shape. */
export function parseAdvice(raw: string): CoachAdvice {
  const j = JSON.parse(raw);
  const str = (v: unknown, field: string): string => {
    if (typeof v !== "string" || !v.trim()) throw new Error(`coach: missing ${field}`);
    return v.trim();
  };
  const list = (v: unknown, field: string): Record<string, unknown>[] => {
    if (!Array.isArray(v)) throw new Error(`coach: ${field} is not a list`);
    return v as Record<string, unknown>[];
  };
  return {
    headline: str(j.headline, "headline"),
    assessment: str(j.assessment, "assessment"),
    suggestions: list(j.suggestions, "suggestions").slice(0, 4).map((s) => ({
      title: str(s.title, "suggestion title"),
      detail: str(s.detail, "suggestion detail"),
    })),
    goalNotes: list(j.goal_notes, "goal_notes").slice(0, 6).map((g) => ({
      goal: str(g.goal, "goal"),
      note: str(g.note, "goal note"),
    })),
  };
}

export interface CoachConfig {
  apiKey: string;
  model: string;
  fetch?: typeof fetch;
}

/** Asks the model; the summary goes in as JSON text. */
export async function askCoach(summary: unknown, config: CoachConfig): Promise<CoachAdvice> {
  const doFetch = config.fetch ?? fetch;
  const res = await doFetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "authorization": `Bearer ${config.apiKey}`, "content-type": "application/json" },
    body: JSON.stringify({
      model: config.model,
      temperature: 0.4,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: JSON.stringify(summary) },
      ],
      response_format: {
        type: "json_schema",
        json_schema: { name: "coach_advice", strict: true, schema: RESPONSE_SCHEMA },
      },
    }),
    signal: AbortSignal.timeout(45_000),
  });
  if (!res.ok) throw new Error(`coach: OpenAI HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const body = await res.json();
  const content = body?.choices?.[0]?.message?.content;
  if (typeof content !== "string") throw new Error("coach: empty model response");
  return parseAdvice(content);
}
