import { cookies, headers } from "next/headers";
import { randomUUID } from "crypto";
import { query } from "./db";
import { redis } from "./redis";

type SessionRecord = {
  sessionId: string;
  userId: string;
  createdAt: string;
  expiresAt: string;
  revokedAt: string | null;
};

export type UserRecord = { id: string; username: string; email: string; created_at?: string };

const SESSION_COOKIE = process.env.SESSION_COOKIE_NAME ?? "session_id";
const SESSION_CACHE_TTL = Number(process.env.SESSION_CACHE_TTL ?? 1800); // seconds

const allowedOrigins = (process.env.ALLOWLIST_ORIGINS ?? "")
  .split(",")
  .map((v) => v.trim())
  .filter(Boolean);

const cacheKey = (sessionId: string) => `sess:${sessionId}`;
const denyKey = (sessionId: string) => `deny:${sessionId}`;

const serializeSession = (row: any): SessionRecord => ({
  sessionId: row.session_id,
  userId: row.user_id,
  createdAt: row.created_at?.toISOString?.() ?? row.created_at,
  expiresAt: row.expires_at?.toISOString?.() ?? row.expires_at,
  revokedAt: row.revoked_at ? row.revoked_at?.toISOString?.() ?? row.revoked_at : null
});

const ttlUntil = (expiresAt: string) => {
  const diff = new Date(expiresAt).getTime() - Date.now();
  return diff > 0 ? Math.floor(diff / 1000) : 0;
};

export const issueSession = async (userId: string) => {
  const sessionId = randomUUID();
  const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24 * 7);
  await query(
    `INSERT INTO sessions (session_id, user_id, created_at, expires_at) VALUES ($1, $2, NOW(), $3)`,
    [sessionId, userId, expiresAt]
  );
  const record: SessionRecord = {
    sessionId,
    userId,
    createdAt: new Date().toISOString(),
    expiresAt: expiresAt.toISOString(),
    revokedAt: null
  };
  await redis.set(cacheKey(sessionId), JSON.stringify(record), "EX", SESSION_CACHE_TTL);
  return record;
};

export const getSession = async (sessionId: string | undefined | null) => {
  if (!sessionId) return null;
  const deny = await redis.get(denyKey(sessionId));
  if (deny) return null;

  const cached = await redis.get(cacheKey(sessionId));
  if (cached) {
    const parsed: SessionRecord = JSON.parse(cached);
    if (new Date(parsed.expiresAt).getTime() < Date.now()) {
      await redis.del(cacheKey(sessionId));
      return null;
    }
    return parsed;
  }

  const res = await query(
    `SELECT session_id, user_id, created_at, expires_at, revoked_at FROM sessions WHERE session_id = $1 LIMIT 1`,
    [sessionId]
  );
  if (res.rowCount === 0) return null;
  const record = serializeSession(res.rows[0]);
  if (record.revokedAt || new Date(record.expiresAt).getTime() < Date.now()) {
    await redis.set(denyKey(sessionId), "1", "EX", ttlUntil(record.expiresAt) || 60);
    return null;
  }
  await redis.set(cacheKey(sessionId), JSON.stringify(record), "EX", SESSION_CACHE_TTL);
  return record;
};

export const revokeSession = async (sessionId: string | undefined | null) => {
  if (!sessionId) return;
  await query(`UPDATE sessions SET revoked_at = NOW() WHERE session_id = $1`, [sessionId]);
  await redis.del(cacheKey(sessionId));
  await redis.set(denyKey(sessionId), "1", "EX", SESSION_CACHE_TTL);
};

export const createUser = (username: string, email: string) => {
  return query(
    `INSERT INTO users (id, username, email, created_at) VALUES ($1, $2, $3, NOW()) RETURNING id, username, email, created_at`,
    [randomUUID(), username, email]
  ).then((r) => r.rows[0] as UserRecord);
};

export const listUsers = () =>
  query(`SELECT id, username, email, created_at FROM users ORDER BY created_at DESC`).then((r) => r.rows as UserRecord[]);

export const getUser = (id: string) =>
  query(`SELECT id, username, email, created_at FROM users WHERE id = $1`, [id]).then((r) => (r.rowCount ? (r.rows[0] as UserRecord) : null));

export const findUserByUsername = (username: string) => {
  return query(`SELECT id, username, email, created_at FROM users WHERE username = $1`, [username]).then((r) =>
    r.rowCount ? (r.rows[0] as UserRecord) : null
  );
};

export const updateUser = (id: string, partial: Partial<UserRecord>) => {
  const fields: string[] = [];
  const values: any[] = [];
  let idx = 1;
  if (partial.username !== undefined) {
    fields.push(`username = $${idx++}`);
    values.push(partial.username);
  }
  if (partial.email !== undefined) {
    fields.push(`email = $${idx++}`);
    values.push(partial.email);
  }
  if (!fields.length) return Promise.resolve(null);
  values.push(id);
  const sql = `UPDATE users SET ${fields.join(", ")} WHERE id = $${idx} RETURNING id, username, email, created_at`;
  return query(sql, values).then((r) => (r.rowCount ? (r.rows[0] as UserRecord) : null));
};

export const deleteUser = (id: string) =>
  query(`DELETE FROM users WHERE id = $1`, [id]).then((r) => r.rowCount > 0);

export const requireSameOrigin = () => {
  const origin = headers().get("origin");
  // In dev or WebView, Origin can be missing; allow when absent or when allowlist is empty.
  if (!origin) return true;
  if (allowedOrigins.length === 0) return true;
  return allowedOrigins.includes(origin);
};

export const setSessionCookie = (sessionId: string) => {
  cookies().set({
    name: SESSION_COOKIE,
    value: sessionId,
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 7
  });
};

export const clearSessionCookie = () => {
  cookies().set({
    name: SESSION_COOKIE,
    value: "",
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    expires: new Date(0),
    path: "/"
  });
};
