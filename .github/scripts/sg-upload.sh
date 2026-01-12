#!/bin/bash

# 1. 재료 준비
REPORT_FILE=$1
PR_NUMBER=$2

# COMMIT_SHA 환경 변수 설정 (GitHub Actions에서는 GITHUB_SHA, 로컬에서는 git 명령 사용)
COMMIT_SHA=${GITHUB_SHA:-$(git rev-parse HEAD)}

# 파일의 지문(SHA256)과 크기를 미리 계산해둡니다 (명세서 필수값)
# macOS와 Linux 모두 호환되도록 수정
FILE_SHA=$(shasum -a 256 "$REPORT_FILE" 2>/dev/null || sha256sum "$REPORT_FILE" | cut -d' ' -f1)

# OS별로 다른 stat 명령어 사용
if [[ "$OSTYPE" == "darwin"* ]]; then
  FILE_SIZE=$(stat -f%z "$REPORT_FILE")
else
  FILE_SIZE=$(stat -c%s "$REPORT_FILE")
fi

echo "SG 전송 시작: $REPORT_FILE (Size: $FILE_SIZE, Commit: $COMMIT_SHA)"

# ---------------------------------------------------------
# STEP 1: Presign (서버한테 파일 올릴 주소 달라고 하기)
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

# 서버가 준 금고 번호(evidence_id)와 금고 주소(upload_url)를 챙깁니다.
EVIDENCE_ID=$(echo "$PRESIGN_RES" | jq -r '.evidence_id')
UPLOAD_URL=$(echo "$PRESIGN_RES" | jq -r '.upload_url')
S3_KEY=$(echo "$PRESIGN_RES" | jq -r '.s3_key')

# ---------------------------------------------------------
# STEP 2: S3 Upload (실제 파일 실물을 창고에 넣기)
# ---------------------------------------------------------
echo "S3에 전체 리포트 업로드 중..."
curl -s -X PUT -T "$REPORT_FILE" "$UPLOAD_URL"

# ---------------------------------------------------------
# STEP 3: Complete (파일 넣었으니 요약 숫자 보고하기)
# ---------------------------------------------------------
echo "SG에 최종 요약본(Summary) 보고 중..."
SUMMARY=$(jq -c '.summary' "$(dirname "$REPORT_FILE")/deduplicated-results.json")

curl -s -X POST "$SG_API_URL/v1/evidence/complete" \
  -H "Authorization: Bearer $SG_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"evidence_id\": \"$EVIDENCE_ID\",
    \"release_id\": \"sha256:$COMMIT_SHA\",
    \"env\": \"pr\",
    \"gate\": \"PR\",
    \"evidence_type\": \"SAST\",
    \"s3_key\": \"$S3_KEY\",
    \"sha256\": \"$FILE_SHA\",
    \"size\": $FILE_SIZE,
    \"summary\": $SUMMARY,
    \"pr_number\": $PR_NUMBER,
    \"issued_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"
  }"

# ---------------------------------------------------------
# STEP 4: Evaluate (판정해달라고 요청하기)
# ---------------------------------------------------------
echo "⚖️ 최종 판정(Evaluate) 요청 중..."
EVAL_RES=$(curl -s -X POST "$SG_API_URL/v1/decisions/evaluate" \
  -H "Authorization: Bearer $SG_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"release_id\": \"sha256:$COMMIT_SHA\",
    \"env\": \"pr\",
    \"gate\": \"PR\",
    \"context\": { \"pr_number\": $PR_NUMBER, \"commit_sha\": \"$COMMIT_SHA\" }
  }")

# 판정 결과(PASS/FAIL/PENDING)를 다음 Job에서 볼 수 있게 저장!
# 명세서상 티켓 ID 대신 decision_id를 저장하거나 결과 전체를 저장 
echo "$EVAL_RES" | jq -r '.decision_id' > /tmp/sg-ticket-id
echo "$EVAL_RES" > /tmp/sg-eval-result

echo "모든 전송 및 판정 요청 완료!"