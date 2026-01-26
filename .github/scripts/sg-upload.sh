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
REPO=${GITHUB_REPOSITORY:-$(git config --get remote.origin.url | sed -n 's#.*/\\(.*\\)\\.git#\\1#p')}
SG_ENV="${SG_ENV:-pr}"
SG_GATE="${SG_GATE:-PR}"
SG_EVIDENCE_TYPE="${SG_EVIDENCE_TYPE:-SAST}"
SG_ARTIFACT_NAME="${SG_ARTIFACT_NAME:-report.json}"
SG_RELEASE_ID="${SG_RELEASE_ID:-}"
SG_SUMMARY_FILE="${SG_SUMMARY_FILE:-}"
SG_RUN_ID="${SG_RUN_ID:-${GITHUB_RUN_ID:-}}"
SG_EXECUTION_ENV="${SG_EXECUTION_ENV:-}"
SG_TARGET_URL="${SG_TARGET_URL:-}"
SG_SPEC_HASH="${SG_SPEC_HASH:-}"
SG_COMPOSE_HASH="${SG_COMPOSE_HASH:-}"
SG_ENV_HASH="${SG_ENV_HASH:-}"
SG_LIMITS_RPS="${SG_LIMITS_RPS:-}"
SG_LIMITS_CONCURRENCY="${SG_LIMITS_CONCURRENCY:-}"
SG_LIMITS_MAX_REQUESTS="${SG_LIMITS_MAX_REQUESTS:-}"
SG_LIMITS_TIMEOUT="${SG_LIMITS_TIMEOUT:-}"
SG_TOOL_NAME="${SG_TOOL_NAME:-}"
SG_TOOL_VERSION="${SG_TOOL_VERSION:-}"
SG_DEBUG_PAYLOAD_PATH="${SG_DEBUG_PAYLOAD_PATH:-}"

if [ -z "$SG_API_URL" ] || [ -z "$SG_API_SECRET" ]; then
  echo "Error: SG_API_URL 또는 SG_API_SECRET이 설정되지 않았습니다."
  exit 1
fi

echo "SG_API_URL: $SG_API_URL"

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

# release_id 결정 (기본: 파일 SHA, 필요 시 override)
if [ -n "$SG_RELEASE_ID" ]; then
  if [[ "$SG_RELEASE_ID" == sha256:* ]]; then
    RELEASE_ID="$SG_RELEASE_ID"
  else
    RELEASE_ID="sha256:$SG_RELEASE_ID"
  fi
else
  RELEASE_ID="sha256:$FILE_SHA"
fi

echo "Release ID: $RELEASE_ID"
echo "Environment: $SG_ENV, Gate: $SG_GATE, Evidence: $SG_EVIDENCE_TYPE"

# python3 필수 확인 (jq 대체용)
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3가 필요합니다 (jq 대체용)."
  exit 1
fi

# JSON 유틸리티 (python3)
json_pretty() {
  python3 -c 'import sys,json; data=sys.stdin.read(); 
try:
    obj=json.loads(data); 
    print(json.dumps(obj, indent=2, ensure_ascii=False))
except Exception:
    print(data)' 
}

json_get_field() {
  local field="$1"
  python3 -c 'import sys,json; field=sys.argv[1]; data=sys.stdin.read(); 
try:
    obj=json.loads(data); 
    print(obj.get(field,""))
except Exception:
    print("")' "$field"
}

json_summary_from_file() {
  local file="$1"
  python3 - <<PY
import json, sys
with open("$file","rb") as f:
    obj = json.loads(f.read().decode("utf-8"))
summary = obj.get("summary", obj)
print(json.dumps(summary, separators=(",",":")))
PY
}

