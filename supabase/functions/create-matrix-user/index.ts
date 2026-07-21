import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const SYNAPSE_URL = "https://matrix.allorachat.app";
// In production, store this in Supabase Secrets. It must match your homeserver.yaml exactly.
const SHARED_SECRET = "REPLACE_WITH_A_SUPER_LONG_RANDOM_STRING"; 

// Generates the strict HMAC-SHA1 digest required by Synapse's Shared-Secret API.
async function generateMac(nonce: string, user: string, pass: string, secret: string) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false, ["sign"]
  );
  
  // The payload format must be exactly: nonce\0username\0password\0admin
  const payload = `${nonce}\0${user}\0${pass}\0notadmin`;
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  
  return Array.from(new Uint8Array(signature))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

serve(async (req) => {
  try {
    const { username, displayName, password } = await req.json();

    // 1. Fetch a single-use nonce from Synapse
    const nonceRes = await fetch(`${SYNAPSE_URL}/_synapse/admin/v1/register`);
    const { nonce } = await nonceRes.json();

    // 2. Generate the cryptographic MAC
    const mac = await generateMac(nonce, username, password, SHARED_SECRET);

    // 3. Command Synapse to provision the new user
    const regRes = await fetch(`${SYNAPSE_URL}/_synapse/admin/v1/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        nonce,
        username,
        displayname: displayName,
        password,
        admin: false,
        mac
      })
    });

    const matrixData = await regRes.json();

    // matrixData contains the new access_token, device_id, and user_id
    return new Response(JSON.stringify(matrixData), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
})