# Database Layer

The database layer wraps [pgx v5](https://github.com/jackc/pgx) with connection pooling, structured query logging, and transaction management. It is the lowest level of the ORM stack that application code interacts with directly.

---

## Purpose

Go's `database/sql` is generic by design. pgx provides a PostgreSQL-native driver with better type support, but it still leaves connection lifecycle, logging, and transaction patterns to the application. This layer encodes EERP's conventions: pool configuration with sane defaults, structured per-query logging, and transaction helpers.

---

## Responsibilities

- Open and manage a `pgxpool` connection pool
- Validate and apply pool configuration defaults
- Wrap transactions in a uniform `Tx` abstraction with savepoint support
- Route all queries through a structured logger
- Expose an `Executor` interface so repositories are agnostic to DB vs. Tx

---

## The Executor Interface

`core/orm/pool/executor/executor.go`

Both `orm.DB` (pooled connection) and `orm.Tx` (active transaction) implement `Executor`. This is why `repository.WithTx(tx)` works: the repository holds an `Executor`, not a concrete type.

```go
type Executor interface {
    Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
    QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
    Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}
```

Code that takes an `Executor` works identically in both transactional and non-transactional contexts.

---

## Connection Pool

`core/orm/pool/db/db.go`

```go
db, err := orm.Open(orm.Config{
    DSN:               "postgres://user:pass@host:5432/dbname",
    MaxConns:          10,
    MinConns:          2,
    MaxConnIdleTime:   30 * time.Minute,
    MaxConnLifeTime:   time.Hour,
    HealthCheckPeriod: time.Minute,
    ConnectTimeout:    10 * time.Second,
    Debug:             false,
}, logger)
```

`orm.Open` calls `ApplyDefaults()` before `Validate()`, so you only need to specify values that differ from defaults.

### Configuration Reference

`core/orm/pool/config/config.go`

| Field | Default | Description |
|---|---|---|
| `DSN` | (required) | PostgreSQL connection string |
| `MaxConns` | 10 | Maximum pool size |
| `MinConns` | 2 | Minimum idle connections |
| `MaxConnIdleTime` | 30m | Close connections idle longer than this |
| `MaxConnLifeTime` | 1h | Recycle connections older than this |
| `HealthCheckPeriod` | 1m | How often to ping idle connections |
| `ConnectTimeout` | 10s | Per-connection establishment timeout |
| `Debug` | false | Log all queries (not just errors) |

### How DSN is Constructed

The DSN is assembled from the `eerp-config.json` fields at startup:

```
postgres://db_user:db_password@db_host:db_port/db_name
```

The `orm.Config` also receives the `max_connection`, `min_connection`, and timeout fields from the config file. See [Configuration](configuration.md) for the full mapping.

---

## Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Opening: orm.Open(cfg, logger)
    Opening --> Validating: ApplyDefaults + Validate
    Validating --> Connecting: pgxpool.NewWithConfig
    Connecting --> Ready: Pool established
    Ready --> Querying: Executor.Query / Exec
    Ready --> Transacting: orm.Transact(ctx, db, fn)
    Transacting --> Ready: COMMIT or ROLLBACK
    Ready --> Closing: db.Close()
    Closing --> [*]
```

---

## Transactions

`core/orm/pool/tx/tx.go`

### Basic transaction

```go
err = orm.Transact(ctx, db, func(tx *orm.Tx) error {
    // Any error triggers ROLLBACK; nil triggers COMMIT
    _, err := orders.WithTx(tx).Create(ctx, order)
    return err
})
```

### Savepoints

Savepoints allow partial rollback within a transaction. This is common in ERP operations where creating an order header should succeed even if creating the associated lines fails (to allow fallback logic).

```go
err = orm.Transact(ctx, db, func(tx *orm.Tx) error {
    // Create the order header
    header, err := orders.WithTx(tx).Create(ctx, order)
    if err != nil {
        return err
    }

    // Try to create lines; allow partial failure
    if err := tx.Savepoint(ctx, "lines"); err != nil {
        return err
    }

    if err := createLines(ctx, tx, header.ID, lineItems); err != nil {
        if rbErr := tx.RollbackTo(ctx, "lines"); rbErr != nil {
            return rbErr
        }
        // Fallback: create a single empty line
        return createEmptyLine(ctx, tx, header.ID)
    }

    return tx.Release(ctx, "lines")
})
```

| Method | SQL Issued |
|---|---|
| `tx.Savepoint(ctx, name)` | `SAVEPOINT name` |
| `tx.RollbackTo(ctx, name)` | `ROLLBACK TO SAVEPOINT name` |
| `tx.Release(ctx, name)` | `RELEASE SAVEPOINT name` |

---

## Query Logging

All SQL that passes through `orm.DB` or `orm.Tx` is recorded by the configured logger.

```go
type LogEntry struct {
    SQL      string
    Args     []any
    Duration time.Duration
    Err      error
}
```

When `Debug = false`: only queries that return an error are logged (at Error level).
When `Debug = true`: every query is logged (successful at Debug, failed at Error).

The `Err` field lets the logger distinguish slow-but-successful queries from failed ones.

---

## Scanning

`core/orm/internal/scan/scan.go`

Result scanning is name-based, not position-based. This means the column order in the SQL output doesn't matter; only the column names need to match `db` tags.

```mermaid
sequenceDiagram
    participant Builder
    participant pgx
    participant Scanner as scan.Rows[T]
    participant Cache as MetadataCache

    Builder->>pgx: Query(ctx, sql, args)
    pgx-->>Builder: Rows
    Builder->>Scanner: scan.All[T](rows, meta)
    Scanner->>pgx: FieldDescriptions() → []string column names
    Scanner->>Cache: meta.columnIndex[name] → field offset
    loop Per row
        Scanner->>pgx: Scan into []any dest
        Scanner->>Scanner: Copy dest values to struct via reflect.Value
    end
    Scanner-->>Builder: []T
```

Missing columns in the struct (returned by SQL but not mapped) are silently skipped. Missing fields in the query (mapped but not returned) get zero values.

---

## Interactions

```mermaid
graph LR
    Config["eerp-config.json"] -->|parsed into| ORMConfig["orm.Config"]
    ORMConfig --> DB["orm.DB"]
    DB -->|wraps| Pool["pgxpool.Pool"]
    DB -->|creates| Tx["orm.Tx"]
    DB & Tx -->|implement| Exec["Executor interface"]
    Repo["Repository[T]"] -->|holds| Exec
    Logger["orm.Logger"] -->|instrumented by| DB & Tx
```

---

## Extension Points

| Extension | How |
|---|---|
| Custom pool config | Pass custom `orm.Config` to `orm.Open` |
| Custom query logging | Implement `orm/log.Logger` |
| Multi-database support | Construct multiple `orm.DB` instances with different DSNs |
| Read replicas | Future: `ReadDB` / `WriteDB` split in the executor interface |
