# Architecture Decision Records

Architecture Decision Records (ADRs) document significant design choices made in EERP: what was decided, why, and what alternatives were considered.

ADRs are **immutable** once accepted. If a decision is reversed or superseded, a new ADR is created rather than editing the old one.

---

## Status Legend

| Status | Meaning |
|---|---|
| **Accepted** | Decision is in effect |
| **Superseded** | Replaced by a later ADR |
| **Proposed** | Under discussion |
| **Rejected** | Considered but not adopted |

---

## Index

| ID | Title | Status | Date |
|---|---|---|---|
| [ADR-001](001-custom-orm.md) | Custom ORM over GORM / ent | Accepted | 2024 |
| [ADR-002](002-wasm-modules.md) | WebAssembly for module isolation | Accepted | 2024 |
| [ADR-003](003-soft-delete.md) | Soft delete as the default delete strategy | Accepted | 2024 |
| [ADR-004](004-csr-frontend.md) | React frontend on a Next.js server with Zustand state | Accepted | 2024 (rev. 2026-06-16) |
| [ADR-005](005-jwt-auth.md) | JWT authentication with stateful refresh tokens | Accepted | 2026-06-08 |
| [ADR-006](006-view-inheritance.md) | Frontend view inheritance | Accepted | 2026-07-09 |
| [ADR-007](007-runtime-view-fields.md) | Runtime-configurable view fields (Kanban/Calendar) | Accepted | 2026-07-09 |
| [ADR-008](008-form-anatomy.md) | Default form anatomy — synthesized header, columns, notebook | Accepted | 2026-07-10 |
| [ADR-009](009-module-lifecycle-api.md) | Module lifecycle managed via API | Superseded (Decision 1, by ADR-010) | 2026-07-10 |
| [ADR-010](010-live-module-lifecycle.md) | Live module lifecycle — activate/deactivate/reload with no restart | Accepted | 2026-07-11 |
| [ADR-011](011-pdf-report-generation.md) | PDF report generation — external Chromium-backed service | Accepted | 2026-08 |
| [ADR-012](012-form-actions-menu.md) | Form actions menu — default chrome for custom actions | Accepted | 2026-08 |
| [ADR-013](013-multi-company.md) | Multi-company — several companies per tenant, company-scoped settings | Accepted | 2026-08 |
| [ADR-014](014-field-level-group-gating.md) | Field-level group gating + role "belongs" inheritance | Accepted | 2026-08 |
| [ADR-015](015-search-filter-bar.md) | Built-in search/filter bar for list views | Accepted | 2026-08 |
| [ADR-016](016-undo-toast.md) | Generic undo toast — default hard-delete affordance | Accepted | 2026-08 |
| [ADR-017](017-cron-scheduler.md) | Background cron scheduler over the generic CRUD surface | Accepted | 2026-08 |
| [ADR-018](018-http2-edge-rest-batching.md) | HTTP/2 at the gateway edge, batching over GraphQL | Accepted | 2026-08 |
| [ADR-019](019-per-model-view-files.md) | One view file per DB model, one file per report | Accepted | 2026-08-27 |

---

## How to Write an ADR

Create a new file in `docs/adrs/` following the naming pattern `NNN-short-title.md` and the structure below:

```markdown
# ADR-NNN: Title

**Status**: Accepted | Superseded | Proposed | Rejected
**Date**: YYYY-MM-DD

## Context

What is the situation that requires a decision? What forces are at play?

## Decision

What was decided? State it clearly and directly.

## Consequences

What are the positive and negative consequences of this decision?

## Alternatives Considered

What other options were evaluated? Why were they rejected?
```

Add a row to the index table above and add the ADR to the `nav` in `mkdocs.yml`.
