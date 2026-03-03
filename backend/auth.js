import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import { randomUUID, scrypt, randomBytes, timingSafeEqual } from 'crypto';
import { promisify } from 'util';
import { getDb, TIERS, getUserByEmail, createEmailUser } from './db.js';

const scryptAsync = promisify(scrypt);

const JWT_SECRET = process.env.JWT_SECRET;
const JWT_EXPIRY = '7d';
const GOOGLE_CLIENT_IDS = (process.env.GOOGLE_CLIENT_ID || process.env.GOOGLE_CLIENT_IDS || '')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

const isProduction = process.env.NODE_ENV === 'production';
if (isProduction && (!JWT_SECRET || JWT_SECRET.length < 32)) {
  throw new Error('JWT_SECRET must be set and at least 32 characters in production');
}
const secret = JWT_SECRET || 'dev-only-change-in-production';

if (isProduction && GOOGLE_CLIENT_IDS.length === 0) {
  throw new Error('GOOGLE_CLIENT_ID or GOOGLE_CLIENT_IDS must be set in production for Google Sign-In');
}

const googleClient = GOOGLE_CLIENT_IDS.length > 0 ? new OAuth2Client() : null;

export function signToken(payload) {
  return jwt.sign(payload, secret, { expiresIn: JWT_EXPIRY });
}

export function verifyToken(token) {
  try {
    return jwt.verify(token, secret);
  } catch {
    return null;
  }
}

/**
 * Refresh a token — accepts recently expired tokens (within 24h grace period)
 * and issues a new token with fresh expiry.
 */
export function refreshToken(oldToken) {
  // First try normal verification
  let payload = verifyToken(oldToken);
  if (payload?.userId) {
    return signToken({ userId: payload.userId });
  }

  // If expired, check if within 24h grace period
  try {
    payload = jwt.verify(oldToken, secret, { ignoreExpiration: true });
    if (!payload?.userId || !payload?.exp) return null;
    const expiredAt = payload.exp * 1000;
    const gracePeriod = 24 * 60 * 60 * 1000; // 24 hours
    if (Date.now() - expiredAt > gracePeriod) return null;
    return signToken({ userId: payload.userId });
  } catch {
    return null;
  }
}

export async function verifyGoogleIdToken(idToken) {
  if (!googleClient || GOOGLE_CLIENT_IDS.length === 0) {
    throw new Error('Google Sign-In is not configured');
  }
  const ticket = await googleClient.verifyIdToken({
    idToken,
    audience: GOOGLE_CLIENT_IDS,
  });
  const payload = ticket.getPayload();
  if (!payload?.sub || !payload?.email) {
    throw new Error('Invalid Google token');
  }
  return { googleId: payload.sub, email: payload.email };
}

export function authMiddleware(req, res, next) {
  const auth = req.headers.authorization;
  const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) {
    return res.status(401).json({ error: 'Missing or invalid authorization' });
  }
  const payload = verifyToken(token);
  if (!payload?.userId) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
  req.userId = payload.userId;
  next();
}

export async function getOrCreateUserByGoogle(googleId, email) {
  const db = getDb();
  const existing = await db.get(
    'SELECT id, email, tier, credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE google_id = ?',
    [googleId]
  );
  if (existing) {
    return { user: existing, isNew: false };
  }
  const id = randomUUID();
  const now = Date.now();
  const initialCredits = TIERS.free.creditsPerMonth;
  await db.run(
    `INSERT INTO users (id, google_id, email, tier, credits_balance, credits_replenished_at, created_at, updated_at)
     VALUES (?, ?, ?, 'free', ?, ?, ?, ?)`,
    [id, googleId, email, initialCredits, now, now, now]
  );
  const user = await db.get(
    'SELECT id, email, tier, credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?',
    [id]
  );
  return { user, isNew: true };
}

/**
 * Hash a password using Node.js built-in crypto.scrypt.
 * Returns a string of the form "salt:hash" (both hex-encoded).
 */
export async function hashPassword(password) {
  const salt = randomBytes(32).toString('hex');
  const derivedKey = await scryptAsync(password, salt, 64);
  return `${salt}:${derivedKey.toString('hex')}`;
}

/**
 * Verify a password against a stored hash (salt:hash format).
 */
export async function verifyPassword(password, storedHash) {
  const [salt, hash] = storedHash.split(':');
  if (!salt || !hash) return false;
  const derivedKey = await scryptAsync(password, salt, 64);
  const hashBuffer = Buffer.from(hash, 'hex');
  return timingSafeEqual(derivedKey, hashBuffer);
}

/**
 * Get or create a user by email for email/password auth.
 * For sign-up: pass passwordHash. For login: use getUserByEmail + verifyPassword.
 */
export async function getOrCreateUserByEmail(email, passwordHash) {
  const existing = await getUserByEmail(email);
  if (existing) {
    return { user: existing, isNew: false };
  }
  const user = await createEmailUser(email, passwordHash, null);
  return { user, isNew: true };
}

export async function replenishCreditsIfNeeded(db, userId, currentBalance, replenishedAt) {
  const tierRow = await db.get('SELECT tier FROM users WHERE id = ?', [userId]);
  if (!tierRow) return currentBalance;
  const tierConfig = TIERS[tierRow.tier] ?? TIERS.free;
  const now = Date.now();
  const monthMs = 30 * 24 * 60 * 60 * 1000;
  const lastReplenish = replenishedAt ?? 0;
  if (now - lastReplenish >= monthMs) {
    const newBalance = (currentBalance ?? 0) + tierConfig.creditsPerMonth;
    const newReplenishedAt = replenishedAt ? lastReplenish + monthMs : now;
    await db.run(
      'UPDATE users SET credits_balance = ?, credits_replenished_at = ?, updated_at = ? WHERE id = ?',
      [newBalance, newReplenishedAt, now, userId]
    );
    return newBalance;
  }
  return currentBalance;
}
