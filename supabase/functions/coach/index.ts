// POST /functions/v1/coach
//
// Body: the summary the phone computed (see mobile/lib/features/coach).
// Auth: the app's Supabase session (verify_jwt). Returns CoachAdvice JSON.

import { createClient } from "npm:@supabase/supabase-js@2";
import { askCoach, MAX_SUMMARY_BYTES } from "../_shared/coach.ts";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  const { data } = bearer ? await db.auth.getUser(bearer) : { data: { user: null } };
  if (!data.user) return json(401, { error: "unauthorized" });

  const text = await req.text();
  if (text.length > MAX_SUMMARY_BYTES) return json(413, { error: "summary_too_large" });
  let summary: unknown;
  try {
    summary = JSON.parse(text);
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return json(503, { error: "coach_not_configured" });

  try {
    const advice = await askCoach(summary, { apiKey, model: Deno.env.get("OPENAI_COACH_MODEL") ?? "gpt-4.1-mini" });
    return json(200, advice);
  } catch (err) {
    console.error("coach failed", err);
    return json(502, { error: "coach_failed" });
  }
});