json_results_summary_from_file() {
  local file="$1"
  python3 - <<PY
import json, sys
with open("$file","rb") as f:
    obj = json.loads(f.read().decode("utf-8"))
summary = obj.get("summary", obj)
def to_int(v):
    try:
        return int(v)
    except Exception:
        return 0
rs = {
  "critical": to_int(summary.get("findings_critical", 0)),
  "high": to_int(summary.get("findings_high", 0)),
  "medium": to_int(summary.get("findings_medium", 0)),
  "low": to_int(summary.get("findings_low", 0)),
  "findings": summary.get("findings", [])
}
print(json.dumps(rs, separators=(",",":")))
PY
}

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
  
  # 디버그는 stderr로 출력 (>&2 추가)
  echo "=== SG Request Debug ===" >&2
  echo "Method: $method" >&2
  echo "Path: $path" >&2
  echo "Timestamp: $timestamp" >&2
  echo "Signature: $signature" >&2
  
  # curl 결과만 stdout으로 반환
  local res
  res=$(curl -sS -X "$method" "${SG_API_URL}${path}" \
    -H "X-SG-Timestamp: $timestamp" \
    -H "X-SG-Signature: $signature" \
    -H "Content-Type: application/json" \
    -d "$body")
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "curl failed (exit $rc) for $path" >&2
  fi
  echo "$res"
}

# ---------------------------------------------------------
# 디버깅: 입력 파일 확인
# ---------------------------------------------------------
echo "=== 입력 파일 확인 ==="
DEDUP_FILE="$(dirname "$REPORT_FILE")/deduplicated-results.json"
SUMMARY_SOURCE="${SG_SUMMARY_FILE:-$DEDUP_FILE}"

if [ -z "$SG_SUMMARY_FILE" ]; then
  if [ ! -f "$DEDUP_FILE" ]; then
    echo "파일 없음: $DEDUP_FILE"
    exit 1
  fi
else
  if [ ! -f "$SUMMARY_SOURCE" ]; then
    echo "파일 없음: $SUMMARY_SOURCE"
    exit 1
  fi
fi

echo "📄 요약 입력 파일 내용 (첫 500자): $SUMMARY_SOURCE"
head -c 500 "$SUMMARY_SOURCE"
echo ""

# JSON 유효성 검사 (jq 우선, 실패 시 python3로 재검증)
python3 - <<PY
import json, sys
with open("$SUMMARY_SOURCE","rb") as f:
    json.loads(f.read().decode("utf-8"))
PY
if [ $? -ne 0 ]; then
  echo "Invalid JSON in $SUMMARY_SOURCE"
  exit 1
fi
echo "JSON 유효성 검사 통과 (python3)"

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
{"release_id":"$RELEASE_ID","env":"$SG_ENV","gate":"$SG_GATE","evidence_type":"$SG_EVIDENCE_TYPE","artifact_name":"$SG_ARTIFACT_NAME","content_type":"application/json","content_length":$FILE_SIZE,"sha256":"$FILE_SHA","run_id":"${GITHUB_RUN_ID:-0}","producer":{"repo":"${GITHUB_REPOSITORY:-unknown}","workflow":"${GITHUB_WORKFLOW:-unknown}","job":"${GITHUB_JOB:-unknown}","run_id":"${GITHUB_RUN_ID:-0}","attempt":${GITHUB_RUN_ATTEMPT:-1},"actor":"${GITHUB_ACTOR:-unknown}"},"commit_sha":"$COMMIT_SHA","pr_number":$PR_NUMBER}
EOF
)

echo "Presign 요청 페이로드:"
echo "$PRESIGN_PAYLOAD" | json_pretty

if [ -n "$SG_DEBUG_PAYLOAD_PATH" ]; then
  mkdir -p "$(dirname "$SG_DEBUG_PAYLOAD_PATH")"
  printf '%s' "$PRESIGN_PAYLOAD" > "$SG_DEBUG_PAYLOAD_PATH"
fi

PRESIGN_RES=$(sg_request "POST" "/v1/evidence/presign" "$PRESIGN_PAYLOAD")

echo "Presign 응답: $PRESIGN_RES"

