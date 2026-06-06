# Testing

EERP follows Go's standard testing approach: table-driven tests, real database for integration tests, and no mock frameworks. The ORM's `Executor` interface means tests can share infrastructure between unit and integration levels.

---

## Test Levels

| Level | Hits the DB? | Speed | Tests |
|---|---|---|---|
| Unit | No | Fast | Business logic, query builders, struct tag parsing |
| Integration | Yes (real PostgreSQL) | Medium | Repository operations, transactions, full service flows |

There is no third "mock database" level. Mocking the database produces tests that pass even when the SQL is wrong. See the rationale in [ADR-001](../adrs/001-custom-orm.md).

---

## Running Tests

### All ORM unit tests

```bash
make run-back-tests BACKTESTPATH=./orm/...
```

### Integration tests (requires Docker database)

Start the database first:

```bash
docker compose up -d
```

Then run:

```bash
make run-back-tests BACKTESTPATH=./orm/pool/db/...
```

### Single test

```bash
make run-back-tests BACKTESTPATH=./orm/... ARGS="-run TestFindOne"
```

### All tests with verbose output

```bash
make run-back-tests BACKTESTPATH=./... ARGS="-v"
```

---

## Unit Tests: Query Builders

Query builders produce SQL strings. Test them by asserting on the generated SQL and arguments — no database needed.

```go
func TestSelectBuilder(t *testing.T) {
    meta := // build or mock StructMeta for Item

    tests := []struct {
        name    string
        builder *orm.SelectBuilder[Item]
        wantSQL string
        wantArgs []any
    }{
        {
            name: "all active items",
            builder: orm.Select[Item](meta).
                Where(orm.Cond("deleted_at IS NULL")).
                OrderBy("name ASC").
                Limit(10),
            wantSQL:  "SELECT * FROM inventory_items WHERE deleted_at IS NULL ORDER BY name ASC LIMIT 10",
            wantArgs: nil,
        },
        {
            name: "filter by stock",
            builder: orm.Select[Item](meta).
                Where(orm.Cond("stock_qty > $1", 0)),
            wantSQL:  "SELECT * FROM inventory_items WHERE stock_qty > $1",
            wantArgs: []any{0},
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            sql, args, err := tt.builder.ToSQL()
            require.NoError(t, err)
            assert.Equal(t, tt.wantSQL, sql)
            assert.Equal(t, tt.wantArgs, args)
        })
    }
}
```

---

## Unit Tests: Service Logic

Test domain invariants without a database by using a fake executor or transaction:

```go
func TestConvertToCustomerAlreadyCustomer(t *testing.T) {
    contact := Contact{Status: "customer"}
    // ... mock FindByID to return this contact
    
    _, err := svc.ConvertToCustomer(ctx, contact.ID)
    assert.ErrorIs(t, err, ErrAlreadyCustomer)
}
```

For services that use the ORM, prefer integration tests with a real database over fake executors. The ORM's `Executor` interface makes this easy.

---

## Integration Tests: Repository

Use a real test database. The recommended pattern:

```go
package crm_test

import (
    "context"
    "testing"
    "eerp/core/orm"
    "eerp/core/modules/crm/internal"
    "eerp/core/testutil"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestContactCreate(t *testing.T) {
    ctx := context.Background()
    db := testutil.OpenTestDB(t)           // (1)
    defer testutil.CleanTable(t, db, "contacts") // (2)

    repo := orm.MustRepo[crm.Contact](db)

    contact := crm.Contact{
        Name:    "Alice Martin",
        Email:   "alice@example.com",
        Company: "Acme Corp",
        Status:  "lead",
    }

    created, err := repo.Create(ctx, contact)
    require.NoError(t, err)

    assert.NotEmpty(t, created.ID)
    assert.Equal(t, "Alice Martin", created.Name)
    assert.False(t, created.CreatedAt.IsZero())

    // Verify it's findable
    found, err := repo.FindByID(ctx, created.ID)
    require.NoError(t, err)
    assert.Equal(t, created.ID, found.ID)
}
```

