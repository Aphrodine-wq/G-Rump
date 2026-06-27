#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────
// agent-eval.mjs — score Qwen's agentic competence on a small task battery.
//
// Runs the real multi-turn tool-call loop (the same shape G-Rump's agent uses)
// against a MOCK tool environment, so it is fully reproducible on any OS with a
// Qwen key — no Mac, no filesystem side effects. Each scenario gives the model a
// task plus tools; the harness executes the mock tools, feeds results back with
// tool_call_id, and scores whether the model reached the right answer using the
// tools (not by guessing).
//
//   QWEN_API_KEY=sk-...  node scripts/agent-eval.mjs
//   BACKEND_URL=https://<host>  APP_API_KEY=...  node scripts/agent-eval.mjs
//
// Exit 0 if the pass rate meets THRESHOLD (default 0.75).
// ─────────────────────────────────────────────────────────────────────────

const KEY = process.env.QWEN_API_KEY || process.env.DASHSCOPE_API_KEY || '';
const BACKEND_URL = (process.env.BACKEND_URL || '').replace(/\/+$/, '');
const APP_API_KEY = process.env.APP_API_KEY || '';
const DIRECT_BASE = (process.env.QWEN_BASE_URL || 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1').replace(/\/+$/, '');
const MODEL = process.env.QWEN_MODEL || 'qwen-coder-plus';
const THRESHOLD = Number(process.env.EVAL_THRESHOLD || '0.75');
const MAX_TURNS = 6;

const chatURL = () => BACKEND_URL ? `${BACKEND_URL}/api/v1/chat/completions` : `${DIRECT_BASE}/chat/completions`;
const headers = () => ({ Authorization: `Bearer ${BACKEND_URL ? APP_API_KEY : KEY}`, 'Content-Type': 'application/json' });

// --- Mock tool environment (a tiny fake repo) ------------------------------
const FS = {
  '/app/config.yaml': 'name: payments\nport: 8080\ndebug: false\n',
  '/app/src/main.js': "import { add } from './math.js';\nconsole.log(add(2, 2));\n",
  '/app/src/math.js': 'export function add(a, b) { return a - b; } // BUG: should be a + b\n',
  '/app/README.md': '# Payments service\nRun on port 8080.\n',
};
const TOOLS = [
  { type: 'function', function: { name: 'list_directory', description: 'List files under a directory path.', parameters: { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] } } },
  { type: 'function', function: { name: 'read_file', description: 'Read a file at an absolute path.', parameters: { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] } } },
  { type: 'function', function: { name: 'grep_search', description: 'Search file contents for a substring.', parameters: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } } },
];
function runTool(name, args) {
  if (name === 'list_directory') {
    const p = (args.path || '').replace(/\/$/, '');
    const hits = Object.keys(FS).filter(f => f.startsWith(p + '/')).map(f => f.slice(p.length + 1).split('/')[0]);
    return [...new Set(hits)].join('\n') || '(empty)';
  }
  if (name === 'read_file') return FS[args.path] ?? `error: no such file: ${args.path}`;
  if (name === 'grep_search') {
    const q = (args.query || '').toLowerCase();
    return Object.entries(FS).filter(([, c]) => c.toLowerCase().includes(q)).map(([f]) => f).join('\n') || '(no matches)';
  }
  return `error: unknown tool ${name}`;
}

// --- Scenarios (task + grader) ---------------------------------------------
const SCENARIOS = [
  { id: 'single-read', task: 'What port does the service run on? Read /app/config.yaml; do not guess.',
    grade: a => /8080/.test(a) },
  { id: 'discover+read', task: 'List /app/src, then read the entry file and tell me what it imports.',
    grade: a => /math/i.test(a) && /add/i.test(a) },
  { id: 'find-bug', task: 'There is a bug in /app/src/math.js. Read it and state the bug in one sentence.',
    grade: a => /(a \+ b|should be.*\+|minus|subtract|-)/i.test(a) && /add/i.test(a) },
  { id: 'grep-locate', task: 'Which files mention "port"? Use grep_search.',
    grade: a => /config\.yaml/i.test(a) && /readme/i.test(a) },
];

async function post(body) {
  const res = await fetch(chatURL(), { method: 'POST', headers: headers(), body: JSON.stringify(body) });
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(0, 160)}`);
  return res.json();
}

async function runScenario(s) {
  const messages = [
    { role: 'system', content: 'You are a coding agent. Inspect files with the provided tools before answering. Never guess file contents.' },
    { role: 'user', content: s.task },
  ];
  let toolCallsMade = 0;
  for (let turn = 0; turn < MAX_TURNS; turn++) {
    const data = await post({ model: MODEL, stream: false, tool_choice: 'auto', tools: TOOLS, messages });
    const msg = data?.choices?.[0]?.message;
    if (!msg) return { ok: false, reason: 'no message', toolCallsMade };
    if (msg.tool_calls?.length) {
      messages.push({ role: 'assistant', content: msg.content ?? null, tool_calls: msg.tool_calls });
      for (const tc of msg.tool_calls) {
        toolCallsMade++;
        let args = {};
        try { args = JSON.parse(tc.function.arguments || '{}'); } catch { /* malformed args */ }
        const result = runTool(tc.function.name, args);
        messages.push({ role: 'tool', tool_call_id: tc.id, content: String(result) });
      }
      continue;
    }
    // Final answer.
    const answer = msg.content ?? '';
    const usedTools = toolCallsMade > 0;
    const correct = s.grade(answer);
    return { ok: usedTools && correct, usedTools, correct, toolCallsMade, answer: answer.slice(0, 100) };
  }
  return { ok: false, reason: 'max turns', toolCallsMade };
}

async function main() {
  if (BACKEND_URL ? !APP_API_KEY : !KEY) { console.log('Set QWEN_API_KEY (direct) or BACKEND_URL + APP_API_KEY.'); process.exit(2); }
  console.log(`G-Rump agent eval — model ${MODEL} — ${SCENARIOS.length} scenarios\n`);
  let pass = 0;
  for (const s of SCENARIOS) {
    try {
      const r = await runScenario(s);
      if (r.ok) pass++;
      const tag = r.ok ? 'PASS' : 'FAIL';
      const extra = r.ok ? `${r.toolCallsMade} tool calls` : (r.reason || `usedTools=${r.usedTools} correct=${r.correct}`);
      console.log(`  ${tag}  ${s.id.padEnd(16)} ${extra}`);
      if (!r.ok && r.answer) console.log(`        answer: ${r.answer}`);
    } catch (e) { console.log(`  FAIL  ${s.id.padEnd(16)} ${e.message}`); }
  }
  const rate = pass / SCENARIOS.length;
  console.log(`\nScore: ${pass}/${SCENARIOS.length} (${(rate * 100).toFixed(0)}%) — threshold ${(THRESHOLD * 100).toFixed(0)}%`);
  process.exit(rate >= THRESHOLD ? 0 : 1);
}

main();
