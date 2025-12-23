"use client";

import { useEffect, useState } from "react";

type Session = { sessionId: string | null; userId: string | null };

export default function LoginPage() {
  const [session, setSession] = useState<Session>({ sessionId: null, userId: null });
  const [username, setUsername] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  const refreshSession = async () => {
    const res = await fetch("/api/session", { credentials: "include" });
    const data = await res.json();
    setSession(data);
  };

  useEffect(() => {
    refreshSession().catch(() => setMessage("세션 조회 실패"));
  }, []);

  const login = async () => {
    setMessage(null);
    const res = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({ username })
    });
    if (!res.ok) {
      setMessage("로그인 실패");
      return;
    }
    await refreshSession();
    setMessage("로그인 성공");
  };

  const logout = async () => {
    await fetch("/api/auth/logout", { method: "POST", credentials: "include" });
    await refreshSession();
    setMessage("로그아웃 완료");
  };

  return (
    <main style={{ padding: 16 }}>
      <div className="card" style={{ marginBottom: 16 }}>
        <h2>로그인</h2>
        <div style={{ display: "flex", gap: 8, flexDirection: "column" }}>
          <input
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="username"
            style={inputStyle}
          />
          <button style={buttonStyle} onClick={login}>
            로그인
          </button>
          <button style={{ ...buttonStyle, background: "#3a3f45" }} onClick={logout}>
            로그아웃
          </button>
          {message && <p style={{ color: "#9fb2c8" }}>{message}</p>}
        </div>
      </div>

      <div className="card">
        <h3>현재 세션</h3>
        <p>session: {session.sessionId ?? "없음"}</p>
        <p>user: {session.userId ?? "anonymous"}</p>
      </div>
    </main>
  );
}

const inputStyle: React.CSSProperties = {
  padding: "10px 12px",
  borderRadius: 8,
  border: "1px solid #263445",
  background: "#0c1016",
  color: "#f4f6f8"
};

const buttonStyle: React.CSSProperties = {
  padding: "10px 12px",
  borderRadius: 8,
  border: "none",
  background: "#1f8aee",
  color: "#fff",
  fontWeight: 600,
  cursor: "pointer"
};
