# Architecture Notes (한국어)

## Monorepo 구조
- Apps: `apps/web` (Next.js App Router), `apps/android` (네이티브 WebView shell)
- Shared: 브릿지 계약, API 클라이언트, 공용 유틸/설정
- Infra: `infra/docker-compose.yml` (PostgreSQL, Redis)

## ADR 템플릿
`docs/architecture/adr/NNNN-title.md`에 다음 형식으로 작성:
```
# Title
Date: YYYY-MM-DD
Status: Proposed
Context: ...
Decision: ...
Consequences: ...
```

## 다이어그램
`docs/architecture/diagrams/`에 아키텍처/시퀀스 다이어그램(PlantUML/Mermaid 등)을 추가. 브릿지 계약, 세션 흐름 등을 문서화.
