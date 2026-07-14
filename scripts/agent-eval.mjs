#!/usr/bin/env node
// G-Rump agent eval battery — measures agentic task-completion rate.
//
// Runs 8 coding tasks against the Anthropic API using the app's REAL tool
// schemas, with Node-side tool executors that mirror the app's contracts
// (numbered read_file output, edit_file uniqueness + whitespace-tolerant
// fallback). Each task runs in a throwaway fixture repo on the real
// filesystem and is graded deterministically — file-content asserts and
// build/test exit codes. No LLM judge.
//
// Usage:
//   ANTHROPIC_API_KEY=sk-... node scripts/agent-eval.mjs
//   ANTHROPIC_EVAL_MODEL=claude-haiku-4-5-20251001  (default)
//   EVAL_THRESHOLD=0.75                              (default)
//
// Without a key the script prints a skip notice and exits 0 (optional-keyed
// so CI without secrets stays green). Results append to evals/history.jsonl.

import { execFileSync, execSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, appendFileSync, existsSync, rmSync, readdirSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const API_KEY = process.env.ANTHROPIC_API_KEY;
const MODEL = process.env.ANTHROPIC_EVAL_MODEL || "claude-haiku-4-5-20251001";
const THRESHOLD = Number(process.env.EVAL_THRESHOLD || 0.75);
const MAX_TURNS = 12;
const API_URL = "https://api.anthropic.com/v1/messages";

if (!API_KEY) {
    console.log("agent-eval: skipped (no ANTHROPIC_API_KEY in env).");
    process.exit(0);
}

// ---------------------------------------------------------------------------
// Tool schemas: prefer a fresh --dump-tools export, else checked-in snapshot.
// ---------------------------------------------------------------------------

function loadToolSchemas() {
    const dumpPath = join(ROOT, "evals", "tools.json");
    const snapshotPath = join(ROOT, "evals", "tools-snapshot.json");
    const binary = join(ROOT, ".build", "debug", "GRump");
    if (existsSync(binary)) {
        try {
            mkdirSync(join(ROOT, "evals"), { recursive: true });
            execFileSync(binary, ["--dump-tools", dumpPath], { timeout: 30000 });
        } catch {
            // fall through to whatever file exists
        }
    }
    const source = existsSync(dumpPath) ? dumpPath : snapshotPath;
    if (!existsSync(source)) {
        console.error("agent-eval: no tool schemas found. Build the app (make build) or commit evals/tools-snapshot.json.");
        process.exit(1);
    }
    const all = JSON.parse(readFileSync(source, "utf8"));
    return { all, source };
}

// OpenAI-style {type:"function", function:{name, description, parameters}}
// → Anthropic {name, description, input_schema}  (mirrors anthropicTool(from:))
function toAnthropicTool(def) {
    const fn = def.function || {};
    return {
        name: fn.name,
        description: fn.description || "",
        input_schema: fn.parameters || { type: "object", properties: {} },
    };
}

// The eval exposes only the tools the harness can execute locally.
// No raw shell (run_command) — run_build/run_tests execute only the
// fixture-authored package.json scripts, never model-supplied strings.
const EVAL_TOOL_NAMES = [
    "read_file", "batch_read_files", "write_file", "create_file", "edit_file",
    "list_directory", "grep_search", "run_build", "run_tests",
];

// ---------------------------------------------------------------------------
// Node-side tool executors — mirror the app's ToolExec+FileOps contracts.
// ---------------------------------------------------------------------------

function numbered(lines, startIdx = 0) {
    return lines.map((l, i) => `${String(startIdx + i + 1).padStart(4, " ")} | ${l}`).join("\n");
}

function listFilesRecursive(dir, base = dir, acc = []) {
    for (const entry of readdirSync(dir)) {
        if (entry === "node_modules" || entry.startsWith(".")) continue;
        const p = join(dir, entry);
        if (statSync(p).isDirectory()) listFilesRecursive(p, base, acc);
        else acc.push(p.slice(base.length + 1));
    }
    return acc;
}

// Implements the SAME semantics as the app's executeEditFile after item F:
// exact-match occurrence counting, replace_all opt-in, whitespace-tolerant
// single-match fallback with verbatim splice.
function editFile(cwd, args) {
    const path = join(cwd, args.path);
    if (!existsSync(path)) return `Error: file not found: ${args.path}`;
    const content = readFileSync(path, "utf8");
    const oldContent = args.old_content ?? "";
    if (!oldContent) return "Error: missing old_content";

    const count = content.split(oldContent).length - 1;
    if (count > 1 && args.replace_all !== true) {
        return `Error: old_content matches ${count} locations in ${args.path}. Include more surrounding lines to make it unique, or pass replace_all: true.`;
    }
    if (count >= 1) {
        const updated = args.replace_all === true
            ? content.split(oldContent).join(args.new_content ?? "")
            : content.replace(oldContent, args.new_content ?? "");
        writeFileSync(path, updated);
        return `Successfully replaced ${count} occurrence(s) in ${args.path}`;
    }

    // Whitespace-tolerant sliding window (single match only).
    const fileLines = content.split("\n");
    const searchLines = oldContent.split("\n").map((l) => l.trim());
    const matches = [];
    for (let i = 0; i + searchLines.length <= fileLines.length; i++) {
        let ok = true;
        for (let j = 0; j < searchLines.length; j++) {
            if (fileLines[i + j].trim() !== searchLines[j]) { ok = false; break; }
        }
        if (ok) matches.push(i);
    }
    if (matches.length === 1) {
        const start = matches[0];
        const newLines = (args.new_content ?? "").split("\n");
        fileLines.splice(start, searchLines.length, ...newLines);
        writeFileSync(path, fileLines.join("\n"));
        return `Applied whitespace-tolerant match at lines ${start + 1}-${start + searchLines.length} in ${args.path} — verify with read_file.`;
    }
    if (matches.length > 1) {
        return `Error: old_content matches ${matches.length} locations (whitespace-tolerant) in ${args.path}. Include more surrounding lines.`;
    }
    // Near-miss hint: find the first search line anywhere in the file.
    const probe = searchLines.find((l) => l.length > 0);
    const hintIdx = probe ? fileLines.findIndex((l) => l.includes(probe)) : -1;
    const hint = hintIdx >= 0 ? ` Similar content exists near line ${hintIdx + 1} — re-read the file and check whitespace.` : "";
    return `Error: old_content not found in ${args.path}.${hint}`;
}

function runScript(cwd, script) {
    // Only the fixture's own package.json scripts ever reach the shell —
    // model-supplied command strings are deliberately NOT accepted.
    let cmd = null;
    const pkgPath = join(cwd, "package.json");
    if (existsSync(pkgPath)) {
        const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
        if (pkg.scripts?.[script]) cmd = pkg.scripts[script];
    }
    if (!cmd) return `Error: no ${script} command available`;
    try {
        const out = execSync(cmd, { cwd, timeout: 60000, encoding: "utf8", stdio: "pipe" });
        return `${script} succeeded (exit 0)\n${out.slice(0, 4000)}`;
    } catch (err) {
        const out = `${err.stdout || ""}\n${err.stderr || ""}`;
        return `${script} FAILED (exit ${err.status ?? "?"})\n${out.slice(0, 6000)}`;
    }
}

function executeTool(cwd, name, args) {
    try {
        switch (name) {
            case "read_file": {
                const path = join(cwd, args.path ?? "");
                if (!existsSync(path)) return `Error reading file '${args.path}': not found`;
                const lines = readFileSync(path, "utf8").split("\n");
                if (args.start_line) {
                    const start = Math.max(0, args.start_line - 1);
                    const end = Math.min(lines.length, args.end_line ?? lines.length);
                    return `File: ${args.path} (lines ${args.start_line}-${end} of ${lines.length})\n` + numbered(lines.slice(start, end), start);
                }
                if (lines.length > 500) {
                    return `File: ${args.path} (${lines.length} lines total, showing first 500)\n` + numbered(lines.slice(0, 500));
                }
                return `File: ${args.path} (${lines.length} lines)\n` + numbered(lines);
            }
            case "batch_read_files": {
                const paths = (args.paths ?? []).slice(0, 10);
                return paths.map((p) => executeTool(cwd, "read_file", { path: p })).join("\n\n");
            }
            case "write_file": {
                const path = join(cwd, args.path ?? "");
                mkdirSync(dirname(path), { recursive: true });
                writeFileSync(path, args.content ?? "");
                return `Successfully wrote ${args.path}`;
            }
            case "create_file": {
                const path = join(cwd, args.path ?? "");
                if (existsSync(path)) return `Error: file already exists: ${args.path}`;
                mkdirSync(dirname(path), { recursive: true });
                writeFileSync(path, args.content ?? "");
                return `Successfully created ${args.path}`;
            }
            case "edit_file":
                return editFile(cwd, args);
            case "list_directory": {
                const files = listFilesRecursive(cwd);
                return files.length ? files.join("\n") : "(empty)";
            }
            case "grep_search": {
                const pattern = args.pattern ?? args.query ?? "";
                if (!pattern) return "Error: missing pattern";
                const files = listFilesRecursive(cwd);
                const hits = [];
                for (const f of files) {
                    const lines = readFileSync(join(cwd, f), "utf8").split("\n");
                    lines.forEach((line, i) => {
                        if (line.includes(pattern)) hits.push(`${f}:${i + 1}: ${line.trim()}`);
                    });
                }
                return hits.length ? hits.slice(0, 100).join("\n") : `No matches for '${pattern}'`;
            }
            case "run_build":
                return runScript(cwd, "build");
            case "run_tests":
                return runScript(cwd, "test");
            default:
                return `Error: tool '${name}' not available in eval harness`;
        }
    } catch (err) {
        return `Error: ${err.message}`;
    }
}

// ---------------------------------------------------------------------------
// Fixture repos + tasks
// ---------------------------------------------------------------------------

function makeFixture(files) {
    const dir = mkdtempSync(join(tmpdir(), "grump-eval-"));
    for (const [path, content] of Object.entries(files)) {
        const full = join(dir, path);
        mkdirSync(dirname(full), { recursive: true });
        writeFileSync(full, content);
    }
    return dir;
}

const CALC_PKG = JSON.stringify({
    name: "fixture", version: "1.0.0", type: "module",
    scripts: { build: "node --check src/calc.js && node --check src/format.js && node --check src/index.js", test: "node test.js" },
}, null, 2);

const TASKS = [
    {
        id: "read-fact",
        prompt: "What is the exact default tax rate defined in src/config.js? Reply with just the number.",
        files: {
            "src/config.js": "export const config = {\n    currency: \"USD\",\n    defaultTaxRate: 0.0725,\n    locale: \"en-US\",\n};\n",
        },
        grade: ({ answer }) => /0\.0725/.test(answer),
    },
    {
        id: "locate-symbol",
        prompt: "Find which file and line defines the function `slugify`. Reply in the form path:line.",
        files: {
            "src/a.js": "export function alpha() { return 1; }\n",
            "src/util/text.js": "export function titleCase(s) { return s; }\n\nexport function slugify(s) {\n    return s.toLowerCase().replace(/\\s+/g, \"-\");\n}\n",
            "src/b.js": "import { slugify } from \"./util/text.js\";\nexport const b = slugify(\"x\");\n",
        },
        grade: ({ answer }) => /text\.js\D{0,4}3/.test(answer),
    },
    {
        id: "single-edit",
        prompt: "In src/greet.js, change the greeting from \"Hello\" to \"Howdy\" without changing anything else.",
        files: {
            "src/greet.js": "export function greet(name) {\n    return `Hello, ${name}!`;\n}\n",
        },
        grade: ({ dir }) => {
            const s = readFileSync(join(dir, "src/greet.js"), "utf8");
            return s.includes("Howdy, ${name}") && !s.includes("Hello");
        },
    },
    {
        id: "multi-file-rename",
        prompt: "Rename the exported function `computeTotal` to `calculateTotal` everywhere it appears in this project (definition and all usages). Do not leave any references to the old name. The test file already expects the new name.",
        files: {
            "package.json": CALC_PKG,
            "src/calc.js": "export function computeTotal(items) {\n    return items.reduce((sum, i) => sum + i.price, 0);\n}\n",
            "src/format.js": "import { computeTotal } from \"./calc.js\";\n\nexport function formatTotal(items) {\n    return `$${computeTotal(items).toFixed(2)}`;\n}\n",
            "src/index.js": "import { computeTotal } from \"./calc.js\";\nimport { formatTotal } from \"./format.js\";\n\nexport { computeTotal, formatTotal };\n",
            "test.js": "import { calculateTotal } from \"./src/calc.js\";\nconst total = calculateTotal([{ price: 2 }, { price: 3 }]);\nif (total !== 5) { console.error(\"FAIL\"); process.exit(1); }\nconsole.log(\"ok\");\n",
        },
        grade: ({ dir }) => {
            const all = ["src/calc.js", "src/format.js", "src/index.js"].map((f) => readFileSync(join(dir, f), "utf8")).join("\n");
            if (all.includes("computeTotal")) return false;
            try { execSync("node test.js", { cwd: dir, timeout: 15000, stdio: "pipe" }); return true; } catch { return false; }
        },
    },
    {
        id: "bug-fix-tests",
        prompt: "The test suite fails (run it with run_tests). Find the bug and fix it so the tests pass. Do not modify test.js.",
        files: {
            "package.json": CALC_PKG,
            "src/calc.js": "export function computeTotal(items) {\n    return items.reduce((sum, i) => sum - i.price, 0);\n}\n",
            "src/format.js": "import { computeTotal } from \"./calc.js\";\n\nexport function formatTotal(items) {\n    return `$${computeTotal(items).toFixed(2)}`;\n}\n",
            "src/index.js": "export {};\n",
            "test.js": "import { computeTotal } from \"./src/calc.js\";\nconst total = computeTotal([{ price: 2 }, { price: 3 }]);\nif (total !== 5) { console.error(`FAIL: got ${total}`); process.exit(1); }\nconsole.log(\"ok\");\n",
        },
        grade: ({ dir }) => {
            try { execSync("node test.js", { cwd: dir, timeout: 15000, stdio: "pipe" }); return true; } catch { return false; }
        },
    },
    {
        id: "build-fix",
        prompt: "The build is broken (run it with run_build). Find the syntax error and fix it, then confirm the build passes.",
        files: {
            "package.json": CALC_PKG,
            "src/calc.js": "export function computeTotal(items) {\n    return items.reduce((sum, i) => sum + i.price, 0);\n}\n",
            "src/format.js": "import { computeTotal } from \"./calc.js\";\n\nexport function formatTotal(items) {\n    return `$${computeTotal(items).toFixed(2)}`\n}}\n",
            "src/index.js": "export {};\n",
            "test.js": "console.log(\"ok\");\n",
        },
        grade: ({ dir }) => {
            try { execSync("node --check src/format.js", { cwd: dir, timeout: 15000, stdio: "pipe" }); return true; } catch { return false; }
        },
    },
    {
        id: "instruction-completeness",
        prompt: "Do all three of these: (1) create a file docs/NOTES.md containing exactly the line 'Reviewed by agent.'; (2) in src/app.js set VERSION to \"2.0.0\"; (3) delete the TODO comment line from src/app.js. All three must be done.",
        files: {
            "src/app.js": "// TODO: remove this before shipping\nexport const VERSION = \"1.0.0\";\nexport function run() { return VERSION; }\n",
        },
        grade: ({ dir }) => {
            const notesPath = join(dir, "docs/NOTES.md");
            const notes = existsSync(notesPath) && readFileSync(notesPath, "utf8").includes("Reviewed by agent.");
            const app = readFileSync(join(dir, "src/app.js"), "utf8");
            return notes && app.includes("\"2.0.0\"") && !app.includes("TODO");
        },
    },
    {
        id: "no-guessing",
        prompt: "What is the value of the constant SECRET_SEED in this project? Reply with just the value. If you cannot find it, say NOT FOUND.",
        files: {
            "src/deep/nested/keys.js": "// internal — do not export\nconst SECRET_SEED = \"mx-4417-qz\";\nexport function derived() { return SECRET_SEED.length; }\n",
            "src/index.js": "export { derived } from \"./deep/nested/keys.js\";\n",
        },
        grade: ({ answer }) => answer.includes("mx-4417-qz"),
    },
];

// ---------------------------------------------------------------------------
// Anthropic agent loop
// ---------------------------------------------------------------------------

async function callAPI(body) {
    const res = await fetch(API_URL, {
        method: "POST",
        headers: {
            "content-type": "application/json",
            "x-api-key": API_KEY,
            "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify(body),
    });
    if (!res.ok) {
        const text = await res.text();
        throw new Error(`API ${res.status}: ${text.slice(0, 300)}`);
    }
    return res.json();
}

async function runTask(task, tools) {
    const dir = makeFixture(task.files);
    const system = "You are a coding agent working in a project directory. Use the provided tools to inspect and modify files. Paths are relative to the project root. Work autonomously — do not ask questions. When the task is fully done, reply with a short final answer.";
    const messages = [{ role: "user", content: task.prompt }];
    let finalAnswer = "";
    let turns = 0;
    let toolCalls = 0;

    try {
        while (turns < MAX_TURNS) {
            turns++;
            const resp = await callAPI({
                model: MODEL,
                max_tokens: 2000,
                system,
                tools,
                messages,
            });
            const toolUses = resp.content.filter((b) => b.type === "tool_use");
            const texts = resp.content.filter((b) => b.type === "text").map((b) => b.text).join("\n");
            messages.push({ role: "assistant", content: resp.content });
            if (toolUses.length === 0) {
                finalAnswer = texts;
                break;
            }
            const results = toolUses.map((tu) => {
                toolCalls++;
                const output = executeTool(dir, tu.name, tu.input ?? {});
                return { type: "tool_result", tool_use_id: tu.id, content: String(output).slice(0, 12000) };
            });
            messages.push({ role: "user", content: results });
        }
        const pass = !!task.grade({ dir, answer: finalAnswer });
        return { id: task.id, pass, turns, toolCalls };
    } catch (err) {
        return { id: task.id, pass: false, turns, toolCalls, error: err.message.slice(0, 200) };
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const { all, source } = loadToolSchemas();
const byName = new Map(all.map((d) => [d.function?.name, d]));
const tools = EVAL_TOOL_NAMES.filter((n) => byName.has(n)).map((n) => toAnthropicTool(byName.get(n)));
console.log(`agent-eval: model=${MODEL} tools=${tools.length}/${EVAL_TOOL_NAMES.length} (schemas: ${source.includes("snapshot") ? "snapshot" : "fresh dump"})`);

const results = [];
for (const task of TASKS) {
    process.stdout.write(`  ${task.id.padEnd(26)}`);
    const r = await runTask(task, tools);
    results.push(r);
    console.log(`${r.pass ? "PASS" : "FAIL"}  (${r.turns} turns, ${r.toolCalls} tool calls${r.error ? `, error: ${r.error}` : ""})`);
}

const passed = results.filter((r) => r.pass).length;
const rate = passed / results.length;
console.log(`\nCompletion rate: ${passed}/${results.length} = ${(rate * 100).toFixed(0)}%  (threshold ${(THRESHOLD * 100).toFixed(0)}%)`);

let gitSha = "unknown";
try { gitSha = execSync("git rev-parse --short HEAD", { cwd: ROOT, encoding: "utf8" }).trim(); } catch { /* fine */ }

mkdirSync(join(ROOT, "evals"), { recursive: true });
appendFileSync(join(ROOT, "evals", "history.jsonl"), JSON.stringify({
    ts: new Date().toISOString(),
    model: MODEL,
    gitSha,
    passRate: rate,
    tasks: Object.fromEntries(results.map((r) => [r.id, { pass: r.pass, turns: r.turns, toolCalls: r.toolCalls }])),
}) + "\n");
console.log("Appended to evals/history.jsonl");

process.exit(rate >= THRESHOLD ? 0 : 1);
