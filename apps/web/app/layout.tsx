import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "WebView App",
  description: "WebView-hosted app with BFF and bridge capabilities"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <header
          style={{
            position: "sticky",
            top: 0,
            zIndex: 10,
            padding: "12px 16px",
            background: "#0c1016",
            borderBottom: "1px solid #1f2a36",
            display: "flex",
            gap: 12,
            alignItems: "center"
          }}
        >
          <Link href="/" style={{ fontWeight: 700, fontSize: 18 }}>
            WebViewApp
          </Link>
          <div style={{ display: "flex", gap: 10, fontSize: 14 }}>
            <Link href="/login">Login</Link>
            <Link href="/users">Users</Link>
            <Link href="/posts">Posts</Link>
          </div>
        </header>
        {children}
      </body>
    </html>
  );
}
