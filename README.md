test
# WebView App Platform Monorepo

Monorepo for a WebView-hosted Android app, React web frontend and Spring Boot API (both based on `dbswhd4932/shoppingmall_project`), and shared bridge contracts.

## Stack
- Monorepo: pnpm + turborepo
- Web: React (CRA) frontend from `dbswhd4932/shoppingmall_project`
- Backend: Spring Boot API from `dbswhd4932/shoppingmall_project`
- Android: Native WebView shell (Kotlin)
- Shared: Bridge contract (zod), API client, shared utils, config
- Infra: Postgres + Redis via docker-compose

## Directory Layout
- `apps/web`: React (CRA) app built from the frontend sources of [dbswhd4932/shoppingmall_project](https://github.com/dbswhd4932/shoppingmall_project)
- `apps/api`: Spring Boot backend built from the backend sources of [dbswhd4932/shoppingmall_project](https://github.com/dbswhd4932/shoppingmall_project)
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
<!-- 2) Infra (optional local DB/cache): `cd infra && docker compose up -d`
   - For the Spring Boot backend (`apps/api`), start local MySQL (port 3307, db `shoppingmall`, user `shopuser`, pass `shop1234`), Redis (6379), and RabbitMQ (5672) to match `application-local.yml`.
3) Apply DB migrations:
   - With container psql: `cd infra && docker compose cp migrations/001_init.sql postgres:/tmp/001_init.sql && docker compose cp migrations/002_users_posts.sql postgres:/tmp/002_users_posts.sql && docker compose exec -T postgres psql -U ${POSTGRES_USER:-appuser} -d ${POSTGRES_DB:-appdb} -f /tmp/001_init.sql && docker compose exec -T postgres psql -U ${POSTGRES_USER:-appuser} -d ${POSTGRES_DB:-appdb} -f /tmp/002_users_posts.sql`
   - Or local psql: `psql "$DATABASE_URL" -f infra/migrations/001_init.sql` then `.../002_users_posts.sql` -->
2) Web dev server (CRA): `cd apps/web && npm install && npm start` (runs on `http://localhost:3000`)
3) Backend dev server: `cd apps/api && ./gradlew bootRun --args='--spring.profiles.active=local'`
4) Android app:
   - Open `apps/android` in Android Studio, or CLI: `cd apps/android && ./gradlew installDebug`
   - WebView dev URL defaults to `http://10.0.2.2:3000`; ensure the web dev server is running.
   - If using an emulator proxy (e.g., Burp), disable it or allow 10.0.2.2:3000.

## Docker Compose (local)
- Required versions: OpenJDK 21, Node.js 22.19.0, Docker Desktop 29.1.3, Docker Compose v5.0.0
- Run from repo root: `docker compose up -d --build`
- Stop: `docker compose stop` / Remove: `docker compose down`
- Check:
  - `docker compose ps`
  - `curl http://localhost:8080/actuator/health`
  - Browser: `http://localhost:3000`

### Services
- infra: mysql(3307->3306), redis(6379), rabbitmq(5672/15672), prometheus(9090), grafana(3001)
- api: 8080
- web: nginx static hosting + `/api` → `http://api:8080` reverse proxy

### Notes
- Container networking uses service names (mysql, redis, rabbitmq1, api).
- The web app uses relative `/api` by default.

## Golden images (ECR)
- Location: `infra/golden/`
- Docs: `infra/golden/README.md`

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
- Web (CRA): `cd apps/web && npm start` / `npm run build`
- Android: `cd apps/android && ./gradlew assembleDebug` (or `installDebug`)

## API placeholders (in-memory)
- Auth/Session: backed by Postgres (sessions table) + Redis cache/denylist.
- Users CRUD: backed by Postgres `users` table.
- Posts CRUD: backed by Postgres `posts` table; authorId defaults to current session user if present.
- Origin allowlist enforced for mutating routes.

## Migrations
- `infra/migrations/001_init.sql` contains sessions/refresh_tokens/devices schema skeleton.
