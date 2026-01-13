# 🔧 PR SAST Workflow 설정 가이드

이 문서는 PR SAST 보안 워크플로우를 설정하는 전체 과정을 안내합니다.

---

## 📋 목차

1. [GitHub Secrets 설정](#1-github-secrets-설정)
2. [Branch Protection Rules 설정](#2-branch-protection-rules-설정)
3. [Environment Protection 설정](#3-environment-protection-설정)
4. [SonarQube 설정](#4-sonarqube-설정)
5. [테스트 실행](#5-테스트-실행)
6. [트러블슈팅](#6-트러블슈팅)

---

## 1. GitHub Secrets 설정

### 1.1 Repository Secrets 추가

GitHub 저장소 → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

필수 Secrets:

| Secret 이름 | 설명 | 값 예시 | 우선순위 |
|-------------|------|---------|---------|
| `ANTHROPIC_API_KEY` | Claude API 키 | `sk-ant-api03-...` | 🔴 필수 |
| `SG_API_URL` | Security Gate API URL | `https://sg-api.example.com` | 🔴 필수 |
| `SG_API_TOKEN` | SG 인증 토큰 | `Bearer xyz123...` | 🔴 필수 |
| `SONAR_TOKEN` | SonarQube 토큰 | `squ_abc123...` | 🟡 권장 |
| `SONAR_HOST_URL` | SonarQube 서버 | `https://sonar.example.com` | 🟡 권장 |
| `SONAR_PROJECT_KEY` | SonarQube 프로젝트 | `dark-mac-cheese` | 🟡 권장 |
| `SEMGREP_APP_TOKEN` | Semgrep 토큰 (선택) | `sgp_abc123...` | ⚪ 선택 |

### 1.2 API 키 발급 방법

#### ANTHROPIC_API_KEY

1. [Anthropic Console](https://console.anthropic.com/) 접속
2. **API Keys** 메뉴
3. **Create Key** 클릭
4. 키 이름 입력 (예: `github-actions-pr-sast`)
5. 생성된 키 복사 (한 번만 표시됨!)

#### SG_API_TOKEN

```bash
# SG API에서 토큰 발급 (예시)
curl -X POST https://sg-api.example.com/auth/token \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "github-actions",
    "client_secret": "your-secret"
  }' | jq -r '.access_token'
```

#### SONAR_TOKEN

1. SonarQube 서버 로그인
2. **My Account** → **Security**
3. **Generate Tokens** 섹션
4. 토큰 이름 입력: `github-actions`
5. **Generate** 클릭

---

## 2. Branch Protection Rules 설정

### 2.1 main 브랜치 보호 설정

GitHub 저장소 → **Settings** → **Branches** → **Add rule**

#### 필수 설정

| 설정 항목 | 값 |
|----------|---|
| Branch name pattern | `main` |
| ✅ Require a pull request before merging | ON |
| ✅ Require approvals | 1명 이상 |
| ✅ Require status checks to pass before merging | ON |
| Required status checks | `Security Gate Verdict` |
| ✅ Require branches to be up to date | ON |
| ✅ Do not allow bypassing the above settings | ON |

#### 추가 권장 설정

| 설정 항목 | 설명 |
|----------|------|
| ✅ Require conversation resolution | 모든 코멘트 해결 필수 |
| ✅ Require signed commits | 커밋 서명 필수 (보안 강화) |
| ✅ Restrict who can push | 관리자만 직접 push 가능 |

### 2.2 설정 확인

1. 테스트 PR 생성
2. `Security Gate Verdict` 체크 대기 중인지 확인
3. 체크 PASS 전까지 **Merge** 버튼 비활성화 확인

---

## 3. Environment Protection 설정

### 3.1 staging Environment 생성

GitHub 저장소 → **Settings** → **Environments** → **New environment**

**Environment name**: `staging`

#### Protection Rules

| 설정 | 값 |
|------|---|
| ✅ Required reviewers | 보안팀, 인프라팀 (최소 1명) |
| Wait timer | 0분 (즉시 승인 가능) |
| Deployment branches | `main` (main 브랜치만 배포 가능) |

#### Environment secrets (staging 전용)

| Secret 이름 | 설명 |
|-------------|------|
| `AWS_ROLE_ARN` | EKS 배포용 IAM Role |
| `KUBE_CONFIG` | staging kubeconfig |

### 3.2 테스트

1. main 브랜치에 merge
2. GitHub Actions → Push 워크플로우 실행
3. Deploy job이 "Waiting for approval" 상태인지 확인
4. 승인 버튼 클릭 → 배포 진행 확인

---

## 4. SonarQube 설정

### 4.1 프로젝트 생성

SonarQube 서버에서:

1. **Projects** → **Create Project**
2. Project Key: `dark-mac-cheese`
3. Display Name: `Dark Mac & Cheese`
4. Main Branch: `main`

### 4.2 Quality Gate 설정

**Administration** → **Quality Gates** → **Create**

권장 조건:

| Metric | Operator | Value |
|--------|----------|-------|
| Security Hotspots Reviewed | is less than | 100% |
| Security Rating | is worse than | A |
| Reliability Rating | is worse than | A |
| Coverage | is less than | 80% |

### 4.3 Webhook 설정 (선택)

SonarQube → **Administration** → **Webhooks**

- URL: `https://sg-api.example.com/webhooks/sonarqube`
- Secret: (SG와 공유)

---

## 5. 테스트 실행

### 5.1 PR 워크플로우 테스트

```bash
# 1. 새 브랜치 생성
git checkout -b test/pr-sast

# 2. 변경 사항 커밋
echo "// test" >> apps/web/src/index.ts
git add .
git commit -m "test: PR SAST workflow"

# 3. Push
git push origin test/pr-sast

# 4. PR 생성
gh pr create --title "Test: PR SAST" --body "Testing security scan workflow"
```

### 5.2 확인 사항

GitHub Actions 탭에서:

- [ ] SonarQube job 성공
- [ ] Semgrep job 성공
- [ ] CodeQL job 성공
- [ ] AI Analysis job 성공
- [ ] Upload to SG job 성공
- [ ] GitHub Check `Security Gate Verdict` 생성됨
- [ ] PR에 보안 리포트 코멘트 달림
- [ ] Artifacts에 `final-security-report` 업로드됨

### 5.3 SG 판정 확인

```bash
# SG API에서 티켓 상태 조회
TICKET_ID="from-workflow-log"

curl -H "Authorization: Bearer $SG_API_TOKEN" \
  "$SG_API_URL/api/v1/tickets/$TICKET_ID/verdict"
```

예상 응답:
```json
{
  "ticket_id": "abc123",
  "status": "pass",
  "score": 85,
  "critical_issues": 0,
  "high_issues": 2
}
```

---

## 6. 트러블슈팅

### 문제 1: SonarQube 연결 실패

**증상**:
```
Error: SonarQube server unreachable
```

**해결**:
1. `SONAR_HOST_URL` 확인 (https:// 포함)
2. 방화벽 규칙 확인
3. GitHub Actions IP 대역 허용

### 문제 2: Claude API 할당량 초과

**증상**:
```
❌ Claude API 호출 실패: RateLimitError
```

**해결**:
1. [Anthropic Console](https://console.anthropic.com/) → **Settings** → **Billing**
2. Usage 확인
3. 필요 시 플랜 업그레이드
4. 또는 워크플로우에 rate limiting 추가:

```yaml
- name: Run Claude AI Analysis
  uses: nick-fields/retry-action@v2
  with:
    timeout_minutes: 10
    max_attempts: 3
    retry_wait_seconds: 60
    command: python3 .github/scripts/llm-analyzer.py scan-results
```

### 문제 3: SG 판정 timeout

**증상**:
```
❌ Timeout: SG 판정을 받지 못했습니다
```

**해결**:
1. SG 로그 확인:
   ```bash
   kubectl logs -n sg -l app=sg-api --tail=100
   ```
2. 티켓 상태 수동 확인:
   ```bash
   curl -H "Authorization: Bearer $SG_API_TOKEN" \
     "$SG_API_URL/api/v1/tickets/$TICKET_ID"
   ```
3. 워크플로우의 timeout 값 조정:
   ```yaml
   MAX_ATTEMPTS=60  # 5분 → 10분
   ```

### 문제 4: Branch Protection Check 안 뜸

**증상**: PR merge 버튼이 활성화되어 있음

**해결**:
1. Branch Protection Rules에서 `Security Gate Verdict` 체크 이름 확인
2. 워크플로우의 Check 생성 부분 확인:
   ```yaml
   name: 'Security Gate Verdict'  # 정확히 일치해야 함
   ```
3. Check가 생성되었는지 확인:
   ```bash
   gh api repos/:owner/:repo/commits/:sha/check-runs
   ```

---

## 📊 설정 완료 체크리스트

- [ ] GitHub Secrets 8개 설정 완료
- [ ] main 브랜치 Protection Rules 설정
- [ ] staging Environment 생성 및 Required Reviewers 지정
- [ ] SonarQube 프로젝트 생성 및 Quality Gate 설정
- [ ] 테스트 PR로 전체 워크플로우 검증
- [ ] SG API 연동 확인
- [ ] GitHub Check 생성 확인
- [ ] Branch Protection 동작 확인

---

## 🚀 다음 단계

설정 완료 후:

1. **팀 교육**: 워크플로우 사용법 공유
2. **모니터링**: SG 대시보드에서 트렌드 확인
3. **최적화**: False Positive 패턴 분석 및 규칙 조정
4. **확장**: Push 워크플로우 설정 (SCA, Image Scan)

---

**문의**: Security Team (#security-gate Slack)
