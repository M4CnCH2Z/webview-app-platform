"use client";

import { useEffect, useState } from "react";
import { createApiClient } from "@platform/api-client";
import { getCapabilities, sendBridgeRequest } from "./lib/bridge";

const api = createApiClient("");

type CapabilityState = {
  appVersion: string;
  bridgeVersion: string;
  supported: string[];
};

export default function Home() {
  const [capabilities, setCapabilities] = useState<CapabilityState | null>(null);
  const [session, setSession] = useState<{ sessionId: string | null; userId: string | null }>({
    sessionId: null,
    userId: null
  });
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .session()
      .then(setSession)
      .catch(() => setError("Failed to load session"));

    getCapabilities()
      .then((caps) => caps && setCapabilities(caps))
      .catch(() => setCapabilities(null));
  }, []);

  const triggerPushToken = async () => {
    try {
      const token = await sendBridgeRequest<{ token: string }>("device.getPushToken", {});
      alert(`Push token: ${token?.token ?? "n/a"}`);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const canUse = (name: string) => capabilities?.supported?.includes(name);

  return (
    <main style={{ padding: 24 }}>
      <div className="card" style={{ marginBottom: 16 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <h1 style={{ margin: 0 }}>WebView Host</h1>
          <span className="pill">
            {capabilities
              ? `Bridge ${capabilities.bridgeVersion} / App ${capabilities.appVersion}`
              : "Bridge: web-only"}
          </span>
        </div>
        <p style={{ color: "#9fb2c8" }}>
          Capability-gated features will use the native bridge when present. Web continues to ship
          independently.
        </p>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <span className="pill">session: {session.sessionId ?? "none"}</span>
          <span className="pill">user: {session.userId ?? "anon"}</span>
        </div>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3>Capabilities</h3>
        <ul>
          {["auth.getSession", "nav.openExternal", "device.getPushToken", "media.pickImage"].map(
            (cap) => (
              <li key={cap} style={{ color: canUse(cap) ? "#5af08c" : "#a3b8cc" }}>
                {cap} {canUse(cap) ? "available" : "not available"}
              </li>
            )
          )}
        </ul>
      </div>

      <div className="card">
        <h3>Actions</h3>
        <button
          onClick={triggerPushToken}
          disabled={!canUse("device.getPushToken")}
          style={{
            padding: "8px 16px",
            background: "#1f8aee",
            color: "#fff",
            border: "none",
            borderRadius: 8,
            cursor: canUse("device.getPushToken") ? "pointer" : "not-allowed",
            opacity: canUse("device.getPushToken") ? 1 : 0.5
          }}
        >
          Request Push Token
        </button>
        {error && <p style={{ color: "#ff7b7b" }}>{error}</p>}
      </div>
    </main>
  );
}
