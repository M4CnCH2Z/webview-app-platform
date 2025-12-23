# Architecture Notes

> 한국어: [README.ko.md](README.ko.md)

## Monorepo Layout
- Apps: `apps/web` (Next.js App Router), `apps/android` (native WebView shell)
- Shared packages: bridge contract, API client, shared utilities, lint/tsconfig configs
- Infra: `infra/docker-compose.yml` for PostgreSQL and Redis

## ADR Template
Create files under `docs/architecture/adr/NNNN-title.md` using:
```
# Title
Date: YYYY-MM-DD
Status: Proposed
Context: ...
Decision: ...
Consequences: ...
```

## Diagrams
Use `docs/architecture/diagrams/` for architecture/system sequence diagrams (e.g., PlantUML or Mermaid). Keep bridge contract and session flows documented.
