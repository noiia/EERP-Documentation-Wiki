# ADR-001: Custom ORM over GORM / ent

**Status**: Accepted
**Date**: 2024

---

## Context

EERP needs to map Go structs to PostgreSQL rows. Several mature ORM libraries exist in the Go ecosystem. The question is whether to use one of them or build a custom layer.

EERP has specific requirements that differ from typical web applications:

1. **No runtime reflection cost**: ERP systems can execute dozens of queries per request. The overhead of repeated reflection to map column values to struct fields compounds at scale.
2. **Soft-delete by default**: Every entity in an ERP must support soft-delete for audit trail purposes. It shouldn't be an opt-in feature.
3. **Savepoints**: ERP operations frequently require partial rollback within a transaction (e.g., creating an order header succeeds even if creating the lines fails). Not all ORMs expose savepoints.
4. **Predictable SQL**: The generated SQL must be deterministic and auditable. Black-box query generation is a liability when debugging slow queries in production.
5. **Batch operations**: Creating 50 order lines should produce a single INSERT statement, not 50 round-trips.

---

## Decision

Build a custom ORM layer on top of [pgx v5](https://github.com/jackc/pgx).

The custom ORM:
- Uses `reflect.VisibleFields` **once per type at startup**, caching the result in a `sync.Map`
- Exposes a type-safe builder API using Go generics
- Has explicit support for soft-delete via the `softdelete` struct tag
- Exposes savepoints via `tx.Savepoint`, `tx.RollbackTo`, and `tx.Release`
- Generates SQL that is logged verbatim (no hidden transformations)
- Supports multi-row VALUES in batch inserts

---

## Consequences

**Positive:**
- Zero reflection at query time — the only reflection cost is at startup
- SQL is always visible and predictable
- Soft-delete, savepoints, and batch operations are first-class features
- No dependency on a large third-party framework that may not support new PostgreSQL features
- The ORM can evolve to match EERP's exact needs

**Negative:**
- Maintenance burden: the ORM must be maintained by the EERP team
- Missing features that GORM/ent provide out of the box (schema auto-migration, hooks, associations)
- New contributors must learn the EERP ORM rather than an industry-standard tool
- Less battle-tested than GORM (millions of production deployments)

---

## Alternatives Considered

### GORM

GORM is the most widely used Go ORM. It provides a rich feature set including associations, hooks, and auto-migration.

**Rejected because:**
- Uses reflection on every query for field mapping
- Soft-delete is opt-in and inconsistently implemented
- Generated SQL is not always obvious; debugging requires enabling verbose logging and understanding GORM's internal state machine
- Savepoints are not natively exposed
- The API surface is large; many features overlap in subtle ways

### ent (Meta's ORM)

ent uses code generation to produce type-safe query builders from a schema definition file.

**Rejected because:**
- Requires a separate schema language and code generation step, adding toolchain complexity
- Generated code is verbose and harder to navigate for contributors
- Schema-first design conflicts with EERP's module-first design where entities are defined by modules
- Less control over the exact SQL generated

### sqlx

sqlx is a thin layer over `database/sql` that adds named struct scanning.

**Rejected because:**
- Uses `database/sql` instead of pgx, losing PostgreSQL-specific type support and performance
- No query builder — all SQL must be written by hand
- No support for the specific patterns EERP needs (soft-delete, batch insert, savepoints as first-class concepts)
