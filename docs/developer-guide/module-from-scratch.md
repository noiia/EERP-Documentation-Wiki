# Building a Module From Scratch

This is the fast-start path: scaffold a complete module — backend entity, self-registration,
frontend views, and tests — with one command, then customize it into something real. It uses
`tools/eerp-init-module`, the same generator a new module should always start from.

For the concepts behind each generated piece, see [Creating a Go
Module](creating-a-go-module.md), [Creating an Entity](creating-an-entity.md), and [Creating a
Frontend Module](creating-a-frontend-module.md) — this page is the practical, ordered walkthrough;
those are the deeper reference for each step.

We'll build `expense` (a simple expense-tracking module) end to end.

---

## 1. Scaffold it

```bash
go run ./tools/eerp-init-module -p core/modules/expense -t go
```

| Flag | Meaning |
|---|---|
| `-p` | Path — the trailing directory name becomes the module/table/npm-package name. Must match `^[a-z][a-z0-9]*$`. |
| `-t` | Type — `go` (compiles into the core binary; **the standard choice**) or `wasm` (cross-compiled to WASI; see [Creating a Module (WASM/WASI Path)](creating-a-module.md) for when that's actually warranted). |

This generates:

```
core/modules/expense/
├── module.json
├── module.go
├── module_test.go
├── package.json
├── tsconfig.json
├── vitest.config.ts
├── views/
│   ├── ExpenseViews.ts
│   └── ExpenseViews.test.ts
└── i18n/
    └── expense.pot
```

And, because the target sits directly under `core/modules/` and the tool found the repo-root
`eerp-config.json` by walking up from there, two wiring steps happen **automatically**:

1. `_ "core/modules/expense"` is inserted alphabetically into `core/modules/all/all.go`'s import
   block — see [Server Integration → the one line](../development/server-integration.md#step-1-the-one-line-blank-import-in-modulesall).
2. `pnpm install` runs inside `core-front/` to link the new workspace package (the frontend
   discovers module packages via a glob over `../core/modules/*`).

!!! note "Outside core/modules?"
    Both wiring steps are skipped with a printed message telling you to do them by hand — the tool
    only auto-wires when the target is a direct child of `core/modules/`.

## 2. Read what you got

**`module.json`** — `type: "go"`, `is_service: false`, `auto_install: false` (flip both once the
module does something real), `static_files.views: ["ExpenseViews.ts"]`.

**`module.go`** — a starter entity and self-registration, ready to run as-is:

```go
func init() {
    module.RegisterGoModule(&expenseModule{})
}

type Expense struct {
    model.BaseModel
    TenantID uuid.UUID `db:"tenant_id"`
    Name     string    `db:"name"`
}

func (m *expenseModule) Register() error {
    return orm.Register[Expense]()
}
```

**`module_test.go`** — asserts the entity carries `tenant_id` (a tenant-isolation guard test —
every tenant-owned table needs this column for the ORM's automatic scoping to apply; see [ORM →
Tenant Isolation](../core/orm.md#tenant-isolation)).

**`views/ExpenseViews.ts`** — three `ViewDescriptor`s (dashboard/tree/form) and a `FrontModule`
with routes `/expense`, `/expense/list`, `/expense/:id`, permission strings following
`<entity>:<entity>:<action>`.

## 3. Run it as-is

```bash
make run-back
```

Look for the route log confirming the generic CRUD surface mounted:

```
INFO   route  {"method": "GET",    "path": "/api/v1/expense"}
INFO   route  {"method": "POST",   "path": "/api/v1/expense"}
INFO   route  {"method": "PUT",    "path": "/api/v1/expense/:id"}
INFO   route  {"method": "DELETE", "path": "/api/v1/expense/:id"}
```

Nothing beyond the blank import in `all.go` was needed — this is the payoff of the self-registering
`GoModule` pattern (see [Server Integration](../development/server-integration.md)).

## 4. Extend the entity

Add the fields expense tracking actually needs:

```go
type Expense struct {
    model.BaseModel
    TenantID    uuid.UUID  `db:"tenant_id"`
    Name        string     `db:"name"`
    AmountCents int64      `db:"amount_cents"` // integer cents, never float
    Category    string     `db:"category"`
    PaidAt      *time.Time `db:"paid_at,omitempty"`
    ReceiptSeen bool       `db:"receipt_seen"` // boolean/file widget backing this
}
```

Restart the backend — `module.LoadGoModules` diffs the schema and issues `ADD COLUMN IF NOT
EXISTS` for the new columns automatically. No migration file to write. See [Creating an
Entity](creating-an-entity.md) for the full struct-tag reference (indexes, group gating,
`omitempty`).

## 5. Add business logic beyond generic CRUD

Only needed once you have an invariant generic CRUD can't express:

```go
// internal/service.go
type Service struct {
    expenses *orm.Repository[Expense]
    db       *orm.DB
}

func New(db *orm.DB) *Service { return &Service{expenses: orm.MustRepo[Expense](db), db: db} }

func (s *Service) TotalByCategory(ctx context.Context, category string) (int64, error) {
    var total int64
    rows, err := s.expenses.FindAll(ctx, orm.Cond("category = $1", category))
    if err != nil {
        return 0, err
    }
    for _, r := range rows {
        total += r.AmountCents
    }
    return total, nil
}
```

Mount any extra route needed for it (see [Creating a Go Module → Step
7](creating-a-go-module.md#step-7-register-with-the-core)); everything else — list, get, create,
update, delete, restore — is already live.

## 6. Fill in the frontend views

The generator does **not** scaffold frontend business fields — only the three-descriptor skeleton
above. Edit `views/ExpenseViews.ts` to match your real fields, following the [one-file-per-DB-model
convention](../adrs/019-per-model-view-files.md) if the module grows past one entity:

```ts
const fields: ViewDescriptor['fields'] = [
  { name: 'name', label: 'Name', type: 'text', required: true },
  { name: 'amount_cents', label: 'Amount', type: 'number', widget: 'monetary' },
  { name: 'category', label: 'Category', type: 'selection', selection: { options: ['travel', 'meals', 'supplies'] } },
  { name: 'paid_at', label: 'Paid', type: 'date' },
  { name: 'receipt_seen', label: 'Receipt', type: 'boolean', widget: 'file' },
]
```

See [Views & Components](../frontend/views-and-components/index.md) for a page per field widget
and view type, and [Creating a Frontend Module](creating-a-frontend-module.md) for the full
descriptor contract.

## 7. Run and click around

```bash
make run-front      # regenerates the module manifest on start
```

The catch-all route resolves `/expense`, runs the permission guard, server-fetches, and renders —
with zero custom React code.

## 8. Test

The generated `module_test.go` and `ExpenseViews.test.ts` are starting points, not full coverage —
extend them as you add fields and business logic. See [Testing](testing.md) for backend patterns
(table-driven tests, transaction-scoped integration tests) and [View Engine →
Testing](../frontend/view-engine.md#testing) for the frontend unit/integration split.

```bash
make run-back-tests BACKTESTPATH=./modules/expense/...
```

## Checklist

- [ ] Scaffolded with `eerp-init-module`, not hand-copied from another module
- [ ] Entity fields use correct types (integer cents for money, pointers for nullable columns)
- [ ] `is_service`/`auto_install` flipped to `true` once the module does something real
- [ ] Sensitive fields excluded/gated via `WithExcludeFields`/`WithFieldGroups` in code
- [ ] Frontend descriptor fields match the real entity, using the right widgets (see [Views & Components](../frontend/views-and-components/index.md))
- [ ] `module_test.go` extended for any custom business logic
- [ ] Module appears in the startup route log and its frontend route renders

## Related

- [Creating a Go Module](creating-a-go-module.md) · [Creating an Entity](creating-an-entity.md) · [Creating a Frontend Module](creating-a-frontend-module.md)
- [Server Integration](../development/server-integration.md) — what happens at startup, in detail
- [Views & Components](../frontend/views-and-components/index.md)
- [Deployment → Docker Compose](deployment.md#docker-compose-recommended)
