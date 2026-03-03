import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { getDb, initDatabase, TIERS } from './db.js';
import { signToken, authMiddleware, verifyGoogleIdToken, getOrCreateUserByGoogle, replenishCreditsIfNeeded, refreshToken, hashPassword, verifyPassword, getOrCreateUserByEmail } from './auth.js';
import { getUserByEmail } from './db.js';
import { proxyChat } from './proxy.js';
import { createCheckoutSession, createPortalSession, handleStripeWebhook, getUsageAnalytics } from './stripe.js';

const app = express();

// Security headers
app.use(helmet({
  contentSecurityPolicy: false, // Allow native app requests
  crossOriginEmbedderPolicy: false,
}));

// CORS: locked down in production, open in development
const isProduction = process.env.NODE_ENV === 'production';
const corsOrigin = process.env.CORS_ORIGIN;
if (isProduction && !corsOrigin) {
  console.warn('WARNING: CORS_ORIGIN not set in production. Cross-origin requests will be rejected.');
}
app.use(cors({
  origin: corsOrigin ? corsOrigin.split(',').map(s => s.trim()) : (isProduction ? false : true),
  credentials: true,
}));

// Audit logger
function auditLog(event, details = {}) {
  const entry = { timestamp: new Date().toISOString(), event, ...details };
  console.log(`[AUDIT] ${JSON.stringify(entry)}`);
}
app.use(express.json({
  limit: '2mb',
  verify: (req, _res, buf) => {
    // Preserve raw body for Stripe webhook signature verification
    if (req.originalUrl === '/api/billing/webhook') {
      req.rawBody = buf;
    }
  },
}));

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  message: { error: 'Too many attempts. Try again later.' },
  standardHeaders: true,
});
app.use('/api/auth', authLimiter);

const apiLimiter = rateLimit({
  windowMs: 1 * 60 * 1000,
  max: 120,
  standardHeaders: true,
});
app.use('/api/', apiLimiter);

// Middleware to ensure DB is initialized on every request (lazy init for serverless)
app.use(async (_req, _res, next) => {
  try {
    await ensureDb();
    next();
  } catch (err) {
    console.error('DB init error:', err);
    next(err);
  }
});

// MARK: - Health Check

app.get('/api/health', async (_req, res) => {
  const db = getDb();
  try {
    await db.get('SELECT 1 as ok');
    res.json({
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptime: Math.floor(process.uptime()),
    });
  } catch (err) {
    res.status(503).json({
      status: 'degraded',
      error: 'database_unavailable',
      message: 'Database health check failed',
    });
  }
});

// MARK: - Structured Error Helper

function apiError(res, status, code, message) {
  return res.status(status).json({ error: { code, message } });
}

// MARK: - Auth

app.post('/api/auth/google', async (req, res) => {
  const { idToken } = req.body || {};
  if (!idToken || typeof idToken !== 'string') {
    auditLog('auth_failed', { reason: 'missing_token', ip: req.ip });
    return res.status(400).json({ error: 'Google ID token required' });
  }
  try {
    const { googleId, email } = await verifyGoogleIdToken(idToken);
    const { user, isNew } = await getOrCreateUserByGoogle(googleId, email);
    auditLog('auth_success', { userId: user.id, email: user.email, isNew });
    const db = getDb();
    await replenishCreditsIfNeeded(db, user.id, user.credits_balance, user.credits_replenished_at);
    const updated = await db.get('SELECT credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?', [user.id]);
    const token = signToken({ userId: user.id });
    const profile = updated ?? user;
    return res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        tier: user.tier,
        creditsBalance: updated?.credits_balance ?? user.credits_balance,
        creditsReplenishedAt: updated?.credits_replenished_at ?? user.credits_replenished_at,
        displayName: profile.display_name ?? null,
        avatarUrl: profile.avatar_url ?? null,
      },
      isNew: !!isNew,
    });
  } catch (err) {
    auditLog('auth_failed', { reason: err.message, ip: req.ip });
    if (err.message?.includes('Invalid') || err.message?.includes('token')) {
      return res.status(401).json({ error: err.message });
    }
    console.error('Google auth error:', err);
    return res.status(500).json({ error: 'Sign-in failed. Try again.' });
  }
});

// MARK: - Email Auth

