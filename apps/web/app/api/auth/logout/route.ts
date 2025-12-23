import { NextResponse } from "next/server";
import { clearSessionCookie, revokeSession } from "../../_lib/session";

export async function POST() {
  // Best-effort revoke; don't leak existence
  clearSessionCookie();
  revokeSession(null);
  return NextResponse.json({ ok: true });
}
