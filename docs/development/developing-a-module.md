# Developing a Module

This guide builds a new pure-Go module from scratch. We'll use `hr` (Human Resources) as the running example; the shipped `contact` module (`core/modules/contact/`) is the reference implementation of exactly this pattern.

---

## Prerequisites

- Go 1.26+, PostgreSQL running (see `compose.yml` — `make run-back` starts it)
- The EERP core repository checked out

No extra toolchain: Go modules compile directly into the core binary.

---

## Module anatomy

```
core/modules/hr/
├── module.json          # Metadata read by the module detector
├── module.go            # GoModule implementation — self-registration
├── model.go             # (optional) exported type alias for inheriting modules
├── internal/
│   └── hr.go            # Entity + service layer
└── views/
    └── HrViews.ts       # (optional) frontend view descriptors
```

The `internal/` package keeps your entity and service private; only the module registration and (optionally) an exported type alias live at the package root.

---

## Step 1 — `module.json`

The module detector scans every directory under the configured `module_root` for a `module.json`. It is required even for pure-Go modules — it drives discovery, activation and frontend static-file serving.

```json
{
    "active": true,
    "type": "go",
    "name": "hr",
    "display_name": "Human Resources",
    "version": "0.0.1",
    "author": "Your Name",
    "description": "Employee management",
    "static_files": {},
    "is_service": true,
    "auto_install": true
}
```

| Field | Type | Description |
|---|---|---|
| `active` | bool | Whether the module is enabled |
| `type` | string | `"go"` for pure-Go modules |
| `name` | string | Unique identifier across all module roots |
| `display_name` | string | Human-readable label (shown in the UI) |
| `static_files` | object | Frontend assets — e.g. `{"views": ["HrViews.ts"]}` (see Step 6) |
| `is_service` | bool | Whether the module exposes an API surface |
| `auto_install` | bool | Whether migrations apply automatically on load |

!!! note "No `wasm_path` for Go modules"
    The detector also resolves `.wasm` binaries for WASM modules. For a pure-Go module, omit it — no `.wasm` found simply means the WASM migration step is skipped.

---

## Step 2 — Define the entity

Entities are plain structs that embed `model.BaseModel`, which contributes `id` (UUID), `created_at`, `updated_at` and `deleted_at` (soft delete) — never declare those yourself.

**`internal/hr.go`:**

```go
package internal

import (
    "core/orm/model"

    "github.com/google/uuid"
)

// Employee is a person hired by the business.
// The table name is derived from the struct name: "employee".
type Employee struct {
    model.BaseModel
    Name        string    `db:"name"`
    Department  string    `db:"department"`
    SalaryCents int64     `db:"salary_cents"` // integer cents — never float
    Status      string    `db:"status"`       // "active" | "on_leave" | "terminated"
}
```

**Rules:**

- Embed `model.BaseModel`; use `db:"column_name"` tags on every business field.
- The table name defaults to the lowercased struct name — override with `orm.WithTableName("...")` at registration (Step 3).
- Store money as integer cents, not `float64`.

---

## Step 3 — Self-register with `module.go`

Every Go module implements the `GoModule` interface (`core/internal/module/go_module.go`) and enlists itself from `init()`:

```go
// core/internal/module/go_module.go
type GoModule interface {
    Name() string
    Register() error // orm.Register[T]() for new tables, orm.ExtendSchema() for others'
}
```

**`module.go`** — mirror of `core/modules/contact/module.go`:

```go
package hr

import (
    "core/internal/module"
    "core/modules/hr/internal"
    "core/orm"
)

func init() {
    module.RegisterGoModule(&hrModule{})
}

type hrModule struct{}

func (m *hrModule) Name() string { return "hr" }

func (m *hrModule) Register() error {
    return orm.Register[internal.Employee]()
}
```

That's the whole integration contract. `orm.Register[T]` builds an API descriptor from the struct: column list, table name, route prefix, soft-delete support.

### Registration options

`orm.Register[T]` accepts options to shape the generated API:

