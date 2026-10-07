import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { askCoach, parseAdvice } from "../coach.ts";

const good = {
  headline: "Food is eating your week",
  assessment: "You spent 3,200 of your 5,000 limit in 4 days.",
  suggestions: [{ title: "Cook twice", detail: "Two home meals keep you under 5,000." }],
  goal_notes: [{ goal: "Spend at most 5,000 ETB a week", note: "~600/day left" }],
};

Deno.test("parseAdvice keeps the promised shape and trims", () => {
  const a = parseAdvice(JSON.stringify({ ...good, headline: "  Food is eating your week " }));
  assertEquals(a.headline, "Food is eating your week");
  assertEquals(a.goalNotes[0].note, "~600/day left");
});

Deno.test("parseAdvice rejects missing fields", () => {
  assertThrows(() => parseAdvice(JSON.stringify({ ...good, assessment: "" })));
  assertThrows(() => parseAdvice(JSON.stringify({ ...good, suggestions: "x" })));
});

Deno.test("askCoach sends the summary with a strict JSON schema and reads the answer", async () => {
  let sent: Record<string, unknown> = {};
  const fakeFetch = ((_url: string, init: RequestInit) => {
    sent = JSON.parse(init.body as string);
    return Promise.resolve(
      new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify(good) } }] }), { status: 200 }),
    );
  }) as unknown as typeof fetch;

  const advice = await askCoach({ week: { spent: 3200 } }, { apiKey: "k", model: "m", fetch: fakeFetch });
  assertEquals(advice.suggestions.length, 1);
  assertEquals(sent.model, "m");
  const messages = sent.messages as { role: string; content: string }[];
  assertEquals(JSON.parse(messages[1].content), { week: { spent: 3200 } });
  assertEquals((sent.response_format as { type: string }).type, "json_schema");
});

Deno.test("askCoach surfaces an API failure", async () => {
  const failing = (() => Promise.resolve(new Response("quota", { status: 429 }))) as unknown as typeof fetch;
  await assertRejects(() => askCoach({}, { apiKey: "k", model: "m", fetch: failing }), Error, "429");
});
