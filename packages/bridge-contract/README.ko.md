# Bridge Contract (한국어)

WebView 브릿지 메시지 계약을 정의합니다.

## 메시지 형식
- 요청: `{ id, version, type, payload }`
- 응답: `{ id, ok, payload?, error? }`

## Capabilities
- 협상: `capabilities.request` → `{ appVersion, bridgeVersion, supported }`
- 예시: `auth.getSession`, `nav.openExternal`, `device.getPushToken`, `media.pickImage`

## 에러 코드
`PERMISSION_DENIED`, `NOT_SUPPORTED`, `INVALID_PAYLOAD`, `INVALID_ORIGIN`, `TIMEOUT`, `INTERNAL_ERROR`

## Semver 정책
- MAJOR: 호환성 깨짐
- MINOR: 비파괴적 기능 추가
- PATCH: 버그 수정
- Android/Web은 major 호환성을 강제(1.x). CI에서 스키마 변경 diff로 브레이킹 여부를 감지하는 것을 권장.
