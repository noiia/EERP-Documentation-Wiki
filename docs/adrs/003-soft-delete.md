# ADR-003: Soft Delete as the Default Delete Strategy

**Status**: Accepted
**Date**: 2024

---

## Context

ERP systems have a different relationship with data deletion than most applications. In a standard web app, deleting a record means removing it from the system. In an ERP:

- A deleted customer may still be referenced by historical invoices.
- A deactivated product may still appear on order history.
- A terminated employee's payroll records must be preserved for legal compliance.
- Auditors need to see what existed at any point in time.

The question is whether delete operations should remove rows from the database or mark them as deleted while keeping the data.

---

## Decision

**Soft delete is the default.** `model.BaseModel` includes a `deleted_at *time.Time` column. When `Repository.Delete()` is called, it sets `deleted_at = NOW()`. All standard reads (`FindByID`, `FindOne`, `FindAll`, `Count`) automatically exclude soft-deleted rows via `WHERE deleted_at IS NULL`.

Hard delete is available but explicit: `Repository.HardDelete()`. This naming makes it impossible to accidentally hard-delete data.

Restoration is also explicit: `Repository.Restore()` clears `deleted_at`.

---

## Consequences

**Positive:**
- **Audit trail**: Deleted data is never lost. Historical reports remain accurate.
- **Compliance**: Meets legal requirements for record retention (e.g., accounting records must be kept for N years).
- **Recovery**: Accidentally deleted records can be restored.
- **Referential integrity**: Foreign keys pointing to a soft-deleted record remain valid.

**Negative:**
- **Storage growth**: Deleted rows are never reclaimed automatically. Tables grow larger over time.
- **Query performance**: Every query must include `WHERE deleted_at IS NULL`. This requires a partial index on `deleted_at` for performance.
- **Complexity for raw queries**: Developers writing ad-hoc queries (outside the ORM) must remember to add the soft-delete filter manually.
- **Unique constraints**: A column that must be unique (e.g., email) can have multiple soft-deleted rows with the same value. Partial unique indexes are required: `CREATE UNIQUE INDEX ON users (email) WHERE deleted_at IS NULL`.

---

## Mitigations

### Partial indexes for performance

```sql
CREATE INDEX ON contacts (deleted_at) WHERE deleted_at IS NULL;
```

This index is small (only active rows) and fast.

### Partial unique constraints

```sql
CREATE UNIQUE INDEX ON contacts (email) WHERE deleted_at IS NULL;
```

### Archival strategy

For very large tables, soft-deleted rows older than a retention period can be moved to an archive table and hard-deleted:

```sql
-- Run monthly by a background job
INSERT INTO contacts_archive SELECT * FROM contacts WHERE deleted_at < NOW() - INTERVAL '7 years';
DELETE FROM contacts WHERE deleted_at < NOW() - INTERVAL '7 years';
```

---

## Alternatives Considered

### Hard delete by default

Delete rows immediately. Maintain an audit log table separately.

**Rejected because:**
- Referential integrity breaks: foreign keys point to rows that no longer exist.
- Audit log tables require separate maintenance and may go out of sync with the main table.
- Restoration is not possible without a backup restore.

### Versioning (event sourcing)

Keep every version of every record in an append-only table. The current state is always the latest version.

**Rejected for now because:**
- Significantly more complex to implement and query.
- Requires all reads to aggregate history to get current state.
- May be the right choice for specific high-audit domains (e.g., accounting) but is overkill as a universal strategy.
- Can be layered on top of soft-delete for specific entities without changing the universal default.
