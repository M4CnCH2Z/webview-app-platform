# WebView App Platform Monorepo (한국어)

## 스택
- Monorepo: pnpm + turborepo
- Web/BFF: Next.js (App Router) + Route Handlers
- Android: Kotlin WebView Shell
- Shared: 브릿지 계약(zod), API 클라이언트, 공용 설정
- Infra: Postgres + Redis (docker-compose)

## 시작하기
1) 의존성 설치: `pnpm install`
2) 인프라 실행(선택): `cd infra && docker compose up -d`
3) DB 마이그레이션 적용:
   - 컨테이너 psql: `cd infra && docker compose cp migrations/001_init.sql postgres:/tmp/001_init.sql && docker compose cp migrations/002_users_posts.sql postgres:/tmp/002_users_posts.sql && docker compose exec -T postgres psql -U ${POSTGRES_USER:-appuser} -d ${POSTGRES_DB:-appdb} -f /tmp/001_init.sql && docker compose exec -T postgres psql -U ${POSTGRES_USER:-appuser} -d ${POSTGRES_DB:-appdb} -f /tmp/002_users_posts.sql`
   - 로컬 psql: `psql "$DATABASE_URL" -f infra/migrations/001_init.sql` 후 `.../002_users_posts.sql`
4) Web/BFF 개발 서버: 루트에서 `pnpm dev` (http://localhost:3000)
5) Android 앱: `apps/android`를 Android Studio로 열거나 `cd apps/android && ./gradlew installDebug`
   - WebView 초기 URL: `http://10.0.2.2:3000` (에뮬레이터 기준)
   - 프록시(Burp 등)를 쓰면 10.0.2.2:3000 허용 또는 프록시 해제

## 브릿지 계약
- 메시지: `{ id, version, type, payload }` → `{ id, ok, payload?, error? }`
- Capabilities: `capabilities.request` -> `{ appVersion, bridgeVersion, supported[] }`
- 예시: `auth.getSession`, `nav.openExternal`, `device.getPushToken`, `media.pickImage`
- 에러 코드: `PERMISSION_DENIED`, `NOT_SUPPORTED`, `INVALID_PAYLOAD`, `INVALID_ORIGIN`, `TIMEOUT`, `INTERNAL_ERROR`
- Semver: MAJOR 호환성 유지(1.x), CI에서 브레이킹 변경 감지 권장

## 보안 기본
- Android WebView: 오리진 allowlist, dev에서만 cleartext 허용, 외부 URL은 시스템 브라우저로 분리, debug 빌드에만 WebView 디버깅.
- Web: CSP, X-Frame-Options DENY, Origin allowlist, SameSite=Lax HttpOnly 세션 쿠키(secure는 prod에서만).

## API / 데이터
- Auth/Session: Postgres `sessions` 테이블 + Redis 캐시/denylist.
- Users CRUD: Postgres `users`.
- Posts CRUD: Postgres `posts`; 로그인 세션이 있으면 authorId 자동 사용, 수동 지정 시 UUID 필요.

## 환경 변수
- `.env.example` 참고: `DATABASE_URL`, `REDIS_URL`, `ALLOWLIST_ORIGINS`, `SESSION_COOKIE_NAME` 등.

## 스크립트
- `pnpm dev` / `pnpm build` / `pnpm lint` / `pnpm typecheck`
- Android CLI: `cd apps/android && ./gradlew assembleDebug` 또는 `installDebug`
