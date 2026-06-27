// ─────────────────────────────────────────────────────────────────────────
// server.js — G-Rump's minimal Qwen backend.
//
// A thin, stateless proxy that forwards chat completions and embeddings to
// Qwen on Alibaba Cloud (see alibaba.js). No accounts, billing, or database —
// the desktop app holds all state; this exists to (a) keep the Qwen key off
// client machines and (b) be the deployed-on-Alibaba-Cloud backend the
// hackathon requires. Auth is a single shared bearer token (APP_API_KEY).
// ─────────────────────────────────────────────────────────────────────────

import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { qwenChatCompletions, qwenEmbeddings, isAlibabaConfigured, alibabaHost } from './alibaba.js';

const app = express();
const isProduction = process.env.NODE_ENV === 'production';
const APP_API_KEY = process.env.APP_API_KEY || '';

app.use(helmet({ contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));

const corsOrigin = process.env.CORS_ORIGIN;
app.use(cors({
  origin: corsOrigin ? corsOrigin.split(',').map(s => s.trim()) : true,
  credentials: true,
}));

app.use(express.json({ limit: '4mb' }));

app.use('/api/', rateLimit({ windowMs: 60 * 1000, max: 120, standardHeaders: true }));

function apiError(res, status, code, message) {
  return res.status(status).json({ error: { code, message } });
}

// Shared-secret gate. If APP_API_KEY is unset (local dev), the gate is open.
function requireAppKey(req, res, next) {
  if (!APP_API_KEY) return next();
  const auth = req.headers['authorization'] || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (token !== APP_API_KEY) return apiError(res, 401, 'unauthorized', 'Invalid or missing API key');
  next();
}

// MARK: - Health

app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    backend: 'qwen',
    alibabaHost: alibabaHost(),
    qwenConfigured: isAlibabaConfigured(),
    uptime: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
  });
});

// MARK: - Chat completions (Qwen, streaming passthrough)

app.post('/api/v1/chat/completions', requireAppKey, async (req, res) => {
  const body = req.body;
  if (!body || typeof body !== 'object') {
    return apiError(res, 400, 'invalid_request', 'Request body must be a JSON object');
  }
  if (!body.model || typeof body.model !== 'string') {
    return apiError(res, 400, 'missing_model', 'model field is required');
  }
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    return apiError(res, 400, 'missing_messages', 'messages must be a non-empty array');
  }
  if (!isAlibabaConfigured()) {
    return apiError(res, 503, 'qwen_unconfigured', 'QWEN_API_KEY is not set on the server');
  }

  try {
    const upstream = await qwenChatCompletions(body);
    if (!upstream.ok) {
      const text = await upstream.text();
      return res.status(upstream.status).send(text);
    }

    // Non-streaming: forward JSON as-is.
    if (body.stream !== true) {
      const data = await upstream.json();
      return res.status(upstream.status).json(data);
    }

    // Streaming: pipe the SSE body straight through (tool_calls survive intact).
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders?.();

    const reader = upstream.body.getReader();
    const decoder = new TextDecoder();
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        res.write(decoder.decode(value, { stream: true }));
        res.flush?.();
      }
    } finally {
      res.end();
    }
  } catch (err) {
    console.error('Chat proxy error:', err);
    if (!res.headersSent) apiError(res, 502, 'upstream_error', 'Failed to reach Qwen on Alibaba Cloud');
    else res.end();
  }
});

// MARK: - Embeddings (Qwen, for the desktop app's semantic memory)

app.post('/api/v1/embeddings', requireAppKey, async (req, res) => {
  const { input, model } = req.body || {};
  if (input == null || (typeof input !== 'string' && !Array.isArray(input))) {
    return apiError(res, 400, 'invalid_input', 'input must be a string or array of strings');
  }
  if (!isAlibabaConfigured()) {
    return apiError(res, 503, 'qwen_unconfigured', 'QWEN_API_KEY is not set on the server');
  }
  try {
    const upstream = await qwenEmbeddings(input, model);
    const data = await upstream.json();
    return res.status(upstream.status).json(data);
  } catch (err) {
    console.error('Embeddings proxy error:', err);
    return apiError(res, 502, 'upstream_error', 'Failed to reach Qwen on Alibaba Cloud');
  }
});

// MARK: - Boot

// Only bind a port when run directly (node server.js / Docker). When imported
// (Vercel's api/index.js, or tests), just export the app without listening.
const isDirectRun = process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/^\//, ''));
if (isDirectRun) {
  const port = process.env.PORT || 3042;
  const server = app.listen(port, () => {
    console.log(`G-Rump Qwen backend listening on http://0.0.0.0:${port} -> ${alibabaHost()}`);
    if (!isAlibabaConfigured()) console.warn('WARNING: QWEN_API_KEY not set. Chat/embeddings will return 503.');
    if (isProduction && !APP_API_KEY) console.warn('WARNING: APP_API_KEY not set in production. The proxy is open.');
  });

  function shutdown(signal) {
    console.log(`\n${signal} received. Shutting down...`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10000);
  }
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

// Global error handler.
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error('Unhandled error:', err);
  if (!res.headersSent) res.status(500).json({ error: { code: 'internal_error', message: 'Internal server error' } });
});

export default app;
