# WebView App Platform Monorepo (한국어)

## 스택
- Monorepo: pnpm + turborepo
- Web: React (CRA) — `apps/web`은 [dbswhd4932/shoppingmall_project](https://github.com/dbswhd4932/shoppingmall_project) 프런트엔드 소스를 활용
- Backend: Spring Boot — `apps/api`는 같은 저장소의 백엔드 소스를 이관
- Android: Kotlin WebView Shell
- Shared: 브릿지 계약(zod), API 클라이언트, 공용 설정
- Infra: Postgres + Redis (docker-compose)

## 시작하기
1) 의존성 설치: `pnpm install`
<!-- 2) 인프라 실행(선택): `cd infra && docker compose up -d`
   - Spring Boot 백엔드(`apps/api`)는 `application-local.yml`에 맞춰 MySQL(3307, db: shoppingmall, user/pass: shopuser/shop1234), Redis(6379), RabbitMQ(5672)가 필요합니다.
3) DB 마이그레이션 적용:
   - 컨테이너 psql: `cd infra && docker compose cp migrations/001_init.sql postgres:/tmp/001_init.sql && docker compose cp migrations/002_users_posts.sql postgres:/tmp/002_users_posts.sql && docker compose exec -T postgres psql -U ${POSTGRES_USER:-appuser} -d ${POSTGRES_DB:-appdb} -f /tmp/001_init.sql && docker compose exec -T postgres psql -U ${POSTGRES_USER:-appuser} -d ${POSTGRES_DB:-appdb} -f /tmp/002_users_posts.sql`
   - 로컬 psql: `psql "$DATABASE_URL" -f infra/migrations/001_init.sql` 후 `.../002_users_posts.sql` -->
2) Web 개발 서버(CRA): `cd apps/web && npm install && npm start` (http://localhost:3000)
3) Backend 개발 서버: `cd apps/api && ./gradlew bootRun --args='--spring.profiles.active=local'`
4) Android 앱: `apps/android`를 Android Studio로 열거나 `cd apps/android && ./gradlew installDebug`
   - WebView 초기 URL: `http://10.0.2.2:3000` (에뮬레이터 기준)
   - 프록시(Burp 등)를 쓰면 10.0.2.2:3000 허용 또는 프록시 해제

## Docker Compose 로컬 실행
- 요구 버전: OpenJDK 21, Node.js 22.19.0, Docker Desktop 29.1.3, Docker Compose v5.0.0
- 루트에서 한번에 실행: `docker compose up -d --build`
- 중지: `docker compose stop` / 삭제: `docker compose down`
- 확인:
  - `docker compose ps`
  - `curl http://localhost:8080/actuator/health`
  - 브라우저: `http://localhost:3000`

### 구성 요약
- infra: mysql(3307->3306), redis(6379), rabbitmq(5672/15672), prometheus(9090), grafana(3001)
- api: 8080
- web: nginx 정적 서빙 + `/api` → `http://api:8080` 리버스 프록시

### 참고
- 컨테이너 환경은 서비스명으로 통신합니다 (예: mysql, redis, rabbitmq1, api).
- 웹은 기본적으로 `/api` 상대경로를 사용합니다.

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
- Web (CRA): `cd apps/web && npm start` / `npm run build`
- Android CLI: `cd apps/android && ./gradlew assembleDebug` 또는 `installDebug`
