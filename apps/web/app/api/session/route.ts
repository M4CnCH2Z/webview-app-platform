import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { clearSessionCookie, getSession } from "../_lib/session";

export async function GET() {
  const sessionId = cookies().get(process.env.SESSION_COOKIE_NAME ?? "session_id")?.value;
  const session = await getSession(sessionId);
  if (!session) {
    clearSessionCookie();
    return NextResponse.json({ sessionId: null, userId: null });
  }
  return NextResponse.json({ sessionId: session.sessionId, userId: session.userId });
}
