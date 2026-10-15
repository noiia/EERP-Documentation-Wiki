# Creating a Module (WASM/WASI Path)

!!! danger "This is a Go path, not Rust — and it's rarely the right one"
    Older revisions of this guide (and of the wider EERP docs) described this as a **Rust**
    toolchain compiling to `wasm32-unknown-unknown`. That subsystem never existed in the
    repository. The real mechanism: a module opting into `"type": "wasm"` is **Go source**,
    cross-compiled to WebAssembly System Interface (WASI) via `GOOS=wasip1 GOARCH=wasm go build`.
    See [ADR-002](../adrs/002-wasm-modules.md) for the corrected decision record.

    **Every module shipped in EERP today uses `"type": "go"` instead** (see [Creating a Go
    Module](creating-a-go-module.md) and, for the fastest start,
    [Building a Module From Scratch](module-from-scratch.md)). The WASM/WASI path documented here
    is fully implemented and exercised by the detector/loader/runtime code, but no production
    module currently uses it. Reach for it only when you specifically need a module's schema
    declaration sandboxed and loadable without rebuilding the core binary — not as the default way
    to start a new module.

This guide walks through the WASM/WASI path using `hr` (Human Resources) as a running example, for
when that isolation genuinely matters.

---

## Before You Start

The WASM component is a second build target of the **same Go source tree** — not a separate
language or toolchain. You need:

- Go 1.26+ (the only toolchain required — no Rust, no `wasm32-unknown-unknown` target)
- A directory inside one of the paths listed in `module_root` in `eerp-config.json`

---

## Step 1: Create the Module Directory

```bash
mkdir -p modules/hr
```

Or scaffold it directly with the module-generator tool (recommended even for the WASM/WASI path —
see [Building a Module From Scratch](module-from-scratch.md)):

```bash
go run ./tools/eerp-init-module -p core/modules/hr -t wasm
```

---

## Step 2: Write module.json

```json
{
    "active": true,
    "type": "wasm",
    "name": "hr",
    "display_name": "Human Resources",
    "version": "0.1.0",
    "author": "Your Name",
    "description": "Employee and contract management",
    "depends": [],
    "priority": 0,
    "static_files": {},
    "is_service": true,
    "auto_install": true
}
```

**Checklist:**

- [ ] `type` is `"wasm"` — this is the field that decides the module compiles to a WASI binary loaded at runtime, instead of straight into the core (see [Module System → The WASM binary is Go, not Rust](../core/module-system.md))
- [ ] `name` is unique across all modules in `module_root`
- [ ] `depends` lists the `name` values of any modules that must load before this one
- [ ] `active: true` to enable on startup

---

## Step 3: Declare the Database Schema

A `"type": "wasm"` module communicates its schema requirements via the migration protocol — a Go
file built only into the WASI binary, guarded by a build tag so it never lands in the native core
binary:

```go
// migrate_wasm.go
//go:build wasip1

package main

// The migration definition, returned as JSON in linear memory.
const migration = `{
    "entity": "employees",
    "version": 1,
    "operations": [
        { "type": "add_column", "table": "employees", "column": "department",   "sql_type": "VARCHAR(128)", "nullable": false },
        { "type": "add_column", "table": "employees", "column": "start_date",   "sql_type": "DATE",         "nullable": false },
        { "type": "add_column", "table": "employees", "column": "salary_cents", "sql_type": "BIGINT",       "nullable": false },
        { "type": "add_column", "table": "employees", "column": "status",       "sql_type": "VARCHAR(32)",  "nullable": false }
    ]
}`

//export migrate
func migrate() *byte {
    return &[]byte(migration)[0]
}

//export migrate_len
func migrateLen() uint32 {
    return uint32(len(migration))
}

func main() {} // required entrypoint for GOOS=wasip1, unused
```

!!! warning "Tables are not auto-created by this protocol"
    The WASM/JSON migration protocol currently only supports `add_column` and `create_index` (see
    [Module System → Supported Operations](../core/module-system.md#migration-protocol)). The base
    table must already exist. In practice, every module that needs a new table uses the `"type":
    "go"` path instead, where `orm.Register[T]` derives `CREATE TABLE IF NOT EXISTS` automatically
    — see [Creating a Go Module](creating-a-go-module.md#step-4-self-register-with-modulego).

---

## Step 4: Implement Business Logic

Business logic still runs as ordinary Go, compiled into the core binary — the WASM/WASI split only
affects schema declaration, never request handling. See [Creating a Go
Module](creating-a-go-module.md) for the full service-layer guide. The native-side files (built
without the `wasip1` tag) live alongside the WASM-only file from Step 3:

```
modules/hr/
├── module.json
├── migrate_wasm.go      # //go:build wasip1 — schema declaration only, built into build/hr.wasm
└── internal/
    ├── employee.go      # Entity definition (native build)
    └── service.go       # Business logic (native build, compiled into core)
```

**`internal/employee.go`:**

```go
package hr

import (
    "core/orm/model"
    "time"
)

type Employee struct {
    model.BaseModel
    Department  string    `db:"department"`
    StartDate   time.Time `db:"start_date"`
    SalaryCents int64     `db:"salary_cents"`
    Status      string    `db:"status"` // "active", "on_leave", "terminated"
}

func (Employee) TableName() string { return "employees" }
```

**`internal/service.go`** — identical in shape to the Go-module path; see [Creating a Go
Module](creating-a-go-module.md#step-5-implement-business-logic) for the full pattern
(repository, transactions, query builder).

---

## Step 5: Compile the WASM Binary

```bash
cd modules/hr
GOOS=wasip1 GOARCH=wasm go build -o build/hr.wasm .
```

Or use the top-level Makefile, which does this for every `"type": "wasm"` module:

```bash
make build
```

---

## Step 6: Register with the Core

At startup, the module loader scans `module_root` and auto-discovers `build/hr.wasm` next to
`module.json`. No explicit registration is needed for the schema side — the loader calls
`migrate()`/`migrate_len()` in the Wasmtime sandbox automatically.

The native business-logic side wires in exactly as it would for a `"type": "go"` module — see
[Server Integration](../development/server-integration.md).

---

## Step 7: Verify Module Loading

```bash
make run-back
```

Expected log output:

```
INFO  module detected  {"name": "hr", "version": "0.1.0", "priority": 0}
INFO  module migrated  {"name": "hr", "operations": 4}
INFO  module loaded    {"name": "hr"}
```

---

## Dependency Ordering

Dependency resolution works identically to the Go-only path — declare `depends` in `module.json`
and the detector assigns priority via topological sort. See [Creating a Go
Module](creating-a-go-module.md#dependency-ordering).

---

## Module Checklist

**WASM/WASI component (Go, cross-compiled):**

- [ ] `module.json` present with unique `name` and `"type": "wasm"`
- [ ] Schema-declaring file guarded by `//go:build wasip1`
- [ ] `migrate()` and `migrate_len()` exported
- [ ] Migration JSON is valid (operations reference correct table names)
- [ ] `.wasm` binary built into `build/<name>.wasm` (auto-discovered by core)

**Native business-logic component:**

- [ ] Go entity embeds `model.BaseModel`
- [ ] Go entity has `db` struct tags or snake_case field names
- [ ] `Service.New(db)` constructor wires repositories
- [ ] Module appears in startup logs without errors

See [Creating a Go Module](creating-a-go-module.md) for the standard, recommended path — omitting
the WASM/WASI split entirely.
