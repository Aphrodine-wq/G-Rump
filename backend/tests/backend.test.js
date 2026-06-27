// Tests for the minimal Qwen backend. No network: we exercise validation,
// the health endpoint, and the unconfigured path. Upstream Alibaba calls are
// not hit (no QWEN_API_KEY in the test env -> the 503 unconfigured path).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import app from '../server.js';

function listen() {
  return new Promise((resolve) => {
    const server = app.listen(0, () => resolve(server));
  });
}

async function call(server, method, path, { body, headers } = {}) {
  const { port } = server.address();
  const res = await fetch(`http://127.0.0.1:${port}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(headers || {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = null; }
  return { status: res.status, json, text };
}

test('health reports the qwen backend + alibaba host', async () => {
  const server = await listen();
  try {
    const { status, json } = await call(server, 'GET', '/api/health');
    assert.equal(status, 200);
    assert.equal(json.backend, 'qwen');
    assert.match(json.alibabaHost, /aliyuncs\.com/);
    assert.equal(typeof json.qwenConfigured, 'boolean');
  } finally { server.close(); }
});

test('chat completions validates the request body', async () => {
  const server = await listen();
  try {
    const noModel = await call(server, 'POST', '/api/v1/chat/completions', { body: { messages: [{ role: 'user', content: 'hi' }] } });
    assert.equal(noModel.status, 400);
    assert.equal(noModel.json.error.code, 'missing_model');

    const noMessages = await call(server, 'POST', '/api/v1/chat/completions', { body: { model: 'qwen-coder-plus' } });
    assert.equal(noMessages.status, 400);
    assert.equal(noMessages.json.error.code, 'missing_messages');
  } finally { server.close(); }
});

test('chat completions returns 503 when Qwen key is unset', async () => {
  const server = await listen();
  try {
    const { status, json } = await call(server, 'POST', '/api/v1/chat/completions', {
      body: { model: 'qwen-coder-plus', messages: [{ role: 'user', content: 'hi' }] },
    });
    assert.equal(status, 503);
    assert.equal(json.error.code, 'qwen_unconfigured');
  } finally { server.close(); }
});

test('embeddings validates input', async () => {
  const server = await listen();
  try {
    const { status, json } = await call(server, 'POST', '/api/v1/embeddings', { body: {} });
    assert.equal(status, 400);
    assert.equal(json.error.code, 'invalid_input');
  } finally { server.close(); }
});
