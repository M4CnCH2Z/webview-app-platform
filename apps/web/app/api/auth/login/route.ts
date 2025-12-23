import { NextResponse } from "next/server";
import {
  findUserByUsername,
  issueSession,
  requireSameOrigin,
  setSessionCookie
} from "../../_lib/session";

export async function POST(req: Request) {
  if (!requireSameOrigin()) {
    return NextResponse.json({ error: "FORBIDDEN" }, { status: 403 });
  }

  const { username } = await req.json();
  if (!username) {
    return NextResponse.json({ error: "INVALID_CREDENTIALS" }, { status: 400 });
  }

  const user = await findUserByUsername(username);
  if (!user) {
    return NextResponse.json({ error: "INVALID_CREDENTIALS" }, { status: 401 });
  }

  const session = await issueSession(user.id);
  setSessionCookie(session.sessionId);
  return NextResponse.json({ sessionId: session.sessionId, userId: session.userId });
}
