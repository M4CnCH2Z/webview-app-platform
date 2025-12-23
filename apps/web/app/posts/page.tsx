"use client";

import { useEffect, useState } from "react";

type Post = {
  id: string;
  title: string;
  body: string;
  authorId: string;
  createdAt: string;
  updatedAt: string;
};

export default function PostsPage() {
  const [posts, setPosts] = useState<Post[]>([]);
  const [form, setForm] = useState({ id: "", title: "", body: "", authorId: "" });
  const [message, setMessage] = useState<string | null>(null);

  const load = async () => {
    const res = await fetch("/api/posts");
    const data = await res.json();
    setPosts(data.posts ?? []);
  };

  useEffect(() => {
    load().catch(() => setMessage("목록 조회 실패"));
  }, []);

  const submit = async () => {
    setMessage(null);
    const method = form.id ? "PUT" : "POST";
    // authorId optional; server will fallback to session user if available
    const res = await fetch("/api/posts", {
      method,
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({
        id: form.id || undefined,
        title: form.title,
        body: form.body,
        authorId: form.authorId
      })
    });
    if (!res.ok) {
      setMessage("저장 실패");
      return;
    }
    setForm({ id: "", title: "", body: "", authorId: "" });
    await load();
    setMessage("저장 완료");
  };

  const remove = async (id: string) => {
    await fetch("/api/posts", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({ id })
    });
    await load();
  };

  return (
    <main style={{ padding: 16 }}>
      <div className="card" style={{ marginBottom: 16 }}>
        <h2>게시판</h2>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <input
            style={inputStyle}
            placeholder="authorId (user id)"
            value={form.authorId}
            onChange={(e) => setForm({ ...form, authorId: e.target.value })}
          />
          <input
            style={inputStyle}
            placeholder="title"
            value={form.title}
            onChange={(e) => setForm({ ...form, title: e.target.value })}
          />
          <textarea
            style={{ ...inputStyle, minHeight: 100 }}
            placeholder="body"
            value={form.body}
            onChange={(e) => setForm({ ...form, body: e.target.value })}
          />
          <button style={buttonStyle} onClick={submit}>
            {form.id ? "수정" : "등록"}
          </button>
          {message && <p style={{ color: "#9fb2c8" }}>{message}</p>}
        </div>
      </div>

      <div className="card">
        <h3>게시글 목록</h3>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {posts.map((p) => (
            <div
              key={p.id}
              style={{
                border: "1px solid #1f2a36",
                borderRadius: 8,
                padding: 12,
                display: "flex",
                flexDirection: "column",
                gap: 6
              }}
            >
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <div style={{ fontWeight: 700 }}>{p.title}</div>
                <div style={{ fontSize: 12, color: "#9fb2c8" }}>작성자: {p.authorId}</div>
              </div>
              <div style={{ whiteSpace: "pre-wrap", color: "#dce6f0" }}>{p.body}</div>
              <div style={{ display: "flex", gap: 8 }}>
                <button
                  style={smallButton}
                  onClick={() =>
                    setForm({
                      id: p.id,
                      title: p.title,
                      body: p.body,
                      authorId: p.authorId
                    })
                  }
                >
                  수정
                </button>
                <button style={{ ...smallButton, background: "#3a3f45" }} onClick={() => remove(p.id)}>
                  삭제
                </button>
              </div>
            </div>
          ))}
          {posts.length === 0 && <p style={{ color: "#9fb2c8" }}>게시글이 없습니다.</p>}
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
