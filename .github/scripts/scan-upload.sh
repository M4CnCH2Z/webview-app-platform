#!/bin/bash

# =============================================================================
# Security Gate Upload Script (Trivy Image Scan) - Final Schema Version
# =============================================================================

set -e

REPORT_FILE=$1
PR_NUMBER=$2
TARGET_DIGEST=$3 

# 환경변수
SG_API_URL="${SECURITY_GATE_URL}"
SG_API_SECRET="${SECURITY_GATE_HMAC_SECRET}"
COMMIT_SHA="${GITHUB_SHA}"

# ---------------------------------------------------------
# 1. 필수 변수 체크
# ---------------------------------------------------------
if [ -z "$SG_API_URL" ] || [ -z "$SG_API_SECRET" ]; then
  echo "Error: SECURITY_GATE_URL 또는 SECRET이 설정되지 않았습니다."
  exit 1
fi

if [ ! -f "$REPORT_FILE" ]; then
  echo "Error: 업로드할 파일이 없습니다: $REPORT_FILE"
  exit 1
fi

if [ -z "$TARGET_DIGEST" ]; then
  echo "Error: Docker Image Digest가 전달되지 않았습니다."
  exit 1
fi

# 접두사(sha256:) 확인 및 강제 부착 로직
if [[ "$TARGET_DIGEST" == sha256:* ]]; then
  # 이미 접두사가 있으면 그대로 사용
  RELEASE_ID="$TARGET_DIGEST"
else
  # 접두사가 없으면 붙여줌
  echo "Digest에 'sha256:' 접두사가 없어 자동으로 추가합니다."
  RELEASE_ID="sha256:$TARGET_DIGEST"
fi

echo "[Image Scan] Release ID: $RELEASE_ID"

# ---------------------------------------------------------
# 2. 파일 정보 계산
# ---------------------------------------------------------
if [[ "$OSTYPE" == "darwin"* ]]; then
  FILE_SIZE=$(stat -f%z "$REPORT_FILE")
  FILE_SHA=$(shasum -a 256 "$REPORT_FILE" | cut -d' ' -f1)
else
  FILE_SIZE=$(stat -c%s "$REPORT_FILE")
  FILE_SHA=$(sha256sum "$REPORT_FILE" | cut -d' ' -f1)
fi

echo "파일: $REPORT_FILE (Size: $FILE_SIZE)"

# ---------------------------------------------------------
# 3. HMAC 서명 함수
# ---------------------------------------------------------
generate_signature() {
  local method=$1
  local path=$2
  local body=$3
  local timestamp=$4
  echo -n "${timestamp}.${method}.${path}.${body}" | openssl dgst -sha256 -hmac "$SG_API_SECRET" | cut -d' ' -f2
}

sg_request() {
  local method=$1
  local path=$2
  local body=$3
  local timestamp=$(date +%s)
  local signature=$(generate_signature "$method" "$path" "$body" "$timestamp")
  
  curl -s -X "$method" "${SG_API_URL}${path}" \
    -H "X-SG-Timestamp: $timestamp" \
    -H "X-SG-Signature: $signature" \
    -H "Content-Type: application/json" \
    -d "$body"
}

# ---------------------------------------------------------
# 4. Environment / Gate 결정
# ---------------------------------------------------------
if [ "${PR_NUMBER:-0}" != "0" ] && [ -n "$PR_NUMBER" ]; then
  ENV_VALUE="pr"
  GATE_VALUE="PR"
else
  ENV_VALUE="staging"
  GATE_VALUE="STAGING_PROMOTE"
fi

echo "Environment: $ENV_VALUE, Gate: $GATE_VALUE"

# ---------------------------------------------------------
# 5. Presign 요청
# ---------------------------------------------------------
echo "[1/3] Presign 요청 중..."

PRESIGN_PAYLOAD=$(jq -n \
  --arg release_id "$RELEASE_ID" \
  --arg env "$ENV_VALUE" \
  --arg gate "$GATE_VALUE" \
  --arg artifact_name "scan.json" \
  --argjson content_length "$FILE_SIZE" \
  --arg sha256 "$FILE_SHA" \
  --arg repo "${GITHUB_REPOSITORY}" \
  --arg workflow "${GITHUB_WORKFLOW:-unknown}" \
  --arg job "${GITHUB_JOB:-unknown}" \
  --arg run_id "${GITHUB_RUN_ID:-0}" \
  --argjson attempt "${GITHUB_RUN_ATTEMPT:-1}" \
  --arg actor "${GITHUB_ACTOR:-unknown}" \
  --arg commit_sha "$COMMIT_SHA" \
  --argjson pr_number "${PR_NUMBER:-0}" \
  '{
    release_id: $release_id,
    env: $env,
    gate: $gate,
    evidence_type: "IMAGE_SCAN",
    artifact_name: $artifact_name,
    content_type: "application/json",
    content_length: $content_length,
    sha256: $sha256,
    producer: {
      repo: $repo,
      workflow: $workflow,
      job: $job,
      run_id: $run_id,
      attempt: $attempt,
      actor: $actor
    },
    commit_sha: $commit_sha,
    pr_number: $pr_number
  }')

