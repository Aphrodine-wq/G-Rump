// ─────────────────────────────────────────────────────────────────────────
// alibaba.js — the single point where this backend calls Alibaba Cloud.
//
// G-Rump runs entirely on Qwen via Alibaba Cloud's Model Studio (DashScope),
// using its OpenAI-compatible endpoint. Every model call in the backend goes
// through this file, so it is the one place that proves "the backend calls
// Alibaba Cloud / Qwen Cloud services" (a hackathon submission requirement).
//
// The host is *.aliyuncs.com — Alibaba Cloud. International accounts use
// dashscope-intl; mainland accounts use dashscope. Override with QWEN_BASE_URL.
// ─────────────────────────────────────────────────────────────────────────

const QWEN_BASE_URL = (process.env.QWEN_BASE_URL ||
  'https://dashscope-intl.aliyuncs.com/compatible-mode/v1').replace(/\/+$/, '');
const QWEN_API_KEY = process.env.QWEN_API_KEY || process.env.DASHSCOPE_API_KEY || '';
const DEFAULT_EMBED_MODEL = process.env.QWEN_EMBED_MODEL || 'text-embedding-v4';

export function isAlibabaConfigured() {
  return Boolean(QWEN_API_KEY);
}

export function alibabaHost() {
  try { return new URL(QWEN_BASE_URL).host; } catch { return QWEN_BASE_URL; }
}

function authHeaders() {
  return {
    Authorization: `Bearer ${QWEN_API_KEY}`,
    'Content-Type': 'application/json',
  };
}

// Chat completions on Alibaba Cloud (Qwen). Returns the raw upstream `fetch`
// Response so the caller can stream the SSE body straight through to the client
// — preserving Qwen's tool_calls / tool_call_id round-trip untouched.
export async function qwenChatCompletions(body) {
  if (!QWEN_API_KEY) throw new Error('QWEN_API_KEY is not set');
  return fetch(`${QWEN_BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify(body),
    duplex: 'half',
  });
}

// Text embeddings on Alibaba Cloud (Qwen) — backs the desktop app's semantic
// memory. `input` may be a string or an array of strings.
export async function qwenEmbeddings(input, model = DEFAULT_EMBED_MODEL) {
  if (!QWEN_API_KEY) throw new Error('QWEN_API_KEY is not set');
  const resp = await fetch(`${QWEN_BASE_URL}/embeddings`, {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify({ model, input }),
  });
  return resp;
}
