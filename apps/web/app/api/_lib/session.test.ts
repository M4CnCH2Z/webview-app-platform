import { afterEach, describe, expect, it, vi } from "vitest";

// Mock next/headers for cookies/headers
const cookieStore = new Map<string, any>();
vi.mock("next/headers", () => ({
  cookies: () => ({
    set: ({ name, value }: { name: string; value: string }) => cookieStore.set(name, value),
    get: (name: string) => (cookieStore.has(name) ? { value: cookieStore.get(name) } : undefined)
  }),
  headers: () => new Map([["origin", "http://localhost:3000"]])
}));

// Simple Redis mock
const redisData = new Map<string, string>();
vi.mock("./redis", () => ({
  redis: {
    get: (k: string) => Promise.resolve(redisData.get(k) ?? null),
    set: (k: string, v: string, mode?: string, ttl?: number) => {
      redisData.set(k, v);
      return Promise.resolve("OK");
    },
    del: (k: string) => {
      redisData.delete(k);
      return Promise.resolve(1);
    }
  }
}));

// Simple DB mock with in-memory tables
type UserRow = { id: string; username: string; email: string; created_at: Date };
type SessionRow = { session_id: string; user_id: string; created_at: Date; expires_at: Date; revoked_at: Date | null };

const users: UserRow[] = [];
const sessions: SessionRow[] = [];

vi.mock("./db", () => ({
  query: async (sql: string, params: any[]) => {
    if (sql.startsWith("INSERT INTO users")) {
      const row: UserRow = {
        id: params[0],
        username: params[1],
        email: params[2],
        created_at: new Date()
      };
      users.push(row);
      return { rows: [row], rowCount: 1 };
    }
    if (sql.startsWith("SELECT id, username, email") && sql.includes("WHERE username =")) {
      const found = users.find((u) => u.username === params[0]);
      return { rows: found ? [found] : [], rowCount: found ? 1 : 0 };
    }
    if (sql.startsWith("SELECT id, username, email") && sql.includes("WHERE id =")) {
      const found = users.find((u) => u.id === params[0]);
      return { rows: found ? [found] : [], rowCount: found ? 1 : 0 };
    }
    if (sql.startsWith("SELECT id, username, email") && sql.includes("FROM users ORDER")) {
      return { rows: users.slice(), rowCount: users.length };
    }
    if (sql.startsWith("UPDATE users SET")) {
      const existing = users.find((u) => u.id === params[params.length - 1]);
      if (!existing) return { rows: [], rowCount: 0 };
      if (sql.includes("username =")) existing.username = params[0];
      if (sql.includes("email =")) existing.email = params[sql.includes("username =") ? 1 : 0];
      return { rows: [existing], rowCount: 1 };
    }
    if (sql.startsWith("DELETE FROM users")) {
      const idx = users.findIndex((u) => u.id === params[0]);
      if (idx === -1) return { rows: [], rowCount: 0 };
      users.splice(idx, 1);
      return { rows: [], rowCount: 1 };
    }
    if (sql.startsWith("INSERT INTO sessions")) {
      const row: SessionRow = {
        session_id: params[0],
        user_id: params[1],
        created_at: new Date(),
        expires_at: new Date(params[2]),
        revoked_at: null
      };
      sessions.push(row);
      return { rows: [], rowCount: 1 };
    }
    if (sql.startsWith("SELECT session_id")) {
      const found = sessions.find((s) => s.session_id === params[0]);
      return { rows: found ? [found] : [], rowCount: found ? 1 : 0 };
    }
    if (sql.startsWith("UPDATE sessions SET revoked_at")) {
      const found = sessions.find((s) => s.session_id === params[0]);
      if (found) found.revoked_at = new Date();
      return { rows: [], rowCount: found ? 1 : 0 };
    }
    throw new Error(`Unhandled SQL in mock: ${sql}`);
  }
}));

import {
  createUser,
  deleteUser,
  findUserByUsername,
  getSession,
  issueSession,
  listUsers,
  updateUser
} from "./session";

afterEach(() => {
  users.splice(0, users.length);
  sessions.splice(0, sessions.length);
  redisData.clear();
  cookieStore.clear();
});

describe("session + user store (mocked DB/Redis)", () => {
  it("creates and finds a user", async () => {
    const u = await createUser("alice", "a@example.com");
    expect(u.username).toBe("alice");
    const found = await findUserByUsername("alice");
    expect(found?.email).toBe("a@example.com");
    const list = await listUsers();
    expect(list).toHaveLength(1);
  });

  it("updates and deletes a user", async () => {
    const u = await createUser("bob", "b@example.com");
    const updated = await updateUser(u.id, { email: "new@example.com" });
    expect(updated?.email).toBe("new@example.com");
    const ok = await deleteUser(u.id);
    expect(ok).toBe(true);
    const list = await listUsers();
    expect(list).toHaveLength(0);
  });

  it("issues session, caches, and revokes", async () => {
    const u = await createUser("charlie", "c@example.com");
    const sess = await issueSession(u.id);
    expect(sess.userId).toBe(u.id);

    const fetched = await getSession(sess.sessionId);
    expect(fetched?.sessionId).toBe(sess.sessionId);

    await import("./session").then((m) => m.revokeSession(sess.sessionId));
    const revoked = await getSession(sess.sessionId);
    expect(revoked).toBeNull();
  });
});
