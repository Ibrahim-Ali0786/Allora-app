// Allora provisioning — registers the Matrix account for a Supabase user.
//
// WHY: the app previously performed Synapse shared-secret registration
// CLIENT-SIDE, which means the admin registration secret shipped inside the
// APK. Moving it here keeps the secret on the server; the client just calls
// this function with its Supabase JWT.
//
// Deploy:
//   supabase functions deploy allora-provision
//   supabase secrets set SYNAPSE_REGISTRATION_SECRET=...
//   supabase secrets set SYNAPSE_BASE_URL=https://matrix.allorachat.app
//
// After deploying, rotate the old secret on the Synapse server
// (registration_shared_secret in homeserver.yaml) so APKs built before this
// change can no longer use it, and remove the legacy fallback in main.dart.

import { createClient } from "jsr:@supabase/supabase-js@2";

const enc = new TextEncoder();

async function hmacSha1Hex(key: string, message: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(key),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(message));
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (request) => {
  const headers = { "content-type": "application/json" };
  try {
    const secret = Deno.env.get("SYNAPSE_REGISTRATION_SECRET");
    const baseUrl = Deno.env.get("SYNAPSE_BASE_URL") ??
      "https://matrix.allorachat.app";
    if (!secret) {
      return new Response(
        JSON.stringify({ ok: false, error: "not_configured" }),
        { status: 500, headers },
      );
    }

    // Identify the caller from their Supabase JWT — the username is DERIVED
    // server-side from the verified user id, so a caller can never register
    // an arbitrary account.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: request.headers.get("Authorization")! } } },
    );
    const { data: { user }, error } = await supabase.auth.getUser();
    if (error || !user) {
      return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
        status: 401,
        headers,
      });
    }

    const username = user.id.replaceAll("-", "").toLowerCase();
    const { password } = await request.json().catch(() => ({ password: null }));
    if (typeof password !== "string" || password.length < 12) {
      return new Response(JSON.stringify({ ok: false, error: "bad_request" }), {
        status: 400,
        headers,
      });
    }

    const nonceRes = await fetch(`${baseUrl}/_synapse/admin/v1/register`);
    if (!nonceRes.ok) throw new Error(`nonce ${nonceRes.status}`);
    const { nonce } = await nonceRes.json();

    const mac = await hmacSha1Hex(
      secret,
      `${nonce}\x00${username}\x00${password}\x00notadmin`,
    );

    const regRes = await fetch(`${baseUrl}/_synapse/admin/v1/register`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ nonce, username, password, mac, admin: false }),
    });

    if (regRes.ok) {
      return new Response(JSON.stringify({ ok: true, username }), { headers });
    }
    const body = await regRes.json().catch(() => ({}));
    // Already registered is a success for our purposes.
    if (body?.errcode === "M_USER_IN_USE") {
      return new Response(JSON.stringify({ ok: true, username }), { headers });
    }
    console.error("provision failed:", regRes.status, body);
    return new Response(JSON.stringify({ ok: false, error: "registration_failed" }), {
      status: 502,
      headers,
    });
  } catch (e) {
    console.error("allora-provision:", e);
    return new Response(JSON.stringify({ ok: false, error: "internal" }), {
      status: 500,
      headers,
    });
  }
});
