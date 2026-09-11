# Creating an Entity

An entity is a Go struct that maps to a database table. This guide covers everything from defining the struct to querying it with the full power of the ORM.

!!! note "This is the data-model half of a module"
    Defining an entity and calling `orm.Register[T]()` from a module's `Register()` method is what
    makes the table exist, migrate, and (unless excluded) get a full generic CRUD HTTP surface — see
    [Creating a Go Module → Step 4](creating-a-go-module.md#step-4-self-register-with-modulego) for
    how this struct plugs into a module's self-registration, and [Server
    Integration](../development/server-integration.md) for what happens at startup once it does.

---

## What Makes an Entity

An entity is any Go struct that:

1. Embeds `model.BaseModel` (provides `id`, `created_at`, `updated_at`, `deleted_at`)
2. Satisfies the `model.Entity` interface constraint (satisfied automatically by embedding `BaseModel`)
3. Has `db` struct tags on its fields

---

## Minimal Entity

```go
package inventory

import "eerp/core/orm/model"

type Item struct {
    model.BaseModel
    SKU   string `db:"sku"`
    Name  string `db:"name"`
    Stock int    `db:"stock_qty"`
}
```

With no `TableName()` method, the table is inferred as `item` (snake_case of `Item`). Add the method to override:

```go
func (Item) TableName() string { return "inventory_items" }
```

---

## Struct Tag Reference

```go
type Invoice struct {
    model.BaseModel
    Number     string     `db:"invoice_number,pk"`   // composite PK marker
    CustomerID uuid.UUID  `db:"customer_id"`
    TotalCents int64      `db:"total_cents"`
    PaidAt     *time.Time `db:"paid_at,omitempty"`   // skip on INSERT if nil
    Notes      string     `db:"-"`                   // never mapped to DB
    Status     string     `db:"status"`
}
```

