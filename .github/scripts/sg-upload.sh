#!/bin/bash
set -euo pipefail

# SG API를 통한 티켓 발급 및 S3 업로드 스크립트

# 환경변수 검증
: "${SG_API_URL:?SG_API_URL 환경변수가 필요합니다}"
: "${SG_API_TOKEN:?SG_API_TOKEN 환경변수가 필요합니다}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY 환경변수가 필요합니다}"
: "${GITHUB_SHA:?GITHUB_SHA 환경변수가 필요합니다}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID 환경변수가 필요합니다}"

# 파라미터 검증
REPORT_FILE="${1:?Usage: $0 <report-file> <pr-number>}"
PR_NUMBER="${2:?Usage: $0 <report-file> <pr-number>}"

if [ ! -f "$REPORT_FILE" ]; then
    echo "❌ Error: Report file not found: $REPORT_FILE"
    exit 1
fi

echo "🔐 Dark Mac & Cheese - SG Report Upload"
echo "========================================"
echo "Repository: $GITHUB_REPOSITORY"
echo "PR Number: $PR_NUMBER"
echo "Commit SHA: $GITHUB_SHA"
echo "Run ID: $GITHUB_RUN_ID"
echo "Report: $REPORT_FILE"
echo ""

# 1. SG API 호출 - 티켓 발급
echo "📝 Step 1: SG API 티켓 발급 요청 중..."

TICKET_RESPONSE=$(curl -s -X POST "$SG_API_URL/api/v1/tickets" \
    -H "Authorization: Bearer $SG_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"repo\": \"$GITHUB_REPOSITORY\",
        \"pr_number\": \"$PR_NUMBER\",
        \"sha\": \"$GITHUB_SHA\",
        \"run_id\": \"$GITHUB_RUN_ID\",
        \"workflow\": \"pr-sast\"
    }")

# 응답 검증
if ! echo "$TICKET_RESPONSE" | jq -e '.ticket_id' > /dev/null 2>&1; then
    echo "❌ Error: Invalid ticket response from SG API"
    echo "Response: $TICKET_RESPONSE"
    exit 1
fi

TICKET_ID=$(echo "$TICKET_RESPONSE" | jq -r '.ticket_id')
PRESIGNED_URL=$(echo "$TICKET_RESPONSE" | jq -r '.upload_url')

echo "✅ 티켓 발급 완료: $TICKET_ID"

# 티켓 ID를 파일에 저장 (워크플로우에서 사용)
echo "$TICKET_ID" > /tmp/sg-ticket-id

echo ""

# 2. S3에 리포트 업로드 (presigned URL 사용)
echo "📤 Step 2: S3에 리포트 업로드 중..."

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT "$PRESIGNED_URL" \
    -H "Content-Type: application/json" \
    --data-binary "@$REPORT_FILE")

if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "❌ Error: S3 upload failed (HTTP $HTTP_STATUS)"
    exit 1
fi

echo "✅ 리포트 업로드 완료"
echo ""

# 3. SG에 업로드 완료 통보
echo "📢 Step 3: SG에 업로드 완료 통보 중..."

NOTIFY_RESPONSE=$(curl -s -X POST "$SG_API_URL/api/v1/tickets/$TICKET_ID/complete" \
    -H "Authorization: Bearer $SG_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"status\": \"uploaded\",
        \"file_size\": $(stat -f%z "$REPORT_FILE" 2>/dev/null || stat -c%s "$REPORT_FILE"),
        \"checksum\": \"$(sha256sum "$REPORT_FILE" | awk '{print $1}')\"
    }")

# 응답 검증
if ! echo "$NOTIFY_RESPONSE" | jq -e '.status' > /dev/null 2>&1; then
    echo "❌ Error: Invalid notification response from SG API"
    echo "Response: $NOTIFY_RESPONSE"
    exit 1
fi

echo "✅ SG 통보 완료"
echo ""
echo "🎉 모든 단계 완료!"
echo ""
echo "Ticket ID: $TICKET_ID"
echo "You can check the verdict status at: $SG_API_URL/tickets/$TICKET_ID"