PRESIGN_RES=$(sg_request "POST" "/v1/evidence/presign" "$PRESIGN_PAYLOAD")
UPLOAD_URL=$(echo "$PRESIGN_RES" | jq -r '.upload_url // empty')
EVIDENCE_ID=$(echo "$PRESIGN_RES" | jq -r '.evidence_id // empty')
S3_KEY=$(echo "$PRESIGN_RES" | jq -r '.s3_key // empty')

if [ -z "$UPLOAD_URL" ] || [ -z "$EVIDENCE_ID" ]; then
  echo "Presign 실패:"
  echo "$PRESIGN_RES"
  exit 1
fi

echo "Evidence ID: $EVIDENCE_ID"

# ---------------------------------------------------------
# 6. S3 Upload
# ---------------------------------------------------------
echo "[2/3] S3로 파일 업로드 중..."
HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X PUT \
  -H "Content-Type: application/json" \
  -T "$REPORT_FILE" "$UPLOAD_URL")

if [ "$HTTP_CODE" != "200" ]; then
  echo "S3 업로드 실패 (HTTP $HTTP_CODE)"
  exit 1
fi

echo "S3 업로드 완료"

# ---------------------------------------------------------
# 7. Complete 요청 (데이터 파싱)
# ---------------------------------------------------------
echo "[3/3] Complete 통보 중..."

ISSUED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Trivy JSON 결과에서 요약 정보 추출 (모든 등급 + Fixable)
# jq 문법: ?는 필드가 없을 경우 에러 방지, length로 개수 셈
CRITICAL_COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$REPORT_FILE" 2>/dev/null || echo 0)
HIGH_COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$REPORT_FILE" 2>/dev/null || echo 0)
MEDIUM_COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="MEDIUM")] | length' "$REPORT_FILE" 2>/dev/null || echo 0)
LOW_COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="LOW")] | length' "$REPORT_FILE" 2>/dev/null || echo 0)
# Fixable: FixedVersion 필드가 존재하고 비어있지 않은 경우
FIXABLE_COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.FixedVersion != null and .FixedVersion != "")] | length' "$REPORT_FILE" 2>/dev/null || echo 0)

echo "스캔 요약: Critical=$CRITICAL_COUNT, High=$HIGH_COUNT, Medium=$MEDIUM_COUNT, Low=$LOW_COUNT, Fixable=$FIXABLE_COUNT"

COMPLETE_PAYLOAD=$(jq -n \
  --arg evidence_id "$EVIDENCE_ID" \
  --arg release_id "$RELEASE_ID" \
  --arg env "$ENV_VALUE" \
  --arg gate "$GATE_VALUE" \
  --arg s3_key "$S3_KEY" \
  --arg sha256 "$FILE_SHA" \
  --argjson size "$FILE_SIZE" \
  --arg issued_at "$ISSUED_AT" \
  --argjson critical "$CRITICAL_COUNT" \
  --argjson high "$HIGH_COUNT" \
  --argjson medium "$MEDIUM_COUNT" \
  --argjson low "$LOW_COUNT" \
  --argjson fixable "$FIXABLE_COUNT" \
  --arg repo "${GITHUB_REPOSITORY}" \
  --arg workflow "${GITHUB_WORKFLOW:-unknown}" \
  --arg job "${GITHUB_JOB:-unknown}" \
  --arg run_id "${GITHUB_RUN_ID:-0}" \
  --argjson attempt "${GITHUB_RUN_ATTEMPT:-1}" \
  --arg actor "${GITHUB_ACTOR:-unknown}" \
  --arg commit_sha "$COMMIT_SHA" \
  --argjson pr_number "${PR_NUMBER:-0}" \
  '{
    evidence_id: $evidence_id,
    release_id: $release_id,
    env: $env,
    gate: $gate,
    evidence_type: "IMAGE_SCAN",
    s3_key: $s3_key,
    sha256: $sha256,
    size: $size,
    issued_at: $issued_at,
    parser_version: "v0",
    summary: {
      tool: "trivy",
      tool_version: "unknown",
      critical: $critical,
      high: $high,
      medium: $medium,
      low: $low,
      fixable: $fixable
    },
    producer: {
      repo: $repo,
      workflow: $workflow,
      job: $job,
      run_id: $run_id,
      attempt: $attempt,
      actor: $actor
    },
    commit_sha: $commit_sha,
    pr_number: $pr_number
  }')

COMPLETE_RES=$(sg_request "POST" "/v1/evidence/complete" "$COMPLETE_PAYLOAD")

# Complete 응답 검증
echo "Complete 응답:"
echo "$COMPLETE_RES"

STATUS=$(echo "$COMPLETE_RES" | jq -r '.status // empty')

if [ -z "$STATUS" ]; then
  echo "Error: Complete API가 status를 반환하지 않았습니다"
  echo "Full Response: $COMPLETE_RES"
  exit 1
fi

if [ "$STATUS" != "RECORDED" ]; then
  echo "Warning: Evidence가 제대로 기록되지 않았을 수 있습니다"
  echo "Expected status: RECORDED, Got: $STATUS"
  exit 1
fi

echo ""
echo "IMAGE_SCAN 전송 완료!"
echo "   Evidence ID: $EVIDENCE_ID"
echo "   Status: $STATUS"
echo "   Summary: Crit=$CRITICAL_COUNT, High=$HIGH_COUNT, Med=$MEDIUM_COUNT, Low=$LOW_COUNT"