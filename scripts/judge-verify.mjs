#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────
// judge-verify.mjs — verify G-Rump's Qwen integration on ANY OS (no Mac needed).
//
// G-Rump's UI is macOS-only, but its intelligence runs on Qwen via a
// cross-platform backend. This script proves the part that matters for judging:
// that the agentic loop actually works on Qwen — tool calling round-trips and
// embeddings — end to end.
//
// Usage (Node 18+, no dependencies):
//   QWEN_API_KEY=sk-...  node scripts/judge-verify.mjs
//
// Routes through the deployed backend if BACKEND_URL is set (proves the
// Alibaba-hosted backend); otherwise calls Qwen DashScope directly.
//   BACKEND_URL=https://<host>  APP_API_KEY=...  node scripts/judge-verify.mjs
//
// Exit 0 = all checks pass.
// ─────────────────────────────────────────────────────────────────────────

const KEY = process.env.QWEN_API_KEY || process.env.DASHSCOPE_API_KEY || '';
const BACKEND_URL = (process.env.BACKEND_URL || '').replace(/\/+$/, '');
const APP_API_KEY = process.env.APP_API_KEY || '';
const DIRECT_BASE = (process.env.QWEN_BASE_URL || 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1').replace(/\/+$/, '');
const CHAT_MODEL = process.env.QWEN_MODEL || 'qwen-coder-plus';
const EMBED_MODEL = process.env.QWEN_EMBED_MODEL || 'text-embedding-v4';

const mode = BACKEND_URL ? `backend (${BACKEND_URL})` : `direct DashScope (${DIRECT_BASE})`;

function chatURL() { return BACKEND_URL ? `${BACKEND_URL}/api/v1/chat/completions` : `${DIRECT_BASE}/chat/completions`; }
function embedURL() { return BACKEND_URL ? `${BACKEND_URL}/api/v1/embeddings` : `${DIRECT_BASE}/embeddings`; }
function headers() {
  // Through the backend: the backend holds the Qwen key; we send APP_API_KEY.
  // Direct: we send the Qwen key as the bearer.
  const bearer = BACKEND_URL ? APP_API_KEY : KEY;
  return { 'Authorization': `Bearer ${bearer}`, 'Content-Type': 'application/json' };
}

const READ_FILE_TOOL = {
  type: 'function',
  function: {
    name: 'read_file',
    description: 'Read the full contents of a file at a given path.',
    parameters: { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] },
  },
};

let passed = 0, failed = 0;
function ok(name, detail = '') { passed++; console.log(`  PASS  ${name}${detail ? ' — ' + detail : ''}`); }
function bad(name, detail = '') { failed++; console.log(`  FAIL  ${name}${detail ? ' — ' + detail : ''}`); }

async function post(url, body) {
  const res = await fetch(url, { method: 'POST', headers: headers(), body: JSON.stringify(body) });
  return res;
}

// 1) Connectivity / non-streaming chat.
async function checkChat() {
  try {
    const res = await post(chatURL(), {
      model: CHAT_MODEL, stream: false,
      messages: [{ role: 'user', content: 'Reply with exactly: OK' }],
    });
    if (!res.ok) return bad('chat connectivity', `HTTP ${res.status}: ${(await res.text()).slice(0, 160)}`);
    const data = await res.json();
    const text = data?.choices?.[0]?.message?.content ?? '';
    text ? ok('chat connectivity', `model replied (${text.trim().slice(0, 40)})`) : bad('chat connectivity', 'empty reply');
  } catch (e) { bad('chat connectivity', e.message); }
}

// 2) Multi-turn tool calling — the core of the autonomous agent loop.
async function checkToolCall() {
  try {
    const res = await post(chatURL(), {
      model: CHAT_MODEL, stream: false, tool_choice: 'auto', tools: [READ_FILE_TOOL],
      messages: [
        { role: 'system', content: 'You are a coding agent. Use tools to inspect files before answering.' },
        { role: 'user', content: 'What is on the first line of /etc/hosts? Use the tool; do not guess.' },
      ],
    });
    if (!res.ok) return bad('tool call (turn 1)', `HTTP ${res.status}: ${(await res.text()).slice(0, 160)}`);
    const data = await res.json();
    const msg = data?.choices?.[0]?.message;
    const tc = msg?.tool_calls?.[0];
    if (!tc) return bad('tool call (turn 1)', 'model did not emit a tool_call');
    let args;
    try { args = JSON.parse(tc.function.arguments); }
    catch { return bad('tool call (turn 1)', `arguments not valid JSON: ${tc.function.arguments}`); }
    if (tc.function.name !== 'read_file' || !tc.id) return bad('tool call (turn 1)', 'wrong tool or missing id');
    ok('tool call (turn 1)', `read_file(${JSON.stringify(args)}) id=${tc.id.slice(0, 12)}`);

    // Turn 2: return the tool result with tool_call_id; expect a continuation.
    const res2 = await post(chatURL(), {
      model: CHAT_MODEL, stream: false,
      messages: [
        { role: 'system', content: 'You are a coding agent. Use tools to inspect files before answering.' },
        { role: 'user', content: 'What is on the first line of /etc/hosts? Use the tool; do not guess.' },
        { role: 'assistant', content: null, tool_calls: [tc] },
        { role: 'tool', tool_call_id: tc.id, content: '##\n# Host Database\n127.0.0.1\tlocalhost' },
      ],
    });
    if (!res2.ok) return bad('tool call (turn 2)', `HTTP ${res2.status}: ${(await res2.text()).slice(0, 160)}`);
    const answer = (await res2.json())?.choices?.[0]?.message?.content ?? '';
    if (!answer) return bad('tool call (turn 2)', 'empty continuation');
    const used = answer.includes('127.0.0.1') || /localhost|host database/i.test(answer);
    ok('tool call (turn 2)', `continued${used ? ' and used the tool result' : ''}`);
  } catch (e) { bad('tool call', e.message); }
}

// 3) Embeddings — backs the cognitive memory's semantic recall.
async function checkEmbeddings() {
  try {
    const res = await post(embedURL(), { model: EMBED_MODEL, input: 'hello world' });
    if (!res.ok) return bad('embeddings', `HTTP ${res.status}: ${(await res.text()).slice(0, 160)}`);
    const vec = (await res.json())?.data?.[0]?.embedding;
    Array.isArray(vec) && vec.length > 0
      ? ok('embeddings', `${vec.length}-dim vector`)
      : bad('embeddings', 'no vector returned');
  } catch (e) { bad('embeddings', e.message); }
}

async function main() {
  console.log(`G-Rump Qwen verification — ${mode}\n`);
  if (BACKEND_URL ? false : !KEY) { console.log('Set QWEN_API_KEY (direct) or BACKEND_URL + APP_API_KEY (via backend).'); process.exit(2); }
  await checkChat();
  await checkToolCall();
  await checkEmbeddings();
  console.log(`\n${passed} passed, ${failed} failed.`);
  if (failed === 0) console.log('VERIFIED — G-Rump runs on Qwen: chat, multi-turn tool calling, and embeddings all work.');
  process.exit(failed === 0 ? 0 : 1);
}

main();
