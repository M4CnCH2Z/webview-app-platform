#!/bin/bash

# 1. 재료 준비
REPORT_FILE=$1
PR_NUMBER=$2

COMMIT_SHA=${GITHUB_SHA:-$(git rev-parse HEAD)}

# 파일의 지문(SHA256) 계산 
FILE_SHA=$(sha256sum "$REPORT_FILE" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$REPORT_FILE" | cut -d' ' -f1)

# OS별로 다른 stat 명령어 사용
if [[ "$OSTYPE" == "darwin"* ]]; then
  FILE_SIZE=$(stat -f%z "$REPORT_FILE")
else
  FILE_SIZE=$(stat -c%s "$REPORT_FILE")
fi

# PR_NUMBER가 비어있으면 기본값 설정
if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" == "null" ]; then
  PR_NUMBER=0
fi

# 디버깅 로그
echo "FILE_SHA: $FILE_SHA"
echo "FILE_SIZE: $FILE_SIZE"
echo "PR_NUMBER: $PR_NUMBER"
echo "SG 전송 시작: $REPORT_FILE (Size: $FILE_SIZE, Commit: $COMMIT_SHA)"

# ---------------------------------------------------------
# 디버깅: 입력 파일 확인
# ---------------------------------------------------------
echo "=== 입력 파일 확인 ==="
DEDUP_FILE="$(dirname "$REPORT_FILE")/deduplicated-results.json"
if [ ! -f "$DEDUP_FILE" ]; then
  echo "파일 없음: $DEDUP_FILE"
  exit 1
fi

# JSON 유효성 검사
if ! jq empty "$DEDUP_FILE" 2>/dev/null; then
  echo "Invalid JSON in $DEDUP_FILE"
  exit 1
fi
echo "JSON 유효성 검사 통과"

# ---------------------------------------------------------
# 공통 producer 객체
# ---------------------------------------------------------
PRODUCER=$(cat <<EOF
{
  "repo": "${GITHUB_REPOSITORY:-unknown}",
  "workflow": "${GITHUB_WORKFLOW:-unknown}",
  "job": "${GITHUB_JOB:-unknown}",
  "run_id": "${GITHUB_RUN_ID:-0}",
  "attempt": ${GITHUB_RUN_ATTEMPT:-1},
  "actor": "${GITHUB_ACTOR:-unknown}"
}
EOF
)

# ---------------------------------------------------------
# STEP 1: Presign
# ---------------------------------------------------------
echo "📤 STEP 1: Presign 요청..."

PRESIGN_PAYLOAD=$(cat <<EOF
{
  "release_id": "sha256:$COMMIT_SHA",
  "env": "pr",
  "gate": "PR",
  "evidence_type": "SAST",
  "artifact_name": "report.json",
  "content_type": "application/json",
  "content_length": $FILE_SIZE,
  "sha256": "$FILE_SHA",
  "producer": $PRODUCER,
  "commit_sha": "$COMMIT_SHA",
  "pr_number": $PR_NUMBER
}
EOF
)

echo "Presign 페이로드:"
echo "$PRESIGN_PAYLOAD" | jq .

PRESIGN_RES=$(curl -s -X POST "$SG_API_URL/v1/evidence/presign" \
  -H "Authorization: Bearer $SG_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PRESIGN_PAYLOAD")

echo "Presign 응답: $PRESIGN_RES"

EVIDENCE_ID=$(echo "$PRESIGN_RES" | jq -r '.evidence_id')
UPLOAD_URL=$(echo "$PRESIGN_RES" | jq -r '.upload_url')
S3_KEY=$(echo "$PRESIGN_RES" | jq -r '.s3_key')

if [ "$EVIDENCE_ID" == "null" ] || [ -z "$EVIDENCE_ID" ]; then
  echo "Presign 실패"
  exit 1
fi
echo "Presign 성공: $EVIDENCE_ID"

# ---------------------------------------------------------
# STEP 2: S3 Upload
# ---------------------------------------------------------
echo "STEP 2: S3 업로드..."
curl -s -X PUT -T "$REPORT_FILE" "$UPLOAD_URL"
echo "S3 업로드 완료"

# ---------------------------------------------------------
# STEP 3: Complete
# ---------------------------------------------------------
echo "📤 STEP 3: Complete 요청..."

SUMMARY=$(jq -c '.summary // {}' "$DEDUP_FILE")

COMPLETE_PAYLOAD=$(cat <<EOF
{
  "evidence_id": "$EVIDENCE_ID",
  "release_id": "sha256:$COMMIT_SHA",
  "env": "pr",
  "gate": "PR",
  "evidence_type": "SAST",
  "s3_key": "$S3_KEY",
  "sha256": "$FILE_SHA",
  "size": $FILE_SIZE,
  "issued_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "summary": $SUMMARY,
  "producer": $PRODUCER,
  "commit_sha": "$COMMIT_SHA",
  "pr_number": $PR_NUMBER
}
EOF
)

echo "Complete 페이로드:"
echo "$COMPLETE_PAYLOAD" | jq .

COMPLETE_RES=$(curl -s -X POST "$SG_API_URL/v1/evidence/complete" \
  -H "Authorization: Bearer $SG_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$COMPLETE_PAYLOAD")

echo "Complete 응답: $COMPLETE_RES"

# ---------------------------------------------------------
# STEP 4: Evaluate
# ---------------------------------------------------------
echo "⚖️ STEP 4: Evaluate 요청..."

EVAL_PAYLOAD=$(cat <<EOF
{
  "release_id": "sha256:$COMMIT_SHA",
  "env": "pr",
  "gate": "PR",
  "context": {
    "pr_number": $PR_NUMBER,
    "commit_sha": "$COMMIT_SHA"
  }
}
EOF
)

echo "Evaluate 페이로드:"
echo "$EVAL_PAYLOAD" | jq .

EVAL_RES=$(curl -s -X POST "$SG_API_URL/v1/decisions/evaluate" \
  -H "Authorization: Bearer $SG_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$EVAL_PAYLOAD")

echo "Evaluate 응답: $EVAL_RES"

# decision 값 추출 (PASS/FAIL)
DECISION=$(echo "$EVAL_RES" | jq -r '.decision // "PENDING"')
echo "🎯 판정 결과: $DECISION"

# 결과 저장
echo "$EVAL_RES" > /tmp/sg-eval-result
echo "$DECISION" > /tmp/sg-decision

echo "모든 전송 및 판정 요청 완료!"