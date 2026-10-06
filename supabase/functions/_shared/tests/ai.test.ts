import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { DEFAULT_OPENAI_MODEL, OpenAiCategorizer } from "../ai.ts";
import { type AiCategorizeInput, DEFAULT_CATEGORY_KEYS } from "../categorizer.ts";

const INPUT: AiCategorizeInput = {
  counterparty: "Tomoca Coffee Bole",
  type: "expense",
  amountEtb: 180,
  description: null,
  categoryKeys: DEFAULT_CATEGORY_KEYS,
};

interface Sent {
  url: string;
  headers: Headers;
  body: Record<string, unknown>;
}

function fakeFetch(status: number, response: unknown, sent: Sent[] = []): typeof fetch {
  return (url, init) => {
    sent.push({
      url: String(url),
      headers: new Headers(init?.headers),
      body: JSON.parse(String(init?.body)),
    });
    const text = typeof response === "string" ? response : JSON.stringify(response);
    return Promise.resolve(new Response(text, { status }));
  };
}

function completion(content: string, finishReason = "stop") {
  return {
    model: "gpt-6-luna-2026-09-01",
    choices: [{ finish_reason: finishReason, message: { role: "assistant", content } }],
  };
}

Deno.test("OpenAI: sends only the allowed fields and parses the structured answer", async () => {
  const sent: Sent[] = [];
  const ai = new OpenAiCategorizer("sk-test", {
    fetch: fakeFetch(200, completion('{"categoryKey":"food.coffee","confidence":0.93}'), sent),
  });

  const s = await ai.categorize(INPUT);

  assertEquals(s, { categoryKey: "food.coffee", confidence: 0.93, model: "gpt-6-luna-2026-09-01" });
  assertEquals(sent.length, 1);
  assertEquals(sent[0].url, "https://api.openai.com/v1/chat/completions");
  assertEquals(sent[0].headers.get("authorization"), "Bearer sk-test");

  const body = sent[0].body as {
    model: string;
    messages: { role: string; content: string }[];
    response_format: { json_schema: { strict: boolean; schema: { properties: { categoryKey: { enum: string[] } } } } };
  };
  assertEquals(body.model, DEFAULT_OPENAI_MODEL);
  assertEquals(JSON.parse(body.messages[1].content), {
    merchant: "Tomoca Coffee Bole",
    type: "expense",
    amountEtb: 180,
    description: null,
  });
  assert(body.response_format.json_schema.strict);
  assertEquals(body.response_format.json_schema.schema.properties.categoryKey.enum, DEFAULT_CATEGORY_KEYS);
});

Deno.test("OpenAI: the model can be swapped with OPENAI_MODEL", async () => {
  const sent: Sent[] = [];
  const ai = new OpenAiCategorizer("sk-test", {
    model: "gpt-other",
    fetch: fakeFetch(200, completion('{"categoryKey":"other","confidence":0.4}'), sent),
  });
  await ai.categorize(INPUT);
  assertEquals(sent[0].body.model, "gpt-other");
});

Deno.test("OpenAI: confidence is clamped to 0..1", async () => {
  const ai = new OpenAiCategorizer("k", {
    fetch: fakeFetch(200, completion('{"categoryKey":"health","confidence":7}')),
  });
  assertEquals((await ai.categorize(INPUT))?.confidence, 1);
});

Deno.test("OpenAI: unusable answers return null so the fallback applies", async () => {
  const answers = [
    completion('{"categoryKey":"crypto","confidence":0.9}'), // not one of our keys
    completion('{"categoryKey":"food","confidence":"high"}'),
    completion("not json"),
    completion('{"categoryKey":"food","conf', "length"),
    { choices: [{ finish_reason: "stop", message: { role: "assistant", content: null, refusal: "no" } }] },
    {},
  ];
  for (const answer of answers) {
    const ai = new OpenAiCategorizer("k", { fetch: fakeFetch(200, answer) });
    assertEquals(await ai.categorize(INPUT), null, JSON.stringify(answer));
  }
});

Deno.test("OpenAI: an HTTP error throws (the categorizer then falls back to review)", async () => {
  const ai = new OpenAiCategorizer("k", { fetch: fakeFetch(429, { error: { message: "rate limited" } }) });
  await assertRejects(() => ai.categorize(INPUT), Error, "OpenAI 429");
});
