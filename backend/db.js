import { createClient } from '@libsql/client';

// Turso / libSQL client — works both locally (file:) and hosted (libsql://)
// Set TURSO_DATABASE_URL and TURSO_AUTH_TOKEN for hosted Turso.
// Falls back to local SQLite file for development.
const url = process.env.TURSO_DATABASE_URL || 'file:data/grump.db';
const authToken = process.env.TURSO_AUTH_TOKEN || undefined;

let client;

export function getClient() {
  if (!client) {
    client = createClient({ url, authToken });
  }
  return client;
}

// Thin async wrapper around @libsql/client to minimize changes to existing code.
// Usage:  const db = getDb();
//         const row = await db.get('SELECT ... WHERE id = ?', [id]);
//         const rows = await db.all('SELECT ...', []);
//         await db.run('INSERT ...', [val1, val2]);
//         await db.exec('CREATE TABLE ...');
export function getDb() {
  const c = getClient();
  return {
    async get(sql, args = []) {
      const result = await c.execute({ sql, args });
      return result.rows[0] ?? null;
    },
    async all(sql, args = []) {
      const result = await c.execute({ sql, args });
      return result.rows;
    },
    async run(sql, args = []) {
      const result = await c.execute({ sql, args });
      return { changes: result.rowsAffected };
    },
    async exec(sql) {
      // exec can contain multiple statements separated by semicolons.
      // @libsql/client's executeMultiple handles this.
      await c.executeMultiple(sql);
    },
  };
}

