# WebView App Platform Monorepo

Monorepo for a WebView-hosted Android app, Next.js web/BFF, and shared bridge contracts.

## Stack
- Monorepo: pnpm + turborepo
- Web/BFF: Next.js (App Router) with route handlers
- Android: Native WebView shell (Kotlin)
- Shared: Bridge contract (zod), API client, shared utils, config
- Infra: Postgres + Redis via docker-compose

## Directory Layout
- `apps/web`: Next.js app (web UI + BFF APIs)
- `apps/android`: Android WebView shell (`io.m4cnch2z.app`)
- `packages/bridge-contract`: Contract-first schemas for Web↔Native bridge
- `packages/api-client`: Fetch wrapper for BFF APIs
- `packages/shared`: Shared utilities
- `packages/config`: tsconfig/eslint base
- `infra`: `docker-compose.yml`, migrations
- `docs/architecture`: ADR template, session model notes

> 한국어 버전: [README.ko.md](README.ko.md)

## Getting Started
1) Install deps: `pnpm install`
2) Infra (optional local DB/cache): `cd infra && docker compose up -d`
3) Apply DB migrations:
   - With container psql: `cd infra && docker compose cp migrations/001_init.sql postgres:/tmp/001_init.sql && docker compose cp migrations/002_users_posts.sql postgres:/tmp/002_users_posts.sql && docker compose exec -T postgres psql -U ${POSTGRES_USER:-appuser} -d ${POSTGRES_DB:-appdb} -f /tmp/001_init.sql && docker compose exec -T postgres psql -U ${POSTGRES_USER:-appuser} -d ${POSTGRES_DB:-appdb} -f /tmp/002_users_posts.sql`
   - Or local psql: `psql "$DATABASE_URL" -f infra/migrations/001_init.sql` then `.../002_users_posts.sql`
4) Web/BFF dev server: from repo root `pnpm dev` (Next.js on `http://localhost:3000`)
4) Android app:
   - Open `apps/android` in Android Studio, or CLI: `cd apps/android && ./gradlew installDebug`
   - WebView dev URL defaults to `http://10.0.2.2:3000`; ensure the web dev server is running.
   - If using an emulator proxy (e.g., Burp), disable it or allow 10.0.2.2:3000.

## Bridge Contract (contract-first)
- Message: `request { id, version, type, payload }` → `response { id, ok, payload?, error? }`
- Capabilities: `capabilities.request` → `{ appVersion, bridgeVersion, supported[] }`
- Example types: `auth.getSession`, `nav.openExternal`, `device.getPushToken`, `media.pickImage`
- Error codes: `PERMISSION_DENIED`, `NOT_SUPPORTED`, `INVALID_PAYLOAD`, `INVALID_ORIGIN`, `TIMEOUT`, `INTERNAL_ERROR`
- Semver: major compatibility enforced (`1.x`); CI should block breaking changes without MAJOR bump.

## Security Defaults
- Android WebView: origin allowlist (`https://app.example.com`, `http://10.0.2.2:3000`, `http://localhost:3000`), cleartext allowed only for dev hosts, external URLs handed to system browser, debug WebView only in debug builds.
- Web: CSP headers, X-Frame-Options DENY, Origin allowlist for login, SameSite=Lax HttpOnly session cookie (placeholder store).
- Redis denylist plan for immediate session revocation; Postgres is source of truth.

## Environment
- Copy `.env.example` → `.env.local` as needed.
- Key vars: `WEB_URL`, `ALLOWLIST_ORIGINS`, `SESSION_COOKIE_NAME`, `POSTGRES_*`, `REDIS_URL`.

## Useful Scripts
- `pnpm dev` / `pnpm build` / `pnpm lint` / `pnpm typecheck`
- `cd apps/android && ./gradlew assembleDebug` (or `installDebug`)

## API placeholders (in-memory)
- Auth/Session: backed by Postgres (sessions table) + Redis cache/denylist.
- Users CRUD: backed by Postgres `users` table.
- Posts CRUD: backed by Postgres `posts` table; authorId defaults to current session user if present.
- Origin allowlist enforced for mutating routes.

## Migrations
- `infra/migrations/001_init.sql` contains sessions/refresh_tokens/devices schema skeleton.