# Presign 응답에서 필요한 값 추출
UPLOAD_URL=$(printf '%s' "$PRESIGN_RES" | json_get_field "upload_url")
EVIDENCE_ID=$(printf '%s' "$PRESIGN_RES" | json_get_field "evidence_id")
S3_KEY=$(printf '%s' "$PRESIGN_RES" | json_get_field "s3_key")

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
S3_UPLOAD_RES=$(curl -s -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" -T "$REPORT_FILE" "$UPLOAD_URL")
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
SUMMARY=$(json_summary_from_file "$SUMMARY_SOURCE")
RESULTS_SUMMARY=$(json_results_summary_from_file "$SUMMARY_SOURCE")

if [ -z "$SUMMARY" ] || [ "$SUMMARY" == "null" ]; then
  echo "summary 필드 없음, 기본값 사용"
  SUMMARY='{"tool":"Claude-AI-Analyzer","tool_version":"4.5","new_critical":0,"new_high":0,"new_medium":0,"new_low":0}'
fi

echo "Summary 값: $SUMMARY"

# Complete 요청 페이로드 (한 줄로 - 서명 계산 시 일관성 유지)
ISSUED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ "$SG_EVIDENCE_TYPE" = "LOCAL_PENTEST" ]; then
  COMPLETE_PAYLOAD=$(cat <<EOF
{"evidence_id":"$EVIDENCE_ID","release_id":"$RELEASE_ID","env":"$SG_ENV","gate":"$SG_GATE","evidence_type":"$SG_EVIDENCE_TYPE","s3_key":"$S3_KEY","sha256":"$FILE_SHA","size":$FILE_SIZE,"issued_at":"$ISSUED_AT","parser_version":"1.0.0","run_id":"$SG_RUN_ID","execution_env":"$SG_EXECUTION_ENV","target_profile":{"target_url":"$SG_TARGET_URL","spec_hash":"$SG_SPEC_HASH","compose_hash":"$SG_COMPOSE_HASH","env_hash":"$SG_ENV_HASH"},"limits":{"rps":${SG_LIMITS_RPS:-0},"concurrency":${SG_LIMITS_CONCURRENCY:-0},"max_requests":${SG_LIMITS_MAX_REQUESTS:-0},"timeout":${SG_LIMITS_TIMEOUT:-0}},"tool_list":[{"name":"$SG_TOOL_NAME","version":"$SG_TOOL_VERSION"}],"results_summary":$RESULTS_SUMMARY,"producer":{"repo":"${GITHUB_REPOSITORY:-unknown}","workflow":"${GITHUB_WORKFLOW:-unknown}","job":"${GITHUB_JOB:-unknown}","run_id":"${GITHUB_RUN_ID:-0}","attempt":${GITHUB_RUN_ATTEMPT:-1},"actor":"${GITHUB_ACTOR:-unknown}"},"commit_sha":"$COMMIT_SHA","pr_number":$PR_NUMBER}
EOF
)
else
  COMPLETE_PAYLOAD=$(cat <<EOF
{"evidence_id":"$EVIDENCE_ID","release_id":"$RELEASE_ID","env":"$SG_ENV","gate":"$SG_GATE","evidence_type":"$SG_EVIDENCE_TYPE","s3_key":"$S3_KEY","sha256":"$FILE_SHA","size":$FILE_SIZE,"issued_at":"$ISSUED_AT","parser_version":"1.0.0","summary":$SUMMARY,"producer":{"repo":"${GITHUB_REPOSITORY:-unknown}","workflow":"${GITHUB_WORKFLOW:-unknown}","job":"${GITHUB_JOB:-unknown}","run_id":"${GITHUB_RUN_ID:-0}","attempt":${GITHUB_RUN_ATTEMPT:-1},"actor":"${GITHUB_ACTOR:-unknown}"},"commit_sha":"$COMMIT_SHA","pr_number":$PR_NUMBER}
EOF
)
fi

echo "Complete 요청 페이로드:"
echo "$COMPLETE_PAYLOAD" | json_pretty

COMPLETE_RES=$(sg_request "POST" "/v1/evidence/complete" "$COMPLETE_PAYLOAD")

echo "Complete 응답: $COMPLETE_RES"

# ---------------------------------------------------------
# STEP 4: Evaluate
# ---------------------------------------------------------
echo "최종 판정(Evaluate) 요청 중..."

EVAL_PAYLOAD=$(cat <<EOF
{"release_id":"$RELEASE_ID","env":"$SG_ENV","gate":"$SG_GATE","context":{"repo":"$REPO","pr_number":$PR_NUMBER,"commit_sha":"$COMMIT_SHA"}}
EOF
)

EVAL_RES=$(sg_request "POST" "/v1/decisions/evaluate" "$EVAL_PAYLOAD")

echo "Evaluate 응답: $EVAL_RES"

echo "$EVAL_RES" | json_get_field "decision_id" > /tmp/sg-ticket-id
echo "$EVAL_RES" > /tmp/sg-eval-result

echo "모든 전송 및 판정 요청 완료!"
