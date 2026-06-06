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
| [ADR-004](004-csr-frontend.md) | CSR-only frontend (no SSR) | Accepted | 2024 |

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
