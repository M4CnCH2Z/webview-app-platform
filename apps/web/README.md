# @platform/web

Next.js(App Router) 앱과 BFF(Route Handlers)용 패키지입니다.

## 주요 스크립트
- `pnpm dev` (루트에서): Next.js dev 서버
- `pnpm -C apps/web test`: Vitest 기반 단위 테스트
- `pnpm -C apps/web lint`: ESLint
- `pnpm -C apps/web build`: Next.js 빌드

## 구조
- `app/`: Next.js App Router 엔트리
  - `api/`: BFF/Route Handlers (auth, session, users, posts)
  - `login`, `users`, `posts` 등 페이지
- `app/lib`: 브릿지 클라이언트(wrapper) 등 클라이언트 유틸
- `next.config.js`: CSP/보안 헤더 및 dev용 eval 허용 설정

## 백엔드 연동
- Postgres: `DATABASE_URL` 환경 변수 사용
- Redis: `REDIS_URL` 환경 변수 사용 (세션 캐시/denylist)
- 세션 쿠키: 개발 환경에서는 secure=false, 프로덕션은 secure=true

## 테스트
- `vitest` 설정: `apps/web/vitest.config.ts`
- 주요 유닛 테스트 예시: `app/api/_lib/session.test.ts` (DB/Redis 모킹)
