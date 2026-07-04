// Allora AI — Supabase Edge Function
//
// The app never ships an LLM key: every AI request is proxied through this
// function. Supabase verifies the caller's JWT before invoking it (default
// behaviour — do NOT deploy with --no-verify-jwt).
//
// Deploy:
//   supabase functions deploy allora-ai
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
// Optional:
//   supabase secrets set ALLORA_AI_MODEL=claude-haiku-4-5-20251001

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const MODEL = Deno.env.get("ALLORA_AI_MODEL") ?? "claude-haiku-4-5-20251001";
const MAX_TOKENS = 1024;

type Msg = { sender?: string; text?: string; role?: string };

interface AiRequest {
  task: string;
  text?: string;
  tone?: string;
  language?: string;
  prompt?: string;
  context?: Msg[];
  history?: Msg[];
}

const TONES: Record<string, string> = {
  professional: "a polished, professional tone",
  friendly: "a warm, friendly tone",
  romantic: "a sweet, romantic tone",
  formal: "a formal, respectful tone",
  funny: "a light, funny tone",
  shorter: "the same tone but noticeably shorter",
  longer: "the same tone but more detailed",
};

function contextBlock(context: Msg[] | undefined): string {
  if (!context?.length) return "";
  const lines = context
    .slice(-20)
    .map((m) => `${(m.sender ?? "?").slice(0, 40)}: ${(m.text ?? "").slice(0, 800)}`)
    .join("\n");
  return `\n\nConversation (oldest first):\n${lines}`;
}

function buildPrompt(req: AiRequest): { system: string; user: string } {
  const base =
    "You are Allora AI, the writing assistant inside the Allora messenger. " +
    "Reply with ONLY the requested text — no preamble, no quotes, no markdown fences.";
  const t = (req.text ?? "").slice(0, 4000);

  switch (req.task) {
    case "rewrite":
      return {
        system: base,
        user: `Rewrite this message in ${TONES[req.tone ?? ""] ?? "a clearer way"}. Keep the meaning and the language of the original.\n\n${t}`,
      };
    case "grammar":
      return {
        system: base,
        user: `Fix spelling and grammar. Change nothing else. Keep the original language.\n\n${t}`,
      };
    case "translate":
      return {
        system: base,
        user: `Translate to ${req.language ?? "English"}. Natural, conversational register.\n\n${t}`,
      };
    case "explain":
      return {
        system: base.replace("ONLY the requested text", "a short, clear explanation"),
        user: `Explain what this message means (intent, idioms, tone). 2-4 sentences.\n\n${t}`,
      };
    case "detect_tone":
      return {
        system: base,
        user: `In one short sentence, describe the tone of this message:\n\n${t}`,
      };
    case "compose":
      return {
        system: base,
        user: `Write a message for me. ${req.tone ? `Use ${TONES[req.tone] ?? req.tone}. ` : ""}Task: ${(req.prompt ?? "").slice(0, 1000)}`,
      };
    case "summarize":
      return {
        system: base.replace("ONLY the requested text", "a compact summary"),
        user: `Summarize this conversation in 3-6 bullet points (use • ). Include decisions and open questions.${contextBlock(req.context)}`,
      };
    case "extract":
      return {
        system: base.replace("ONLY the requested text", "a compact list"),
        user: `From this conversation, extract action items, dates/times, and places as short bullet points grouped under "Tasks", "Dates", "Places". Write "None found" for empty groups.${contextBlock(req.context)}`,
      };
    case "reply":
      return {
        system: base,
        user: `${(req.prompt ?? "Suggest the best reply").slice(0, 500)}. Write it as me ("Me" in the transcript), matching the conversation's language and tone.${contextBlock(req.context)}`,
      };
    case "smart_replies":
      return {
        system:
          "You suggest quick replies inside a messenger. Output EXACTLY three replies separated by newlines. Each under 8 words, in the conversation's language, no numbering, no quotes.",
        user: `Suggest three quick replies I could send next.${contextBlock(req.context)}`,
      };
    case "chat":
      return { system: "", user: "" }; // handled separately
    default:
      return { system: base, user: t || (req.prompt ?? "") };
  }
}

async function callModel(
  apiKey: string,
  system: string,
  messages: { role: string; content: string }[],
): Promise<string> {
  const res = await fetch(ANTHROPIC_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      ...(system ? { system } : {}),
      messages,
    }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`model_error ${res.status}: ${body.slice(0, 300)}`);
  }
  const data = await res.json();
  return (data.content?.[0]?.text ?? "").trim();
}

Deno.serve(async (request) => {
  const headers = { "content-type": "application/json" };
  try {
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ ok: false, error: "AI backend not configured (missing ANTHROPIC_API_KEY)." }),
        { status: 500, headers },
      );
    }

    const req = (await request.json()) as AiRequest;

    if (req.task === "chat") {
      const history = (req.history ?? []).slice(-24);
      const messages = history
        .filter((m) => (m.text ?? "").trim().length > 0)
        .map((m) => ({
          role: m.role === "assistant" ? "assistant" : "user",
          content: (m.text ?? "").slice(0, 4000),
        }));
      if (messages.length === 0 || messages[messages.length - 1].role !== "user") {
        return new Response(
          JSON.stringify({ ok: false, error: "Nothing to respond to." }),
          { status: 400, headers },
        );
      }
      const text = await callModel(
        apiKey,
        "You are Allora AI, a concise, helpful assistant inside the Allora messenger. " +
          "You help with writing, translating, summarizing and everyday questions. Keep answers tight.",
        messages,
      );
      return new Response(JSON.stringify({ ok: true, text }), { headers });
    }

    const { system, user } = buildPrompt(req);
    if (!user.trim()) {
      return new Response(
        JSON.stringify({ ok: false, error: "Empty request." }),
        { status: 400, headers },
      );
    }
    const text = await callModel(apiKey, system, [{ role: "user", content: user }]);

    if (req.task === "smart_replies") {
      const suggestions = text
        .split("\n")
        .map((s) => s.replace(/^[-•*\d.\s"]+|["\s]+$/g, "").trim())
        .filter((s) => s.length > 0 && s.length <= 60)
        .slice(0, 3);
      return new Response(JSON.stringify({ ok: true, suggestions }), { headers });
    }

    return new Response(JSON.stringify({ ok: true, text }), { headers });
  } catch (e) {
    console.error("allora-ai:", e);
    return new Response(
      JSON.stringify({ ok: false, error: "The AI service hit an error. Try again." }),
      { status: 500, headers },
    );
  }
});
