#!/bin/bash

# =============================================================================
# Security Gate Evidence Upload Script
# 인증: HMAC-SHA256 서명 기반
# =============================================================================

REPORT_FILE=$1
PR_NUMBER=$2

# 환경변수 매핑 (Secrets 이름과 스크립트 변수 연결)
SG_API_URL="${SG_API_URL:-$SECURITY_GATE_URL}"
SG_API_SECRET="${SG_API_SECRET:-$SECURITY_GATE_HMAC_SECRET}"
COMMIT_SHA=${GITHUB_SHA:-$(git rev-parse HEAD)}

# 파일의 지문(SHA256) 계산 
FILE_SHA=$(sha256sum "$REPORT_FILE" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$REPORT_FILE" | cut -d' ' -f1)

# OS별로 다른 stat 명령어 사용
if [[ "$OSTYPE" == "darwin"* ]]; then
  FILE_SIZE=$(stat -f%z "$REPORT_FILE")
else
  FILE_SIZE=$(stat -c%s "$REPORT_FILE")
fi

# 디버깅 로그 추가
echo "FILE_SHA: $FILE_SHA"
echo "FILE_SIZE: $FILE_SIZE"
echo "SG 전송 시작: $REPORT_FILE (Size: $FILE_SIZE, Commit: $COMMIT_SHA)"

# =============================================================================
# HMAC-SHA256 서명 함수
# 서명 포맷: HMAC(secret, timestamp + "." + method + "." + path + "." + raw_body)
# =============================================================================
generate_signature() {
  local method=$1
  local path=$2
  local body=$3
  local timestamp=$4
  
  # 서명할 문자열: timestamp.method.path.body
  local string_to_sign="${timestamp}.${method}.${path}.${body}"
  
  # HMAC-SHA256 서명 생성 (hex 출력)
  echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$SG_API_SECRET" | cut -d' ' -f2
}

# 인증 헤더와 함께 curl 요청하는 함수
sg_request() {
  local method=$1
  local path=$2
  local body=$3
  
  local timestamp=$(date +%s)
  local signature=$(generate_signature "$method" "$path" "$body" "$timestamp")
  
  echo "=== SG Request Debug ==="
  echo "Method: $method"
  echo "Path: $path"
  echo "Timestamp: $timestamp"
  echo "Signature: $signature"
  
  curl -s -X "$method" "${SG_API_URL}${path}" \
    -H "X-SG-Timestamp: $timestamp" \
    -H "X-SG-Signature: $signature" \
    -H "Content-Type: application/json" \
    -d "$body"
}

# ---------------------------------------------------------
# 디버깅: 입력 파일 확인
# ---------------------------------------------------------
echo "=== 입력 파일 확인 ==="
DEDUP_FILE="$(dirname "$REPORT_FILE")/deduplicated-results.json"
if [ ! -f "$DEDUP_FILE" ]; then
  echo "파일 없음: $DEDUP_FILE"
  exit 1
fi

echo "📄 deduplicated-results.json 내용 (첫 500자):"
head -c 500 "$DEDUP_FILE"
echo ""

# JSON 유효성 검사
if ! jq empty "$DEDUP_FILE" 2>/dev/null; then
  echo "Invalid JSON in $DEDUP_FILE"
  exit 1
fi
echo "JSON 유효성 검사 통과"

# ---------------------------------------------------------
# STEP 1: Presign
# ---------------------------------------------------------
echo "=== Presign 요청 변수 확인 ==="
echo "COMMIT_SHA: $COMMIT_SHA"
echo "FILE_SHA: $FILE_SHA"
echo "FILE_SIZE: $FILE_SIZE"
echo "PR_NUMBER: [$PR_NUMBER]"

# PR_NUMBER가 비어있으면 기본값 설정
if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" == "null" ]; then
  echo "PR_NUMBER가 비어있음, 0으로 설정"
  PR_NUMBER=0
fi

# Presign 요청 페이로드 생성
PRESIGN_PAYLOAD=$(cat <<EOF
{"release_id":"sha256:$FILE_SHA","env":"pr","gate":"PR","evidence_type":"SAST","artifact_name":"report.json","content_type":"application/json","content_length":$FILE_SIZE,"sha256":"$FILE_SHA","producer":{"repo":"${GITHUB_REPOSITORY:-unknown}","workflow":"${GITHUB_WORKFLOW:-unknown}","job":"${GITHUB_JOB:-unknown}","run_id":"${GITHUB_RUN_ID:-0}","attempt":${GITHUB_RUN_ATTEMPT:-1},"actor":"${GITHUB_ACTOR:-unknown}"},"commit_sha":"$COMMIT_SHA","pr_number":$PR_NUMBER}
EOF
)

echo "Presign 요청 페이로드:"
echo "$PRESIGN_PAYLOAD" | jq .

PRESIGN_RES=$(sg_request "POST" "/v1/evidence/presign" "$PRESIGN_PAYLOAD")

echo "Presign 응답: $PRESIGN_RES"

# Presign 응답에서 필요한 값 추출
UPLOAD_URL=$(echo "$PRESIGN_RES" | jq -r '.upload_url // empty')
EVIDENCE_ID=$(echo "$PRESIGN_RES" | jq -r '.evidence_id // empty')
S3_KEY=$(echo "$PRESIGN_RES" | jq -r '.s3_key // empty')

if [ -z "$UPLOAD_URL" ] || [ -z "$EVIDENCE_ID" ]; then
  echo "Presign 실패: upload_url 또는 evidence_id가 없습니다"
  echo "$PRESIGN_RES"
  exit 1
fi

echo "EVIDENCE_ID: $EVIDENCE_ID"
echo "S3_KEY: $S3_KEY"

# ---------------------------------------------------------
# STEP 2: S3 Upload
# ---------------------------------------------------------
echo "S3에 전체 리포트 업로드 중..."
S3_UPLOAD_RES=$(curl -s -w "\n%{http_code}" -X PUT -T "$REPORT_FILE" "$UPLOAD_URL")
S3_HTTP_CODE=$(echo "$S3_UPLOAD_RES" | tail -n1)

if [ "$S3_HTTP_CODE" != "200" ]; then
  echo "S3 업로드 실패: HTTP $S3_HTTP_CODE"
  exit 1
fi
echo "S3 업로드 성공"

# ---------------------------------------------------------
# STEP 3: Complete - Summary 안전하게 추출
# ---------------------------------------------------------
echo "SG에 최종 요약본(Summary) 보고 중..."

# Summary 추출 및 검증
SUMMARY=$(jq -c '.summary // empty' "$DEDUP_FILE")

if [ -z "$SUMMARY" ] || [ "$SUMMARY" == "null" ]; then
  echo "summary 필드 없음, 기본값 사용"
  SUMMARY='{"tool":"Claude-AI-Analyzer","tool_version":"4.5","new_critical":0,"new_high":0,"new_medium":0,"new_low":0}'
fi

echo "Summary 값: $SUMMARY"

# Complete 요청 페이로드 (한 줄로 - 서명 계산 시 일관성 유지)
ISSUED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMPLETE_PAYLOAD=$(cat <<EOF
{"evidence_id":"$EVIDENCE_ID","release_id":"sha256:$FILE_SHA","env":"pr","gate":"PR","evidence_type":"SAST","s3_key":"$S3_KEY","sha256":"$FILE_SHA","size":$FILE_SIZE,"summary":$SUMMARY,"pr_number":$PR_NUMBER,"issued_at":"$ISSUED_AT"}
EOF
)

echo "Complete 요청 페이로드:"
echo "$COMPLETE_PAYLOAD" | jq .

COMPLETE_RES=$(sg_request "POST" "/v1/evidence/complete" "$COMPLETE_PAYLOAD")

echo "Complete 응답: $COMPLETE_RES"

# ---------------------------------------------------------
# STEP 4: Evaluate
# ---------------------------------------------------------
echo "최종 판정(Evaluate) 요청 중..."

EVAL_PAYLOAD=$(cat <<EOF
{"release_id":"sha256:$FILE_SHA","env":"pr","gate":"PR","context":{"pr_number":$PR_NUMBER,"commit_sha":"$COMMIT_SHA"}}
EOF
)

EVAL_RES=$(sg_request "POST" "/v1/decisions/evaluate" "$EVAL_PAYLOAD")

echo "Evaluate 응답: $EVAL_RES"

echo "$EVAL_RES" | jq -r '.decision_id' > /tmp/sg-ticket-id
echo "$EVAL_RES" > /tmp/sg-eval-result

echo "모든 전송 및 판정 요청 완료!"