| Tag option | Effect |
|---|---|
| `db:"col"` | Map to column `col` |
| `db:"col,pk"` | Treat as primary key |
| `db:"col,omitempty"` | Skip on INSERT/UPDATE when value is zero |
| `db:"col,softdelete"` | This column is the soft-delete timestamp |
| `db:"col,index"` / `db:"col,index=<method>"` | Secondary index, created idempotently at startup — see [ORM → Indexes](../core/orm.md#indexes) |
| `db:"-"` | Never include in any query |

!!! tip "Field-level visibility and gating"
    Struct tags control column mapping, not who gets to see a field over the API. To restrict a
    column to callers in specific groups (an Odoo-style security group, e.g. hiding `salary_cents`
    from everyone but `hr_manager`), pass `orm.WithFieldGroups(...)` at registration instead — see
    [ORM → API Exposure vs. Registration](../core/orm.md#api-exposure-vs-registration) and
    [ADR-014](../adrs/014-field-level-group-gating.md).

---

## Building the Repository

Create one repository per entity at startup. `MustRepo` panics if struct tags are misconfigured — this is intentional, as misconfiguration is a programming error.

```go
items := orm.MustRepo[Item](db)
```

Store the repository on your service struct:

```go
type Service struct {
    items *orm.Repository[Item]
    db    *orm.DB
}

func New(db *orm.DB) *Service {
    return &Service{
        items: orm.MustRepo[Item](db),
        db:    db,
    }
}
```

---

## CRUD Operations

### Create

```go
item := Item{
    SKU:   "WIDGET-001",
    Name:  "Blue Widget",
    Stock: 100,
}

created, err := items.Create(ctx, item)
// created.ID, created.CreatedAt are now populated
```

### Read

```go
// By primary key
item, err := items.FindByID(ctx, id)

// First match
cheapest, err := items.FindOne(ctx, orm.Cond("stock_qty > $1", 0),
    orm.OrderBy("price_cents ASC"))

// All rows (soft-deleted excluded automatically)
all, err := items.FindAll(ctx)

// With conditions
inStock, err := items.FindAll(ctx, orm.Cond("stock_qty > $1", 0))
```

### Update

```go
item.Name = "Red Widget"
updated, err := items.Update(ctx, item, item.ID)
// updated.UpdatedAt is refreshed
```

### Delete (soft)

```go
n, err := items.Delete(ctx, id)
// Sets deleted_at = NOW(). Row is hidden from all subsequent reads.
```

### Delete (hard)

```go
n, err := items.HardDelete(ctx, id)
// DELETE FROM inventory_items WHERE id = $1
```

### Restore

```go
err = items.Restore(ctx, id)
// Clears deleted_at. Row reappears in reads.
```

---

## Advanced Queries

When repository methods aren't expressive enough, use query builders.

### Filtering with multiple conditions

```go
results, err := orm.Select[Item](items.Meta()).
    Where(orm.Cond("stock_qty > $1", 0)).
    Where(orm.Cond("name ILIKE $1", "%widget%")).
    OrderBy("name ASC").
    Limit(20).
    All(ctx, db)
```

Multiple `Where()` calls are joined with `AND`. Placeholder numbers are rebased automatically — each `Cond` can use `$1` independently.

### Joining related tables

```go
type ItemWithSupplier struct {
    Item                           // embed Item fields
    SupplierName string `db:"supplier_name"`
}

rows, err := orm.Select[ItemWithSupplier](items.Meta()).
    Columns("i.*", "s.name AS supplier_name").
    Join("JOIN suppliers s ON s.id = i.supplier_id").
    Where(orm.Cond("i.stock_qty < $1", 10)).
    All(ctx, db)
```

### Aggregation

```go
// COUNT with condition
n, err := orm.Select[Item](items.Meta()).
    Where(orm.Cond("stock_qty = $1", 0)).
    Count(ctx, db)
```

### Batch insert

```go
newItems := []Item{
    {SKU: "A", Name: "Alpha", Stock: 10},
    {SKU: "B", Name: "Beta",  Stock: 20},
}
created, err := items.CreateBatch(ctx, newItems)
```

---

## Transactions Involving Entities

```go
err = orm.Transact(ctx, db, func(tx *orm.Tx) error {
    txItems := items.WithTx(tx)
    txMoves := stockMoves.WithTx(tx)

    item, err := txItems.FindByID(ctx, itemID)
    if err != nil { return err }

    item.Stock -= quantity
    if item.Stock < 0 {
        return ErrInsufficientStock
    }

    _, err = txItems.Update(ctx, item, item.ID)
    if err != nil { return err }

    _, err = txMoves.Create(ctx, StockMove{
        ItemID:   itemID,
        Quantity: -quantity,
        Reason:   "sale",
    })
    return err
})
```

---

## Soft Delete Behaviour

| Operation | Includes soft-deleted rows? |
|---|---|
| `FindByID` | No |
| `FindOne` | No |
| `FindAll` | No |
| `Count` | No |
| `Delete` | Sets `deleted_at`; row hidden from above |
| `Restore` | Clears `deleted_at`; row visible again |
| `HardDelete` | Removes row permanently |
| Raw SELECT builder | Only if you don't add `WHERE deleted_at IS NULL` |

To explicitly query soft-deleted rows (e.g., an admin recycle bin view):

```go
deleted, err := orm.Select[Item](items.Meta()).
    Where(orm.Cond("deleted_at IS NOT NULL")).
    All(ctx, db)
```

---

## Metadata Caching

The first call to `orm.MustRepo[Item]` triggers a one-time reflection pass over `Item`'s struct fields. The resulting `StructMeta` is cached in a `sync.Map`. All subsequent operations on `Repository[Item]` use the cached metadata with zero reflection.

This means:

- Startup is slightly slower per entity (acceptable)
- Request handling has no reflection cost (critical for performance)
- Misconfigured tags cause a panic at startup, not silently at runtime

---

## Checklist for a New Entity

- [ ] Struct embeds `model.BaseModel`
- [ ] All columns have `db` tags (or snake_case field names)
- [ ] `TableName()` defined if the default table name is wrong
- [ ] `omitempty` on nullable pointer fields that should be skipped on zero
- [ ] `orm.MustRepo[MyEntity](db)` called at service construction time
- [ ] Repository stored on the service struct (not recreated per request)
- [ ] Integration test with a real database (see [Testing](testing.md))