app.post('/api/auth/signup', async (req, res) => {
  const { email, password, displayName } = req.body || {};
  if (!email || typeof email !== 'string') {
    return apiError(res, 400, 'missing_email', 'Email is required');
  }
  if (!password || typeof password !== 'string') {
    return apiError(res, 400, 'missing_password', 'Password is required');
  }
  // Validate email format
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email.trim())) {
    return apiError(res, 400, 'invalid_email', 'Invalid email format');
  }
  // Validate password length
  if (password.length < 8) {
    return apiError(res, 400, 'weak_password', 'Password must be at least 8 characters');
  }
  try {
    // Check if email already exists
    const existing = await getUserByEmail(email.trim().toLowerCase());
    if (existing) {
      auditLog('signup_failed', { reason: 'email_exists', email: email.trim().toLowerCase(), ip: req.ip });
      return apiError(res, 409, 'email_exists', 'An account with this email already exists. Please sign in.');
    }
    const passwordHash = await hashPassword(password);
    const { user } = await getOrCreateUserByEmail(email.trim().toLowerCase(), passwordHash);
    // Update display name if provided
    if (displayName && typeof displayName === 'string' && displayName.trim()) {
      const db = getDb();
      await db.run('UPDATE users SET display_name = ?, updated_at = ? WHERE id = ?', [displayName.trim(), Date.now(), user.id]);
    }
    const db = getDb();
    await replenishCreditsIfNeeded(db, user.id, user.credits_balance, user.credits_replenished_at);
    const updated = await db.get('SELECT credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?', [user.id]);
    const token = signToken({ userId: user.id });
    auditLog('signup_success', { userId: user.id, email: email.trim().toLowerCase() });
    const profile = updated ?? user;
    return res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        tier: user.tier,
        creditsBalance: updated?.credits_balance ?? user.credits_balance,
        creditsReplenishedAt: updated?.credits_replenished_at ?? user.credits_replenished_at,
        displayName: profile.display_name ?? displayName?.trim() ?? null,
        avatarUrl: profile.avatar_url ?? null,
      },
      isNew: true,
    });
  } catch (err) {
    auditLog('signup_failed', { reason: err.message, ip: req.ip });
    console.error('Signup error:', err);
    return apiError(res, 500, 'signup_failed', 'Sign-up failed. Try again.');
  }
});

app.post('/api/auth/login', async (req, res) => {
  const { email, password } = req.body || {};
  if (!email || typeof email !== 'string') {
    return apiError(res, 400, 'missing_email', 'Email is required');
  }
  if (!password || typeof password !== 'string') {
    return apiError(res, 400, 'missing_password', 'Password is required');
  }
  try {
    const user = await getUserByEmail(email.trim().toLowerCase());
    if (!user) {
      auditLog('login_failed', { reason: 'user_not_found', email: email.trim().toLowerCase(), ip: req.ip });
      return apiError(res, 401, 'invalid_credentials', 'Invalid email or password');
    }
    if (!user.password_hash) {
      auditLog('login_failed', { reason: 'no_password_set', email: email.trim().toLowerCase(), ip: req.ip });
      return apiError(res, 401, 'invalid_credentials', 'This account uses Google Sign-In. Please sign in with Google.');
    }
    const valid = await verifyPassword(password, user.password_hash);
    if (!valid) {
      auditLog('login_failed', { reason: 'wrong_password', email: email.trim().toLowerCase(), ip: req.ip });
      return apiError(res, 401, 'invalid_credentials', 'Invalid email or password');
    }
    const db = getDb();
    await replenishCreditsIfNeeded(db, user.id, user.credits_balance, user.credits_replenished_at);
    const updated = await db.get('SELECT credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?', [user.id]);
    const token = signToken({ userId: user.id });
    auditLog('login_success', { userId: user.id, email: user.email });
    const profile = updated ?? user;
    return res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        tier: user.tier,
        creditsBalance: updated?.credits_balance ?? user.credits_balance,
        creditsReplenishedAt: updated?.credits_replenished_at ?? user.credits_replenished_at,
        displayName: profile.display_name ?? null,
        avatarUrl: profile.avatar_url ?? null,
      },
      isNew: false,
    });
  } catch (err) {
    auditLog('login_failed', { reason: err.message, ip: req.ip });
    console.error('Login error:', err);
    return apiError(res, 500, 'login_failed', 'Sign-in failed. Try again.');
  }
});

app.post('/api/auth/refresh', async (req, res) => {
  const { token: oldToken } = req.body || {};
  if (!oldToken || typeof oldToken !== 'string') {
    return apiError(res, 400, 'missing_token', 'Token is required');
  }
  const newToken = refreshToken(oldToken);
  if (!newToken) {
    return apiError(res, 401, 'refresh_failed', 'Token cannot be refreshed. Please sign in again.');
  }
  auditLog('token_refreshed', { ip: req.ip });
  return res.json({ token: newToken });
});

