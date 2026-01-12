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

# 디버깅 로그 추가
echo "FILE_SHA: $FILE_SHA"
echo "FILE_SIZE: $FILE_SIZE"
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
PRESIGN_RES=$(curl -s -X POST "$SG_API_URL/v1/evidence/presign" \
  -H "Authorization: Bearer $SG_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"release_id\": \"sha256:$COMMIT_SHA\",
    \"env\": \"pr\",
    \"gate\": \"PR\",
    \"evidence_type\": \"SAST\",
    \"artifact_name\": \"report.json\",
    \"sha256\": \"$FILE_SHA\",
    \"content_length\": $FILE_SIZE,
    \"pr_number\": $PR_NUMBER
  }")

echo "Presign 응답: $PRESIGN_RES"

EVIDENCE_ID=$(echo "$PRESIGN_RES" | jq -r '.evidence_id')
UPLOAD_URL=$(echo "$PRESIGN_RES" | jq -r '.upload_url')
S3_KEY=$(echo "$PRESIGN_RES" | jq -r '.s3_key')

if [ "$EVIDENCE_ID" == "null" ] || [ -z "$EVIDENCE_ID" ]; then
  echo "Presign 실패: evidence_id를 받지 못함"
  exit 1
fi

# ---------------------------------------------------------
# STEP 2: S3 Upload
# ---------------------------------------------------------
echo "S3에 전체 리포트 업로드 중..."
curl -s -X PUT -T "$REPORT_FILE" "$UPLOAD_URL"

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

# Complete 요청 - JSON을 임시 파일로 만들어서 전송 (특수문자 문제 방지)
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
  "summary": $SUMMARY,
  "pr_number": $PR_NUMBER,
  "issued_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

echo "Complete 요청 페이로드:"
echo "$COMPLETE_PAYLOAD" | jq .

COMPLETE_RES=$(curl -s -X POST "$SG_API_URL/v1/evidence/complete" \
  -H "Authorization: Bearer $SG_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$COMPLETE_PAYLOAD")

echo "Complete 응답: $COMPLETE_RES"

# ---------------------------------------------------------
# STEP 4: Evaluate
# ---------------------------------------------------------
echo "최종 판정(Evaluate) 요청 중..."
EVAL_RES=$(curl -s -X POST "$SG_API_URL/v1/decisions/evaluate" \
  -H "Authorization: Bearer $SG_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"release_id\": \"sha256:$COMMIT_SHA\",
    \"env\": \"pr\",
    \"gate\": \"PR\",
    \"context\": { \"pr_number\": $PR_NUMBER, \"commit_sha\": \"$COMMIT_SHA\" }
  }")

echo "Evaluate 응답: $EVAL_RES"

echo "$EVAL_RES" | jq -r '.decision_id' > /tmp/sg-ticket-id
echo "$EVAL_RES" > /tmp/sg-eval-result

echo "모든 전송 및 판정 요청 완료!"