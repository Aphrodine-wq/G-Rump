# G-Rump Qwen backend — minimal Node container for Alibaba Cloud (ECS or
# Function Compute / Serverless App Engine).
FROM node:20-slim

WORKDIR /app

# Install production deps first for better layer caching.
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

# App source.
COPY . .

ENV NODE_ENV=production
ENV PORT=3042
EXPOSE 3042

CMD ["node", "server.js"]
