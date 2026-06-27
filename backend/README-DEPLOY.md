# Deploying the G-Rump Qwen backend on Alibaba Cloud

A stateless Node/Express proxy that forwards chat completions and embeddings to
**Qwen on Alibaba Cloud (DashScope)**. All Alibaba Cloud calls are centralized
in [`alibaba.js`](./alibaba.js) — that's the file that proves the backend uses
Alibaba Cloud services.

## Endpoints

| Method | Path | Notes |
|---|---|---|
| `GET`  | `/api/health` | Reports backend + the `*.aliyuncs.com` host it targets |
| `POST` | `/api/v1/chat/completions` | OpenAI-compatible; streams (SSE) when `stream:true`; tool calls pass through |
| `POST` | `/api/v1/embeddings` | `{ input, model? }` → Qwen `text-embedding-v4` |

Chat/embeddings require `QWEN_API_KEY`. If `APP_API_KEY` is set, callers must send
`Authorization: Bearer <APP_API_KEY>`.

## Environment

See [`.env.example`](./.env.example). Required: `QWEN_API_KEY`. Production: also
set `APP_API_KEY` and `CORS_ORIGIN`. Mainland accounts: set `QWEN_BASE_URL` to
`https://dashscope.aliyuncs.com/compatible-mode/v1`.

## Build the image

```bash
cd backend
docker build -t grump-qwen-backend .
```

## Option A — Alibaba Cloud ECS (Ubuntu VM + container)

```bash
# On the ECS instance (Ubuntu 22.04, Docker installed):
docker run -d --name grump-qwen \
  -p 3042:3042 \
  -e QWEN_API_KEY=sk-...                                  \
  -e QWEN_BASE_URL=https://dashscope-intl.aliyuncs.com/compatible-mode/v1 \
  -e APP_API_KEY=<long-random-string>                     \
  -e NODE_ENV=production                                  \
  grump-qwen-backend
```

Put nginx (or Alibaba SLB) in front for TLS, and open port 443 in the ECS
security group. Point the desktop app's backend base URL at `https://<host>`.

## Option B — Alibaba Cloud Function Compute / Serverless

Push the image to **Alibaba Container Registry (ACR)** and deploy it as a
container-based Function Compute service (HTTP trigger), or deploy the repo to
Serverless App Engine (SAE). Set the env vars in the console. The app reads
`PORT` and listens on `0.0.0.0`, so it works behind FC's HTTP trigger.

## Verify (deployment proof)

```bash
# Health — shows the aliyuncs.com host the backend calls
curl https://<host>/api/health

# Chat — a real Qwen response proves the Alibaba Cloud call
curl -s https://<host>/api/v1/chat/completions \
  -H "Authorization: Bearer $APP_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen-coder-plus","messages":[{"role":"user","content":"say hi"}]}'

# Embeddings
curl -s https://<host>/api/v1/embeddings \
  -H "Authorization: Bearer $APP_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input":"hello"}'
```

Record the `/api/health` + a streamed chat response as the hackathon's
"backend running on Alibaba Cloud, calling Qwen" proof.
