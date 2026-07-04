# allora-ai — server-side AI proxy

All Allora AI features (rewrite, translate, summarize, smart replies, the
assistant chat) call this function. The Anthropic key lives **only** here as
a Supabase secret — never in the APK.

## Deploy

```bash
supabase functions deploy allora-ai        # JWT verification stays ON
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
# optional model override (defaults to claude-haiku-4-5-20251001):
supabase secrets set ALLORA_AI_MODEL=claude-sonnet-4-6
```

The app calls it via `Supabase.functions.invoke('allora-ai', ...)`, so the
user's Supabase session token is attached automatically and unauthenticated
callers are rejected by the platform.

## Contract

Request body: `{ task, text?, tone?, language?, prompt?, context?, history? }`
Response: `{ ok: true, text?, suggestions? }` or `{ ok: false, error }`.

Until this function is deployed, the app shows a clear "AI is unreachable"
message wherever AI is invoked — nothing else breaks.
