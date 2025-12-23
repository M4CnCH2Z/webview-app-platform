import { NextResponse } from "next/server";
import { deleteUser, getUser, requireSameOrigin, updateUser } from "../../_lib/session";

type Params = { params: { id: string } };

export async function GET(_: Request, { params }: Params) {
  const user = await getUser(params.id);
  if (!user) return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  return NextResponse.json(user);
}

export async function PUT(req: Request, { params }: Params) {
  if (!requireSameOrigin()) return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  const { username, email } = await req.json();
  const updated = await updateUser(params.id, { username, email });
  if (!updated) return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  return NextResponse.json(updated);
}

export async function DELETE(_: Request, { params }: Params) {
  if (!requireSameOrigin()) return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  const ok = await deleteUser(params.id);
  if (!ok) return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  return NextResponse.json({ ok: true });
}
