#!/bin/bash

# =============================================================================
# Security Gate Upload Script (Trivy 호환 & Docker Image Digest 필수 버전)
# =============================================================================

REPORT_FILE=$1
PR_NUMBER=$2
TARGET_DIGEST=$3  # 3번째 인자: Docker Image Digest (필수)

# 환경변수 매핑
SG_API_URL="${SECURITY_GATE_URL}"
SG_API_SECRET="${SECURITY_GATE_HMAC_SECRET}"
COMMIT_SHA=${GITHUB_SHA}

# ---------------------------------------------------------
# 1. 필수 변수 및 파일 체크
# ---------------------------------------------------------

# 1) URL/Secret 체크
if [ -z "$SG_API_URL" ] || [ -z "$SG_API_SECRET" ]; then
  echo "Error: SECURITY_GATE_URL 또는 SECRET이 설정되지 않았습니다."
  exit 1
fi

# 2) 파일 존재 확인
if [ ! -f "$REPORT_FILE" ]; then
  echo "Error: 업로드할 파일이 없습니다: $REPORT_FILE"
  exit 1
fi

# 3) [중요] Docker Image Digest 체크 (Strict Mode)
if [ -z "$TARGET_DIGEST" ]; then
  echo "Error: Docker Image Digest($3)가 전달되지 않았습니다."
  echo "   이 파이프라인은 반드시 도커 이미지와 매핑되어야 합니다."
  exit 1
else
  RELEASE_ID="$TARGET_DIGEST"
  echo "[Target] Docker Image Digest: $RELEASE_ID"
fi

# ---------------------------------------------------------
# 파일 크기 및 해시 계산 (OS 호환성 처리)
# ---------------------------------------------------------
if [[ "$OSTYPE" == "darwin"* ]]; then
  FILE_SIZE=$(stat -f%z "$REPORT_FILE")
  FILE_SHA=$(shasum -a 256 "$REPORT_FILE" | cut -d' ' -f1)
else
  FILE_SIZE=$(stat -c%s "$REPORT_FILE")
  FILE_SHA=$(sha256sum "$REPORT_FILE" | cut -d' ' -f1)
fi

echo "[준비] 파일: $REPORT_FILE (Size: $FILE_SIZE)"

# ---------------------------------------------------------
# HMAC 서명 함수
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
# 2. Presign 요청 (업로드할 S3 주소 받기)
# ---------------------------------------------------------
echo "[1/3] Presign 요청 중..."

# release_id에는 도커 이미지의 Digest($RELEASE_ID)가 들어감 
PRESIGN_PAYLOAD=$(cat <<EOF
{
  "release_id": "$RELEASE_ID",
  "env": "pr",
  "gate": "PR",
  "evidence_type": "IMAGE_SCAN",
  "artifact_name": "scan.json",
  "content_type": "application/json",
  "content_length": $FILE_SIZE,
  "sha256": "$FILE_SHA",
  "producer": {
    "repo": "${GITHUB_REPOSITORY:-unknown}",
    "workflow": "${GITHUB_WORKFLOW:-unknown}",
    "job": "${GITHUB_JOB:-unknown}",
    "run_id": "${GITHUB_RUN_ID:-0}",
    "attempt": ${GITHUB_RUN_ATTEMPT:-1},
    "actor": "${GITHUB_ACTOR:-unknown}"
  },
  "commit_sha": "$COMMIT_SHA",
  "pr_number": ${PR_NUMBER:-0}
}
EOF
)

PRESIGN_RES=$(sg_request "POST" "/v1/evidence/presign" "$PRESIGN_PAYLOAD")
UPLOAD_URL=$(echo "$PRESIGN_RES" | jq -r '.upload_url // empty')
EVIDENCE_ID=$(echo "$PRESIGN_RES" | jq -r '.evidence_id // empty')

if [ -z "$UPLOAD_URL" ] || [ -z "$EVIDENCE_ID" ]; then
  echo "Presign 실패. 응답 내용:"
  echo "$PRESIGN_RES"
  exit 1
fi

# ---------------------------------------------------------
# 3. S3 Upload (받은 URL로 파일 전송)
# ---------------------------------------------------------
echo "[2/3] S3로 파일 업로드 중..."
HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X PUT -H "Content-Type: application/json" -T "$REPORT_FILE" "$UPLOAD_URL")

if [ "$HTTP_CODE" != "200" ]; then
  echo "S3 업로드 실패 (HTTP $HTTP_CODE)"
  exit 1
fi

# ---------------------------------------------------------
# 4. Complete (완료 통보)
# ---------------------------------------------------------
echo "[3/3] 완료 통보 중..."

SUMMARY='{"tool":"Trivy","note":"GitHub Actions Scan Uploaded"}'
ISSUED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

COMPLETE_PAYLOAD=$(cat <<EOF
{
  "evidence_id": "$EVIDENCE_ID",
  "release_id": "$RELEASE_ID",
  "env": "pr",
  "gate": "PR",
  "evidence_type": "IMAGE_SCAN",
  "sha256": "$FILE_SHA",
  "size": $FILE_SIZE,
  "issued_at": "$ISSUED_AT",
  "summary": $SUMMARY,
  "producer": {
    "repo": "$GITHUB_REPOSITORY"
  },
  "commit_sha": "$COMMIT_SHA",
  "pr_number": ${PR_NUMBER:-0}
}
EOF
)

COMPLETE_RES=$(sg_request "POST" "/v1/evidence/complete" "$COMPLETE_PAYLOAD")

echo "전송 성공! (Evidence ID: $EVIDENCE_ID)"