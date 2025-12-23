import { NextResponse } from "next/server";
import { randomUUID } from "crypto";
import { requireSameOrigin, getSession } from "../_lib/session";
import { query } from "../_lib/db";
import { cookies } from "next/headers";

type Post = {
  id: string;
  title: string;
  body: string;
  authorId: string;
  createdAt: string;
  updatedAt: string;
};

const mapRow = (row: any): Post => ({
  id: row.id,
  title: row.title,
  body: row.body,
  authorId: row.author_id,
  createdAt: row.created_at?.toISOString?.() ?? row.created_at,
  updatedAt: row.updated_at?.toISOString?.() ?? row.updated_at
});

export const posts = new Map<string, Post>(); // kept for compatibility; not used now.

export async function GET() {
  const res = await query(`SELECT id, title, body, author_id, created_at, updated_at FROM posts ORDER BY created_at DESC`);
  return NextResponse.json({ posts: res.rows.map(mapRow) });
}

export async function POST(req: Request) {
  if (!requireSameOrigin()) return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  const { title, body, authorId: bodyAuthorId } = await req.json();
  if (!title || !body) return NextResponse.json({ error: "BAD_REQUEST" }, { status: 400 });

  // Prefer current session user; fallback to provided authorId (must be uuid)
  const sessionId = cookies().get(process.env.SESSION_COOKIE_NAME ?? "session_id")?.value;
  const session = await getSession(sessionId);
  const authorId = session?.userId ?? bodyAuthorId ?? null;

  if (authorId && !/^[0-9a-fA-F-]{36}$/.test(authorId)) {
    return NextResponse.json({ error: "INVALID_AUTHOR" }, { status: 400 });
  }

  const now = new Date().toISOString();
  const res = await query(
    `INSERT INTO posts (id, title, body, author_id, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $5) RETURNING id, title, body, author_id, created_at, updated_at`,
    [randomUUID(), title, body, authorId, now]
  );
  return NextResponse.json(mapRow(res.rows[0]), { status: 201 });
}

export async function PUT(req: Request) {
  if (!requireSameOrigin()) return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  const { id, title, body } = await req.json();
  if (!id) return NextResponse.json({ error: "BAD_REQUEST" }, { status: 400 });
  const res = await query(
    `UPDATE posts SET title = COALESCE($2, title), body = COALESCE($3, body), updated_at = NOW() WHERE id = $1 RETURNING id, title, body, author_id, created_at, updated_at`,
    [id, title, body]
  );
  if (res.rowCount === 0) return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  return NextResponse.json(mapRow(res.rows[0]));
}

export async function DELETE(req: Request) {
  if (!requireSameOrigin()) return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  const { id } = await req.json();
  if (!id) return NextResponse.json({ error: "BAD_REQUEST" }, { status: 400 });
  const res = await query(`DELETE FROM posts WHERE id = $1`, [id]);
  if (res.rowCount === 0) return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  return NextResponse.json({ ok: true });
}
