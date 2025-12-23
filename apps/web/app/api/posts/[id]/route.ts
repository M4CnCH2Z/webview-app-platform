import { NextResponse } from "next/server";
import { requireSameOrigin } from "../../_lib/session";
import { query } from "../../_lib/db";

type Params = { params: { id: string } };

export async function GET(_: Request, { params }: Params) {
  const res = await query(
    `SELECT id, title, body, author_id, created_at, updated_at FROM posts WHERE id = $1 LIMIT 1`,
    [params.id]
  );
  if (res.rowCount === 0) return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  const row = res.rows[0];
  return NextResponse.json({
    id: row.id,
    title: row.title,
    body: row.body,
    authorId: row.author_id,
    createdAt: row.created_at?.toISOString?.() ?? row.created_at,
    updatedAt: row.updated_at?.toISOString?.() ?? row.updated_at
  });
}

export async function PUT(req: Request, { params }: Params) {
  if (!requireSameOrigin()) return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  const { title, body } = await req.json();
  const res = await query(
    `UPDATE posts SET title = COALESCE($2, title), body = COALESCE($3, body), updated_at = NOW() WHERE id = $1 RETURNING id, title, body, author_id, created_at, updated_at`,
    [params.id, title, body]
  );
  if (res.rowCount === 0) return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  const row = res.rows[0];
  return NextResponse.json({
    id: row.id,
    title: row.title,
    body: row.body,
    authorId: row.author_id,
    createdAt: row.created_at?.toISOString?.() ?? row.created_at,
    updatedAt: row.updated_at?.toISOString?.() ?? row.updated_at
  });
}

export async function DELETE(_: Request, { params }: Params) {
  if (!requireSameOrigin()) return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  const res = await query(`DELETE FROM posts WHERE id = $1`, [params.id]);
  if (res.rowCount === 0) return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  return NextResponse.json({ ok: true });
}
