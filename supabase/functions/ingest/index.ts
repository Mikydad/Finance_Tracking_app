// POST /functions/v1/ingest
//
// Body: { "text": "<bank SMS>", "sender": "CBE", "receivedAt": "2026-10-05T12:00:00Z",
//         "channel": "shortcut" | "paste" | "android_sms" }
// Auth: either the app's Supabase session (Authorization: Bearer <jwt>) or an
// ingestion token from the iPhone Shortcut (Authorization: Bearer fin_...).

import { createClient } from "npm:@supabase/supabase-js@2";
import { encryptText, importKey, sha256Hex } from "../_shared/crypto.ts";
import { type Channel, ingestMessage } from "../_shared/pipeline.ts";
import { SupabaseIngestStore } from "../_shared/supabase_store.ts";

const MAX_TEXT_LENGTH = 2000;
const CHANNELS: Channel[] = ["shortcut", "paste", "android_sms"];

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const keyPromise = importKey(Deno.env.get("RAW_MESSAGE_KEY") ?? "");

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

async function authenticate(req: Request): Promise<string | null> {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!bearer) return null;

  if (bearer.startsWith("fin_")) {
    const { data } = await db.from("ingestion_tokens").select("id, user_id")
      .eq("token_hash", await sha256Hex(bearer)).is("revoked_at", null).maybeSingle();
    if (!data) return null;
    await db.from("ingestion_tokens").update({ last_used_at: new Date().toISOString() }).eq("id", data.id);
    return data.user_id as string;
  }

  const { data } = await db.auth.getUser(bearer);
  return data.user?.id ?? null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const userId = await authenticate(req);
  if (!userId) return json(401, { error: "unauthorized" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const text = typeof body.text === "string" ? body.text.trim() : "";
  if (!text) return json(400, { error: "text_required" });
  if (text.length > MAX_TEXT_LENGTH) return json(413, { error: "text_too_long" });

  const channel = (CHANNELS.includes(body.channel as Channel) ? body.channel : "shortcut") as Channel;
  const sender = typeof body.sender === "string" && body.sender.trim() ? body.sender.trim().slice(0, 40) : null;
  const receivedAt = typeof body.receivedAt === "string" && !isNaN(Date.parse(body.receivedAt))
    ? new Date(body.receivedAt)
    : new Date();

  try {
    const key = await keyPromise;
    const result = await ingestMessage(
      new SupabaseIngestStore(db),
      { userId, channel, text, sender, receivedAt },
      { encrypt: (plain) => encryptText(key, plain) },
    );
    return json(200, result);
  } catch (err) {
    console.error("ingest failed", err);
    return json(500, { error: "ingest_failed" });
  }
});
