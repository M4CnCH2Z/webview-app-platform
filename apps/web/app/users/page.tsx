"use client";

import { useEffect, useState } from "react";

type User = { id: string; username: string; email: string };

export default function UsersPage() {
  const [users, setUsers] = useState<User[]>([]);
  const [form, setForm] = useState({ id: "", username: "", email: "" });
  const [message, setMessage] = useState<string | null>(null);

  const load = async () => {
    const res = await fetch("/api/users");
    const data = await res.json();
    setUsers(data.users ?? []);
  };

  useEffect(() => {
    load().catch(() => setMessage("목록 조회 실패"));
  }, []);

  const submit = async () => {
    try {
      setMessage(null);
      const method = form.id ? "PUT" : "POST";
      const res = await fetch("/api/users", {
        method,
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({
          id: form.id || undefined,
          username: form.username,
          email: form.email
        })
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        setMessage(err.error ?? "저장 실패");
        return;
      }
      setForm({ id: "", username: "", email: "" });
      await load();
      setMessage("저장 완료");
    } catch (e) {
      setMessage(`오류: ${(e as Error).message}`);
    }
  };

  const remove = async (id: string) => {
    try {
      const res = await fetch("/api/users", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ id })
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        setMessage(err.error ?? "삭제 실패");
        return;
      }
      await load();
    } catch (e) {
      setMessage(`오류: ${(e as Error).message}`);
    }
  };

  return (
    <main style={{ padding: 16 }}>
      <div className="card" style={{ marginBottom: 16 }}>
        <h2>회원 관리</h2>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <input
            style={inputStyle}
            placeholder="username"
            value={form.username}
            onChange={(e) => setForm({ ...form, username: e.target.value })}
          />
          <input
            style={inputStyle}
            placeholder="email"
            value={form.email}
            onChange={(e) => setForm({ ...form, email: e.target.value })}
          />
          <button style={buttonStyle} onClick={submit}>
            {form.id ? "수정" : "등록"}
          </button>
          {message && <p style={{ color: "#9fb2c8" }}>{message}</p>}
        </div>
      </div>

      <div className="card">
        <h3>회원 목록</h3>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {users.map((u) => (
            <div
              key={u.id}
              style={{
                border: "1px solid #1f2a36",
                borderRadius: 8,
                padding: 12,
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center"
              }}
            >
              <div>
                <div style={{ fontWeight: 600 }}>{u.username}</div>
                <div style={{ color: "#9fb2c8", fontSize: 13 }}>{u.email}</div>
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                <button
                  style={smallButton}
                  onClick={() => setForm({ id: u.id, username: u.username, email: u.email })}
                >
                  수정
                </button>
                <button style={{ ...smallButton, background: "#3a3f45" }} onClick={() => remove(u.id)}>
                  삭제
                </button>
              </div>
            </div>
          ))}
          {users.length === 0 && <p style={{ color: "#9fb2c8" }}>등록된 회원이 없습니다.</p>}
        </div>
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

const smallButton: React.CSSProperties = {
  padding: "8px 10px",
  borderRadius: 8,
  border: "none",
  background: "#1f8aee",
  color: "#fff",
  fontWeight: 600,
  cursor: "pointer",
  fontSize: 13
};