app.get('/api/me', authMiddleware, async (req, res) => {
  const db = getDb();
  const user = await db.get('SELECT id, email, tier, credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?', [req.userId]);
  if (!user) return res.status(401).end();
  await replenishCreditsIfNeeded(db, user.id, user.credits_balance, user.credits_replenished_at);
  const updated = await db.get('SELECT credits_balance, credits_replenished_at FROM users WHERE id = ?', [user.id]);
  const tierInfo = TIERS[user.tier] ?? TIERS.free;
  return res.json({
    id: user.id,
    email: user.email,
    tier: user.tier,
    tierName: tierInfo.name,
    creditsBalance: updated?.credits_balance ?? user.credits_balance,
    creditsPerMonth: tierInfo.creditsPerMonth,
    creditsReplenishedAt: updated?.credits_replenished_at ?? user.credits_replenished_at,
    displayName: user.display_name ?? null,
    avatarUrl: user.avatar_url ?? null,
  });
});

app.patch('/api/me', authMiddleware, async (req, res) => {
  const db = getDb();
  const { displayName, avatarUrl } = req.body || {};
  const updates = [];
  const args = [];
  if (typeof displayName === 'string') {
    if (displayName.length > 200) {
      return apiError(res, 400, 'invalid_display_name', 'Display name must be 200 characters or less');
    }
    updates.push('display_name = ?');
    args.push(displayName.trim() || null);
  }
  if (typeof avatarUrl === 'string') {
    if (avatarUrl.length > 2048) {
      return apiError(res, 400, 'invalid_avatar_url', 'Avatar URL must be 2048 characters or less');
    }
    const trimmedUrl = avatarUrl.trim();
    if (trimmedUrl) {
      try {
        const parsed = new URL(trimmedUrl);
        if (parsed.protocol !== 'https:') {
          return apiError(res, 400, 'invalid_avatar_url', 'Avatar URL must use HTTPS');
        }
      } catch {
        return apiError(res, 400, 'invalid_avatar_url', 'Invalid avatar URL');
      }
    }
    updates.push('avatar_url = ?');
    args.push(trimmedUrl || null);
  }
  if (updates.length === 0) {
    return res.status(400).json({ error: 'No valid profile fields to update' });
  }
  const now = Date.now();
  updates.push('updated_at = ?');
  args.push(now);
  args.push(req.userId);
  await db.run(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`, args);
  const user = await db.get('SELECT id, email, tier, credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?', [req.userId]);
  const tierInfo = TIERS[user.tier] ?? TIERS.free;
  return res.json({
    id: user.id,
    email: user.email,
    tier: user.tier,
    tierName: tierInfo.name,
    creditsBalance: user.credits_balance,
    creditsPerMonth: tierInfo.creditsPerMonth,
    creditsReplenishedAt: user.credits_replenished_at ?? null,
    displayName: user.display_name ?? null,
    avatarUrl: user.avatar_url ?? null,
  });
});

app.get('/api/me/usage', authMiddleware, async (req, res) => {
  const db = getDb();
  const rows = await db.get(`
    SELECT SUM(credits_deducted) as total_credits, COUNT(*) as request_count,
           SUM(prompt_tokens) as total_prompt, SUM(completion_tokens) as total_completion
    FROM usage_log WHERE user_id = ?
  `, [req.userId]);
  const monthAgo = Date.now() - 30 * 24 * 60 * 60 * 1000;
  const recent = await db.get(`
    SELECT SUM(credits_deducted) as credits_this_month, COUNT(*) as requests_this_month
    FROM usage_log WHERE user_id = ? AND created_at >= ?
  `, [req.userId, monthAgo]);

  // Per-model breakdown (last 30 days)
  const byModel = await db.all(`
    SELECT model, COUNT(*) as requests, SUM(credits_deducted) as credits,
           SUM(prompt_tokens) as prompt_tokens, SUM(completion_tokens) as completion_tokens
    FROM usage_log WHERE user_id = ? AND created_at >= ?
    GROUP BY model ORDER BY credits DESC
  `, [req.userId, monthAgo]);

  // Daily usage (last 14 days)
  const twoWeeksAgo = Date.now() - 14 * 24 * 60 * 60 * 1000;
  const daily = await db.all(`
    SELECT CAST(created_at / 86400000 AS INTEGER) as day,
           COUNT(*) as requests, SUM(credits_deducted) as credits
    FROM usage_log WHERE user_id = ? AND created_at >= ?
    GROUP BY day ORDER BY day
  `, [req.userId, twoWeeksAgo]);

  return res.json({
    totalCreditsUsed: rows?.total_credits ?? 0,
    requestCount: rows?.request_count ?? 0,
    totalPromptTokens: rows?.total_prompt ?? 0,
    totalCompletionTokens: rows?.total_completion ?? 0,
    creditsThisMonth: recent?.credits_this_month ?? 0,
    requestsThisMonth: recent?.requests_this_month ?? 0,
    byModel,
    dailyUsage: daily,
  });
});

// MARK: - Billing

app.post('/api/billing/checkout', authMiddleware, async (req, res) => {
  const { priceKey, successUrl, cancelUrl } = req.body || {};
  if (!priceKey || typeof priceKey !== 'string') {
    return apiError(res, 400, 'missing_price_key', 'priceKey is required');
  }
  try {
    const db = getDb();
    const user = await db.get('SELECT email FROM users WHERE id = ?', [req.userId]);
    if (!user) return apiError(res, 404, 'user_not_found', 'User not found');
    auditLog('billing_checkout', { userId: req.userId, priceKey });
    const session = await createCheckoutSession(req.userId, user.email, priceKey, successUrl, cancelUrl);
    return res.json({ url: session.url, sessionId: session.id });
  } catch (err) {
    console.error('Checkout error:', err);
    return apiError(res, 500, 'checkout_failed', err.message || 'Failed to create checkout session');
  }
});

app.post('/api/billing/portal', authMiddleware, async (req, res) => {
  const { returnUrl } = req.body || {};
  try {
    const db = getDb();
    const user = await db.get('SELECT email FROM users WHERE id = ?', [req.userId]);
    if (!user) return apiError(res, 404, 'user_not_found', 'User not found');
    const session = await createPortalSession(req.userId, user.email, returnUrl);
    return res.json({ url: session.url });
  } catch (err) {
    console.error('Portal error:', err);
    return apiError(res, 500, 'portal_failed', err.message || 'Failed to create portal session');
  }
});

app.post('/api/billing/webhook', async (req, res) => {
  const signature = req.headers['stripe-signature'];
  if (!signature) return res.status(400).send('Missing stripe-signature header');
  try {
    const result = await handleStripeWebhook(req.rawBody, signature);
    return res.json(result);
  } catch (err) {
    console.error('Webhook error:', err);
    return res.status(400).json({ error: err.message });
  }
});

app.post('/api/billing/credit-pack', authMiddleware, async (req, res) => {
  const { packKey, successUrl, cancelUrl } = req.body || {};
  if (!packKey || typeof packKey !== 'string' || !packKey.startsWith('credits_')) {
    return apiError(res, 400, 'invalid_pack', 'Valid credit pack key required (credits_1000, credits_5000, credits_20000)');
  }
  try {
    const db = getDb();
    const user = await db.get('SELECT email FROM users WHERE id = ?', [req.userId]);
    if (!user) return apiError(res, 404, 'user_not_found', 'User not found');
    const session = await createCheckoutSession(req.userId, user.email, packKey, successUrl, cancelUrl);
    return res.json({ url: session.url, sessionId: session.id });
  } catch (err) {
    console.error('Credit pack error:', err);
    return apiError(res, 500, 'purchase_failed', err.message || 'Failed to create credit pack checkout');
  }
});

app.get('/api/billing/usage', authMiddleware, async (req, res) => {
  try {
    const analytics = await getUsageAnalytics(req.userId);
    const db = getDb();
    const user = await db.get('SELECT tier, credits_balance, subscription_status, subscription_period_end FROM users WHERE id = ?', [req.userId]);
    const tierInfo = TIERS[user?.tier] ?? TIERS.free;
    return res.json({
      tier: user?.tier ?? 'free',
      tierName: tierInfo.name,
      creditsBalance: user?.credits_balance ?? 0,
      creditsPerMonth: tierInfo.creditsPerMonth,
      subscriptionStatus: user?.subscription_status ?? null,
      subscriptionPeriodEnd: user?.subscription_period_end ?? null,
      ...analytics,
    });
  } catch (err) {
    console.error('Usage analytics error:', err);
    return apiError(res, 500, 'analytics_failed', 'Failed to fetch usage analytics');
  }
});

// MARK: - Chat Proxy

app.post('/api/v1/chat/completions', authMiddleware, (req, res) => {
  // Validate chat request body
  const body = req.body;
  if (!body || typeof body !== 'object') {
    return apiError(res, 400, 'invalid_request', 'Request body must be a JSON object');
  }
  if (!body.model || typeof body.model !== 'string') {
    return apiError(res, 400, 'missing_model', 'model field is required and must be a string');
  }
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    return apiError(res, 400, 'missing_messages', 'messages must be a non-empty array');
  }
  for (const msg of body.messages) {
    if (!msg.role || !['system', 'user', 'assistant', 'tool'].includes(msg.role)) {
      return apiError(res, 400, 'invalid_message_role', `Invalid message role: ${msg.role}`);
    }
  }

  proxyChat(req, res).catch(err => {
    console.error('Proxy error:', err);
    if (!res.headersSent) {
      apiError(res, 500, 'proxy_error', 'Failed to proxy request to AI provider');
    }
  });
});

// MARK: - GDPR/CCPA Data Endpoints

app.get('/api/me/export', authMiddleware, async (req, res) => {
  const db = getDb();
  const user = await db.get('SELECT id, email, google_id, tier, credits_balance, credits_replenished_at, display_name, avatar_url, created_at, updated_at FROM users WHERE id = ?', [req.userId]);
  if (!user) return res.status(404).end();
  const usage = await db.all('SELECT model, prompt_tokens, completion_tokens, credits_deducted, created_at FROM usage_log WHERE user_id = ? ORDER BY created_at DESC', [req.userId]);
  const purchases = await db.all('SELECT * FROM credit_purchases WHERE user_id = ? ORDER BY created_at DESC', [req.userId]);
  auditLog('data_export', { userId: req.userId });
  return res.json({
    exportDate: new Date().toISOString(),
    profile: user,
    usageLog: usage,
    creditPurchases: purchases,
  });
});

app.delete('/api/me', authMiddleware, async (req, res) => {
  const db = getDb();
  const user = await db.get('SELECT id FROM users WHERE id = ?', [req.userId]);
  if (!user) return res.status(404).end();
  await db.run('DELETE FROM usage_log WHERE user_id = ?', [req.userId]);
  await db.run('DELETE FROM credit_purchases WHERE user_id = ?', [req.userId]);
  await db.run('DELETE FROM users WHERE id = ?', [req.userId]);
  auditLog('account_deleted', { userId: req.userId });
  return res.json({ deleted: true });
});

// MARK: - Data Retention (prune logs older than 90 days)

async function pruneOldUsageLogs() {
  try {
    const db = getDb();
    const cutoff = Date.now() - 90 * 24 * 60 * 60 * 1000;
    const result = await db.run('DELETE FROM usage_log WHERE created_at < ?', [cutoff]);
    if (result.changes > 0) {
      auditLog('retention_prune', { deletedRows: result.changes });
    }
  } catch (err) {
    console.error('Retention prune error:', err);
  }
}

// Initialize database and start server (only when run directly, not when imported by Vercel)
let dbInitialized = false;

async function ensureDb() {
  if (!dbInitialized) {
    await initDatabase();
    dbInitialized = true;
  }
}

// When running directly (not imported as a module for Vercel)
const isDirectRun = process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/^\//, ''));
if (isDirectRun || !process.env.VERCEL) {
  const port = process.env.PORT || 3042;

  ensureDb().then(() => {
    // Run retention prune on startup and every 24 hours
    pruneOldUsageLogs();
    setInterval(pruneOldUsageLogs, 24 * 60 * 60 * 1000);

    const server = app.listen(port, () => {
      console.log(`G-Rump platform listening on http://localhost:${port}`);
      if (!process.env.OPENROUTER_API_KEY) {
        console.warn('WARNING: OPENROUTER_API_KEY not set. Chat proxy will return 503.');
      }
      if (isProduction && !process.env.STRIPE_SECRET_KEY) {
        console.warn('WARNING: STRIPE_SECRET_KEY not set. Billing will return 503.');
      }
    });

    // Graceful shutdown
    function gracefulShutdown(signal) {
      console.log(`\n${signal} received. Shutting down gracefully...`);
      server.close(() => {
        console.log('Server closed.');
        process.exit(0);
      });
      setTimeout(() => {
        console.error('Forced shutdown after timeout.');
        process.exit(1);
      }, 10000);
    }
    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => gracefulShutdown('SIGINT'));
  });
}

// Global error handler — must be after all routes
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error('Unhandled error:', err);
  if (!res.headersSent) {
    res.status(500).json({ error: { code: 'internal_error', message: 'Internal server error' } });
  }
});

// Export for Vercel serverless
export default app;
