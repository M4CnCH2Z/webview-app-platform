# CI/CD Workflows

## 개요
- PR, main, nightly, Android release용 GitHub Actions 워크플로우 추가
- 변경 경로 기반 실행(dorny/paths-filter@v3):
  - `apps/web/**` → web job
  - `apps/android/**` → android job
  - `packages/bridge-contract/**` → web + android 모두 실행
- 워크플로우는 항상 트리거되지만, 변경이 없으면 해당 job 내에서 “Skipping” 처리 후 성공으로 종료 → required check 안정화

## 워크플로우 파일
- `.github/workflows/pr-ci.yml`: pull_request/dispatch용
- `.github/workflows/main-ci-cd.yml`: main push/dispatch용, web/android 배포 placeholder 포함
- `.github/workflows/nightly.yml`: 매일 03:00 KST(18:00 UTC) + dispatch, 최소 lint/build
- `.github/workflows/android-release.yml`: 태그 `android-v*` + dispatch, release placeholder(환경 보호 예시)

## 주요 설정
- concurrency: PR `pr-${{ github.ref }}`, main `main-${{ github.ref }}`, nightly `nightly-group`, release `release-android-${{ github.ref }}`
- 캐시:
  - pnpm store (`~/.pnpm-store`)
  - turborepo (`./.turbo`)
  - Gradle (`~/.gradle/caches`, `~/.gradle/wrapper`)
  - 키: OS + lockfile/gradle-wrapper hash
- Node: setup-node@v4 (v20), corepack enable → pnpm
- Java: setup-java@v4 (temurin 17)

## 실행 플로우
- PR: 항상 트리거 → paths-filter → web/android 조건부 실행, 미해당 시 스킵 후 성공
- main: 동일 조건 + web deploy placeholder, android internal/QA deploy placeholder
- nightly: web lint+build, android lint+assemble (조건 체크 없이 최소 빌드)
- android release: 태그 `android-v*` → assembleRelease + 서명/업로드 placeholder (환경 보호 사용 예시)

## 로컬 재현
- web: `pnpm install --frozen-lockfile && pnpm turbo run lint test build --filter=apps/web...`
- android: `cd apps/android && ./gradlew lint testDebugUnitTest assembleDebug` (wrapper 경로 맞추어 조정)
- nightly 수준: `pnpm turbo run lint build --filter=apps/web...` 와 android lint/assemble

## 설계 이유
- required check 안정성: 변경이 없어도 워크플로우/잡은 성공 상태로 종료
- 변경 영향 최소화: paths-filter로 web/android/bridge별 필요한 작업만 수행
- 캐시 적극 활용: pnpm/turbo/Gradle 캐시로 CI 비용 감소
- 스케줄: 03:00 KST 주기 점검으로 잠복 이슈 조기 발견