1. `testutil.OpenTestDB(t)` opens a connection to the test database (same DSN as `eerp-config.json` by default, or `TEST_DSN` env var). It registers `t.Cleanup(db.Close)`.
2. `testutil.CleanTable` truncates the table after the test. Alternatively, use transactions (see below).

---

## Integration Tests: Transactions for Isolation

The cleanest way to isolate integration tests is to wrap each test in a transaction and roll it back:

```go
func TestContactSoftDelete(t *testing.T) {
    ctx := context.Background()
    db := testutil.OpenTestDB(t)

    var id uuid.UUID

    // Run in a transaction, then roll back
    _ = orm.Transact(ctx, db, func(tx *orm.Tx) error {
        repo := orm.MustRepo[crm.Contact](db).WithTx(tx)

        created, err := repo.Create(ctx, crm.Contact{Name: "Bob", Email: "bob@example.com"})
        require.NoError(t, err)
        id = created.ID

        n, err := repo.Delete(ctx, id)
        require.NoError(t, err)
        assert.Equal(t, int64(1), n)

        // Should not be findable after soft-delete
        _, err = repo.FindByID(ctx, id)
        assert.ErrorIs(t, err, orm.ErrNotFound)

        return errors.New("rollback intentionally")  // triggers rollback
    })

    // No cleanup needed — transaction was rolled back
}
```

---

## Integration Tests: Full Service Flow

Test complete use cases end-to-end with a real database:

```go
func TestConvertToCustomer(t *testing.T) {
    ctx := context.Background()
    db := testutil.OpenTestDB(t)
    svc := crm.New(db)

    // Arrange
    lead, err := svc.Create(ctx, crm.Contact{
        Name:   "Carol White",
        Email:  "carol@example.com",
        Status: "lead",
    })
    require.NoError(t, err)
    t.Cleanup(func() {
        _, _ = orm.MustRepo[crm.Contact](db).HardDelete(ctx, lead.ID)
    })

    // Act
    customer, err := svc.ConvertToCustomer(ctx, lead.ID)

    // Assert
    require.NoError(t, err)
    assert.Equal(t, "customer", customer.Status)
    assert.Equal(t, lead.ID, customer.ID)
}
```

---

## Table-Driven Tests

For operations with many variations (e.g., testing all SQL operator conditions):

```go
func TestConditionRebasing(t *testing.T) {
    tests := []struct {
        name     string
        conds    []orm.Condition
        wantSQL  string
        wantArgs []any
    }{
        {
            name:     "single condition",
            conds:    []orm.Condition{orm.Cond("status = $1", "open")},
            wantSQL:  "status = $1",
            wantArgs: []any{"open"},
        },
        {
            name: "two conditions rebased",
            conds: []orm.Condition{
                orm.Cond("status = $1", "open"),
                orm.Cond("region = $1", "EU"),
            },
            wantSQL:  "status = $1 AND region = $2",
            wantArgs: []any{"open", "EU"},
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            sql, args := orm.JoinConditions(tt.conds)
            assert.Equal(t, tt.wantSQL, sql)
            assert.Equal(t, tt.wantArgs, args)
        })
    }
}
```

---

## Test Helpers

| Helper | Purpose |
|---|---|
| `testutil.OpenTestDB(t)` | Opens a real DB connection, registers cleanup |
| `testutil.CleanTable(t, db, table)` | Truncates table after test |
| `t.Helper()` | Mark assertion helpers; errors point to call site |
| `require.NoError(t, err)` | Stop test immediately on error |
| `assert.Equal(t, want, got)` | Soft assertion (test continues) |

---

## What Not To Test

- **SQL generation for standard CRUD**: covered by ORM's own tests.
- **Database connectivity**: covered by the pool's health-check tests.
- **Struct tag parsing**: covered by `MetadataCache` tests.

Focus your tests on **business invariants**: state transitions, validation rules, and multi-step operations that must be atomic.