```go
orm.Register[internal.Employee](
    orm.WithTableName("employees"),                 // override derived table name
    orm.WithReadOnlyFields("tenant_id"),            // accepted from DB, rejected on write
    orm.WithExcludeFields("salary_cents"),          // removed from the API surface entirely
)

// Register with the ORM but expose NO HTTP routes (internal-only table):
orm.Register[internal.AuditLog](orm.WithExcluded())
```

!!! warning "Security-critical exclusions belong in code"
    `api.yaml` (`api_config_path` in the config) carries only cosmetic API-surface overrides. Fields that must never cross the wire are excluded in code via `WithExcludeFields` / `WithExcluded` — code-level options are fail-closed.

### Migrations are derived — no migration files

You do **not** write migrations. At startup, `module.LoadGoModules` snapshots the schema registry before and after your `Register()` call and applies the diff with idempotent DDL: new tables get `CREATE TABLE IF NOT EXISTS` (BaseModel columns included), new columns get `ADD COLUMN IF NOT EXISTS`, and declared indexes are ensured in a final pass. Details in [Server Integration](server-integration.md#startup-migration-flow).

If you need DDL the auto-migration can't derive (join tables with composite primary keys, custom constraints), implement the optional `Migrator` interface on the same struct — it runs after the auto-migration:

```go
func (m *hrModule) Migrate(ctx context.Context, db *orm.DB) error {
    _, err := db.Exec(ctx, `
        CREATE TABLE IF NOT EXISTS employee_teams (
            employee_id UUID NOT NULL REFERENCES employee(id),
            team_id     UUID NOT NULL,
            PRIMARY KEY (employee_id, team_id)
        )`)
    return err
}
```

---

## Step 4 — Business logic (service layer)

Generic CRUD (list, get, create, update, delete, restore) is served automatically — you only write a service for operations *beyond* that. The pattern, from `core/modules/contact/internal/contacts.go`:

```go
package internal

import (
    "context"

    "core/orm"

    "github.com/google/uuid"
)

type Service struct {
    employees *orm.Repository[Employee]
    db        *orm.DB
}

// New wires the service to the database.
// Call once at startup — panics if the Employee struct tags are invalid.
func New(db *orm.DB) *Service {
    return &Service{
        employees: orm.MustRepo[Employee](db),
        db:        db,
    }
}

// Repository CRUD — respects soft delete automatically:
func (s *Service) List(ctx context.Context) ([]Employee, error) {
    return s.employees.FindAll(ctx)
}

func (s *Service) ListByDepartment(ctx context.Context, dept string) ([]Employee, error) {
    return s.employees.FindAll(ctx, orm.Cond("department = $1", dept))
}

// Query() — the lower tier, for custom ordering / complex conditions:
func (s *Service) ListByStatusOrdered(ctx context.Context, status string) ([]Employee, error) {
    return s.employees.Query().
        Where(orm.Cond("status = $1", status)).
        Where(orm.Cond("deleted_at IS NULL")). // Query() has no implicit soft-delete filter
        OrderBy("name ASC").
        All(ctx, s.db)
}

// Transactions — for any read-modify-write:
func (s *Service) Terminate(ctx context.Context, id uuid.UUID) (Employee, error) {
    var updated Employee
    err := orm.Transact(ctx, s.db, func(tx *orm.Tx) error {
        txEmployees := s.employees.WithTx(tx)
        emp, err := txEmployees.FindByID(ctx, id)
        if err != nil {
            return err
        }
        emp.Status = "terminated"
        updated, err = txEmployees.Update(ctx, emp, id)
        return err
    })
    return updated, err
}
```

!!! warning "Two soft-delete tiers"
    `FindAll` / `FindByID` add `WHERE deleted_at IS NULL` implicitly. `Query()` does **not** — add the condition yourself. See [ORM](../core/orm.md) for the full API.

---

## Step 5 — Extending another module's entity (inheritance)

A module can add columns to an entity **owned by another module without modifying it**. `core/modules/crminheritdemo/` is the working demo — it extends the CRM entity:

```go
package crminheritdemo

import (
    "time"

    // Non-blank import: forces crm.init() before crminheritdemo.init() AND
    // gives us the exported crm.CRM type to embed.
    "core/modules/crm"

    "core/internal/module"
    "core/orm"
)

func init() {
    module.RegisterGoModule(&crminheritdemoModule{})
}

// CRM embeds the base entity and adds module-specific fields. Registered under
// the "crm" table name, it replaces the base registration so the generic API
// automatically includes the new columns — the crm module is never touched.
type CRM struct {
    crm.CRM
    Date    *time.Time `db:"date"`
    Comment string     `db:"comment"`
}

type crminheritdemoModule struct{}

func (m *crminheritdemoModule) Name() string { return "crminheritdemo" }

func (m *crminheritdemoModule) Register() error {
    return orm.Register[CRM](orm.WithTableName("crm"))
}
```

Two things make this work:

1. **The base module exports a type alias** (`core/modules/crm/model.go`) so inheritors can embed the entity without violating Go's `internal` package rules:

    ```go
    package crm

    import crminternal "core/modules/crm/internal"

    // CRM re-exports the base entity from internal so that inheriting
    // modules can embed it.
    type CRM = crminternal.CRM
    ```

2. **The auto-migration detects the new columns**: `LoadGoModules` compares column snapshots per table, so re-registering `crm` with extra fields yields `ADD COLUMN IF NOT EXISTS date, comment` — nothing else changes.

For schema-only extension without a Go struct (e.g. columns declared at runtime), use `orm.ExtendSchema(tableName, extraFields)` instead.

---

## Step 6 — Frontend views (optional)

If the entity should appear in the UI, add descriptor files under `views/` and declare them in `module.json`:

```json
"static_files": {
    "views": ["HrViews.ts"]
}
```

Views are **descriptors only** — the frontend engine derives the data loader, store and renderer from them; modules ship no components. From `core/modules/crm/views/CrmViews.ts`:

```ts
import type { FrontModule, ViewDescriptor } from '@eerp/core-front'

const fields: ViewDescriptor['fields'] = [
  { name: 'name',   label: 'Name',   type: 'text', required: true },
  { name: 'email',  label: 'Email',  type: 'text', required: true },
  { name: 'status', label: 'Status', type: 'text' },
]

const listView: ViewDescriptor = {
  entity: 'hr',              // maps to the Go /api/v1/hr routes (route prefix = table name)
  viewType: 'tree',          // flat data (no parent_id) -> rendered as a DataGrid
  fields,
  permissions: ['hr:hr:read'],
}

const hr: FrontModule = {
  name: 'hr',
  routes: [
    { path: '/hr/list', descriptor: listView, permission: 'hr:hr:read' },
    { path: '/hr/:id',  descriptor: { ...listView, viewType: 'form' }, permission: 'hr:hr:read' },
  ],
}

export default hr
```

See [View Engine](../frontend/view-engine.md) and [Module Discovery](../frontend/module-discovery.md) for how the front server discovers and serves these files.

---

## Step 7 — Tests

Keep a `module_test.go` next to `module.go` asserting the module registers cleanly (see `core/modules/contact/module_test.go`). Run backend tests with:

```bash
make run-back-tests                    # all packages
BACKTESTPATH=./modules/hr/... make run-back-tests
```

---

## Checklist

- [ ] `module.json` present, `name` unique, `active: true`
- [ ] Entity embeds `model.BaseModel` with `db` tags on every field
- [ ] `module.go`: `init()` calls `module.RegisterGoModule`, `Register()` calls `orm.Register[T]`
- [ ] Sensitive fields excluded via `WithExcludeFields` / `WithExcluded` (in code, not `api.yaml`)
- [ ] Extra DDL (join tables, constraints) in an optional `Migrate(ctx, db)` method
- [ ] Read-modify-write operations wrapped in `orm.Transact` + `WithTx`
- [ ] Exported type alias in `model.go` if other modules should be able to extend the entity
- [ ] Frontend views declared in `static_files.views` if the entity has a UI

**Next:** wire the module into the server — [Server Integration](server-integration.md).
