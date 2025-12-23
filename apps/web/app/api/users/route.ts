import { NextResponse } from "next/server";
import {
  createUser,
  deleteUser,
  getUser,
  listUsers,
  requireSameOrigin,
  updateUser
} from "../_lib/session";

export async function GET() {
  const users = await listUsers();
  return NextResponse.json({ users });
}

export async function POST(req: Request) {
  if (!requireSameOrigin()) return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  const { username, email } = await req.json();
  if (!username || !email) return NextResponse.json({ error: "BAD_REQUEST" }, { status: 400 });
  const user = await createUser(username, email);
  return NextResponse.json(user, { status: 201 });
}

export async function PUT(req: Request) {
  if (!requireSameOrigin()) return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  const { id, username, email } = await req.json();
  if (!id) return NextResponse.json({ error: "BAD_REQUEST" }, { status: 400 });
  const updated = await updateUser(id, { username, email });
  if (!updated) return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  return NextResponse.json(updated);
}

export async function DELETE(req: Request) {
  if (!requireSameOrigin()) return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  const { id } = await req.json();
  if (!id) return NextResponse.json({ error: "BAD_REQUEST" }, { status: 400 });
  const ok = await deleteUser(id);
  if (!ok) return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  return NextResponse.json({ ok: true });
}