export async function initDatabase() {
  const db = getDb();

  // Enable foreign key enforcement
  await db.exec('PRAGMA foreign_keys = ON;');

  // Migration tracking table
  await db.exec(`
    CREATE TABLE IF NOT EXISTS migrations (
      version INTEGER PRIMARY KEY,
      name TEXT,
      applied_at TEXT DEFAULT (datetime('now'))
    );
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      google_id TEXT UNIQUE NOT NULL,
      email TEXT NOT NULL,
      tier TEXT NOT NULL DEFAULT 'free',
      credits_balance INTEGER NOT NULL DEFAULT 0,
      credits_replenished_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  `);

  await db.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS usage_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      model TEXT,
      prompt_tokens INTEGER,
      completion_tokens INTEGER,
      credits_deducted INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
  `);

  await db.exec(`
    CREATE INDEX IF NOT EXISTS idx_usage_log_user ON usage_log(user_id);
  `);

  // Additional indexes for query performance
  await db.exec('CREATE INDEX IF NOT EXISTS idx_usage_log_created ON usage_log(created_at);');
  await db.exec('CREATE INDEX IF NOT EXISTS idx_usage_log_user_created ON usage_log(user_id, created_at);');

  await migrateProfileColumns(db);
  await migrateStripeColumns(db);
  await migrateCreditPurchasesTable(db);
  await migrateEmailAuthColumns(db);
}

async function migrateProfileColumns(db) {
  const columns = await db.all("PRAGMA table_info(users)");
  const names = new Set(columns.map(c => c.name));
  if (!names.has('display_name')) {
    await db.exec('ALTER TABLE users ADD COLUMN display_name TEXT');
  }
  if (!names.has('avatar_url')) {
    await db.exec('ALTER TABLE users ADD COLUMN avatar_url TEXT');
  }
}

async function migrateStripeColumns(db) {
  const columns = await db.all("PRAGMA table_info(users)");
  const names = new Set(columns.map(c => c.name));
  if (!names.has('stripe_customer_id')) {
    await db.exec('ALTER TABLE users ADD COLUMN stripe_customer_id TEXT');
  }
  if (!names.has('stripe_subscription_id')) {
    await db.exec('ALTER TABLE users ADD COLUMN stripe_subscription_id TEXT');
  }
  if (!names.has('subscription_status')) {
    await db.exec('ALTER TABLE users ADD COLUMN subscription_status TEXT');
  }
  if (!names.has('subscription_period_end')) {
    await db.exec('ALTER TABLE users ADD COLUMN subscription_period_end INTEGER');
  }
  if (!names.has('trial_end')) {
    await db.exec('ALTER TABLE users ADD COLUMN trial_end INTEGER');
  }
}

async function migrateCreditPurchasesTable(db) {
  await db.exec(`
    CREATE TABLE IF NOT EXISTS credit_purchases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      pack_key TEXT NOT NULL,
      credits_added INTEGER NOT NULL,
      amount_cents INTEGER NOT NULL,
      stripe_session_id TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
  `);

  await db.exec(`
    CREATE INDEX IF NOT EXISTS idx_credit_purchases_user ON credit_purchases(user_id);
  `);
}

async function migrateEmailAuthColumns(db) {
  const columns = await db.all("PRAGMA table_info(users)");
  const names = new Set(columns.map(c => c.name));
  if (!names.has('password_hash')) {
    await db.exec('ALTER TABLE users ADD COLUMN password_hash TEXT');
  }
  if (!names.has('auth_provider')) {
    await db.exec("ALTER TABLE users ADD COLUMN auth_provider TEXT DEFAULT 'google'");
  }
  // google_id was originally NOT NULL — for email auth users it will be NULL.
  // SQLite doesn't support ALTER COLUMN, but new rows can insert NULL if we
  // accept the constraint at the application level (INSERT will work because
  // the column already exists and the NOT NULL was on CREATE TABLE which only
  // applies to rows at insertion time — SQLite doesn't enforce NOT NULL
  // retroactively on ALTER-added columns, but the original column *was* in
  // CREATE TABLE). We create a unique index on email for email-auth lookups.
  // The existing idx_users_google_id unique index handles google_id lookups.
  const indexes = await db.all("PRAGMA index_list(users)");
  const indexNames = new Set(indexes.map(i => i.name));
  if (!indexNames.has('idx_users_email_auth')) {
    // Partial-unique: only enforce uniqueness for email-auth users
    // (Google users may share email but have different google_id)
    await db.exec("CREATE INDEX IF NOT EXISTS idx_users_email_auth ON users(email, auth_provider)");
  }
}

export async function getUserByEmail(email) {
  const db = getDb();
  return db.get(
    "SELECT id, email, tier, credits_balance, credits_replenished_at, display_name, avatar_url, password_hash, auth_provider FROM users WHERE email = ? AND auth_provider = 'email'",
    [email]
  );
}

export async function createEmailUser(email, passwordHash, displayName) {
  const { randomUUID } = await import('crypto');
  const db = getDb();
  const id = randomUUID();
  const now = Date.now();
  const initialCredits = TIERS.free.creditsPerMonth;
  // google_id column has NOT NULL constraint, so use a sentinel prefix for email-auth users
  const placeholderGoogleId = `email:${id}`;
  await db.run(
    `INSERT INTO users (id, google_id, email, tier, credits_balance, credits_replenished_at, created_at, updated_at, password_hash, auth_provider, display_name)
     VALUES (?, ?, ?, 'free', ?, ?, ?, ?, ?, 'email', ?)`,
    [id, placeholderGoogleId, email, initialCredits, now, now, now, passwordHash, displayName || null]
  );
  const user = await db.get(
    'SELECT id, email, tier, credits_balance, credits_replenished_at, display_name, avatar_url FROM users WHERE id = ?',
    [id]
  );
  return user;
}

export const TIERS = {
  free:    { name: 'Free',    creditsPerMonth: 500,   models: ['free'] },
  starter: { name: 'Starter', creditsPerMonth: 2000,  models: ['free', 'fast'] },
  pro:     { name: 'Pro',     creditsPerMonth: 5000,  models: ['free', 'fast', 'frontier'] },
  team:    { name: 'Team',    creditsPerMonth: 25000, models: ['free', 'fast', 'frontier'] },
};

/** Credits per 1K tokens by model tier (frontier costs more) */
export const CREDITS_PER_1K_TOKENS = 1;
export const CREDITS_PER_1K_BY_MODEL_TIER = {
  free: 0,
  fast: 1,
  frontier: 3,
};
