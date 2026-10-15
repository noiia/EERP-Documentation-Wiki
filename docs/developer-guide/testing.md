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

```bash
make test                                             # everything the CI runs, stops at the first failure
make run-back-tests                                   # all Go tests (starts db + garage, sets CONFIG)
make run-back-tests BACKTESTPATH=./orm/...            # one package tree
make run-back-tests ARGS="-v -run TestFindOne -timeout 10m"
make run-deadcode                                     # the dead code gate alone
make run-front-tests                                  # frontend lint + typecheck + tests
```

`make test` runs, in order: the Go backend tests with Redis (`REDIS_URL` set, so the cache tests
run too), the **dead code gate**, `pdf-service`'s tests, then the frontend's lint, typecheck and
tests — the same checks as CI.

!!! warning "The dead code gate"
    CI fails on any Go function unreachable from `main` that isn't listed in
    `.github/deadcode-allowlist.txt`. A helper used only by tests belongs in a `_test.go` file —
    `export_test.go` to expose it to the package's external tests — not in production code.

Always pass a `-timeout`: a killed `go test` can leave a Postgres session holding the schema
advisory lock, and later migrations then wait forever (see
[Getting Started → Troubleshooting](../getting-started.md#troubleshooting)).

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

Database-backed tests use `core/internal/testdb`, one way for every package:

```go
package inventory // an in-package test: it can use the module's own types

import (
    "context"
    "testing"

    "core/internal/testdb"
    "core/orm"
    "core/orm/model"

    "github.com/google/uuid"
)

func TestItemCreate(t *testing.T) {
    app := testdb.Open(t)                       // (1) skipped when no database is configured
    testdb.MigrateModules(t, app, "inventory")  // (2) the module's real schema

    tenant := uuid.New()                        // (3) a fresh tenant: no collision with dev data
    ctx := context.Background()
    repo := orm.MustRepo[Item](app.DB)

    created, err := repo.Create(ctx, Item{BaseModel: model.BaseModel{TenantID: tenant}, Name: "Widget"})
    if err != nil {
        t.Fatal(err)
    }
    t.Cleanup(func() { _, _ = repo.HardDelete(context.Background(), created.ID) }) // (4)
    // … assertions …
}
```

1. `testdb.Open(t)` connects to `TEST_DSN` (CI), else the database named in the config file
   `CONFIG` points at (what `make run-back-tests` sets). With neither, the test is **skipped**, so
   a plain `go test ./...` stays database-free. The connection closes when the test ends.
2. On a fresh database, create the tables first: `testdb.MigrateModules(t, app, "auth", …)` for
   modules' real schemas (blank-import each module's package so it registers), or
   `testdb.Migrate(t, app, tables...)` for individually registered tables.
3. Tests may run against the **live dev database**. Seed under a fresh `uuid.New()` tenant…
4. …and clean up **only the rows you created**.

!!! danger "Never `DELETE FROM <table>`"
    A blanket delete or `TRUNCATE` in a test wipes the developer's dev data. Scope every cleanup to
    the ids or the tenant the test created.

The full app wiring is tested the same way: `internal/app/app_test.go` boots `app.Build` against
the test database and drives real routes as the seeded dev admin.

---

## Integration Tests: Transactions for Isolation

The cleanest way to isolate integration tests is to wrap each test in a transaction and roll it back:

```go
func TestContactSoftDelete(t *testing.T) {
    ctx := context.Background()
    db := testdb.Open(t).DB

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
    db := testdb.Open(t).DB
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
| `testdb.Open(t)` | The test database (`TEST_DSN`, else `CONFIG`, else skip), closed at test end |
| `testdb.MigrateModules(t, app, names...)` / `testdb.Migrate(t, app, tables...)` | Create the schema a test needs on a fresh database |
| `testdb.Config(t)` | The resolved app config, with `TEST_DSN`'s coordinates when set |
| `t.Helper()` | Mark assertion helpers; errors point to call site |
| `require.NoError(t, err)` | Stop test immediately on error |
| `assert.Equal(t, want, got)` | Soft assertion (test continues) |

---

## What Not To Test

- **SQL generation for standard CRUD**: covered by ORM's own tests.
- **Database connectivity**: covered by the pool's health-check tests.
- **Struct tag parsing**: covered by `MetadataCache` tests.

Focus your tests on **business invariants**: state transitions, validation rules, and multi-step operations that must be atomic.
