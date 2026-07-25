# Module System

The module system is the core extension mechanism of EERP. It allows independent business domains (CRM, Inventory, Accounting) to be developed and wired into the runtime without modifying the core.

---

## Purpose

In a traditional monolithic ERP, adding a new feature means modifying the core. EERP inverts this: the core is a stable runtime; business features are pluggable modules.

EERP uses a **hybrid module model** with two distinct components per module:

| Component | Runs when | Responsibility |
|---|---|---|
| WASM binary (Rust) | Startup only | Schema declaration via `migrate()` ABI |
| Go service (monolith) | Every request | Business logic, ORM queries, HTTP handlers |

The WASM boundary is crossed once per module per startup — not on each request. This gives sandboxed schema ownership without any per-request serialization cost.

> **Current state**: every shipped module is a pure Go service — the Wasmtime loader is live, but `.wasm` binaries are still the next step for full schema decoupling. `core/modules/` currently ships `crm` and `contact` (business entities), `appstore` (the module-management UI, see [Live Activation](#live-activation-no-restart)), `crminheritdemo` (a worked example of [extending another module's table](orm.md#extending-another-modules-table)), and three infrastructure-only modules with no `module.json` of their own — `auth`, `settings`, and `pictures`/`notebook` (record-anchored services, see [Object Storage](object-storage.md)) — all registered with the ORM but excluded from generic CRUD.

!!! note "How a Go module gets wired in"
    `core/modules/all` is a small `//go:build !wasip1` package that blank-imports every other Go module so each one's `init()` fires and self-registers via `module.RegisterGoModule`. It is the one file that changes when a new Go-only module is added to the tree — everything else (discovery, dependency ordering, HTTP wiring) proceeds from that registration exactly as it does for a WASM module.

---

## Responsibilities

- Discover modules by scanning the filesystem (`module_root` in config)
- Validate module metadata (`module.json`) and resolve the dependency graph
- Load and instantiate WASM binaries in a sandboxed Wasmtime environment
- Call `migrate()` / `migrate_len()`, read linear memory, apply DDL
- Define the ABI contract between modules and the core
- Wire Go services into the application at startup

---

## Module Anatomy

A full hybrid module contains:

```
modules/crm/
├── module.json           # Module metadata and dependency declaration
├── crm.wasm              # Compiled Rust binary (WASM schema protocol)
├── src/                  # Rust source (not read by core)
│   └── lib.rs            # migrate() + migrate_len() exports
└── internal/             # Go source (compiled into core binary)
    ├── crm.go            # Contact entity + Service (business logic)
    └── handlers.go       # HTTP handlers (future)
```

A Go-only module (current approach) omits the `src/` and `.wasm` parts:

```
modules/crm/
├── module.json
└── internal/
    └── crm.go
```

### module.json

```json
{
    "active": true,
    "name": "crm",
    "display_name": "CRM",
    "version": "0.0.1",
    "author": "Edwin Lecomte",
    "description": "CRM core module",
    "depends": [],
    "priority": 0,
    "static_files": {},
    "is_service": true,
    "auto_install": true
}
```

| Field | Type | Description |
|---|---|---|
| `active` | bool | Whether the module should be loaded |
| `name` | string | Unique identifier (used in dependency resolution) |
| `display_name` | string | Human-readable name |
| `version` | semver | Module version |
| `depends` | []string | Names of modules that must be loaded first |
| `priority` | int | Manual priority hint (rarely needed; dependency resolver assigns priorities) |
| `is_service` | bool | Whether the module registers HTTP handlers |
| `auto_install` | bool | Whether to apply migrations automatically on load |
| `app_mode` | bool | Whether the module gets a navigable tile in the frontend landing menu (see below) |

`app_mode` is deliberately **not** a field on the Go `types.Module` struct — the App Store's management API round-trips `module.json` as a raw map precisely so keys like this one (display-only, frontend-consumed) survive untouched without every one needing a matching Go field. The frontend's build-time discovery reads `app_mode === true` straight off each module's JSON to decide whether it appears as an app tile; a module without one (or without a `module.json` at all — the infrastructure-only modules above) is simply never offered as an app to open. See [ADR-009: Module Lifecycle via API](../adrs/009-module-lifecycle-api.md#4-app_mode-stopped-being-writable) for why it's readable but not writable through that API.

---

## Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Discovered: Filesystem scan finds module.json
    Discovered --> Validated: Metadata parsed and validated
    Validated --> Ordered: Dependency graph resolved, priority assigned
    Ordered --> WASMInstantiated: .wasm binary loaded into Wasmtime
    WASMInstantiated --> Migrated: migrate() called, schema changes applied to PG
    Migrated --> GoWired: Go service instantiated (crm.New(db))
    GoWired --> Active: Module ready to serve requests
    Active --> [*]: Shutdown

    note right of WASMInstantiated: Skipped if no .wasm found
    note right of GoWired: Current active path for all modules
```

---

## Detection Flow

`core/internal/module/detector.go`

```mermaid
flowchart TD
    A[Read module_root from config] --> B[Walk directories for module.json files]
    B --> C[Parse each module.json into Module struct]
    C --> D{All dependencies present?}
    D -- No --> E[Log missing deps, skip affected modules]
    D -- Yes --> F[Topological sort by depends array]
    F --> G[Assign numeric priority to each module]
    G --> H[Snapshot: detect changed modules]
    H --> I[Auto-discover .wasm binary if wasm_path unset]
    I --> J[Return ordered Module list]
```

### Snapshot-based Change Detection

The detector maintains a cache of the previous scan in `./cache/modules`. On each startup, it compares the current filesystem state with the cached state:

- **New module**: load and migrate
- **Changed module** (different hash): reload
- **Unchanged module**: skip migration (idempotent operations still safe)
- **Removed module**: mark inactive

### Priority Assignment

Modules in the same dependency tier get the same priority number. The algorithm:

1. Assign priority 0 to all modules with no dependencies.
2. For each remaining module, assign `max(dependencies' priorities) + 1`.
3. Repeat until all modules have a priority.

Modules at priority _N_ load concurrently; priority _N+1_ waits for all of _N_ to complete.

---

## Loading Flow

`core/internal/module/load.go`

```mermaid
sequenceDiagram
    participant Loader
    participant Wasmtime
    participant Module as WASM Module
    participant DB as PostgreSQL

    Loader->>Loader: Group modules by priority
    loop Priority level (sequential)
        par Each module in group (concurrent)
            Loader->>Wasmtime: Instantiate(wasm_bytes, linker)
            Wasmtime-->>Loader: Instance
            Loader->>Module: Call migrate_len()
            Module-->>Loader: byte length
            Loader->>Module: Call migrate()
            Module-->>Loader: memory pointer
            Loader->>Loader: Read memory[ptr : ptr+len]
            Loader->>Loader: JSON.Unmarshal → Migration struct
            loop Per operation
                Loader->>DB: ALTER TABLE (add_column etc.)
            end
        end
    end
```

---

## Migration Protocol

Modules communicate schema requirements through a simple memory-based protocol. This avoids a direct Go/Rust dependency; the only shared contract is the JSON shape.

### Module side (Rust)

```rust
// The migration definition, returned as JSON in linear memory
static MIGRATION: &str = r#"{
    "entity": "contacts",
    "version": 1,
    "operations": [
        {
            "type": "add_column",
            "table": "contacts",
            "column": "crm_segment",
            "sql_type": "VARCHAR(64)",
            "nullable": true
        }
    ]
}"#;

#[no_mangle]
pub extern "C" fn migrate() -> *const u8 {
    MIGRATION.as_ptr()
}

#[no_mangle]
pub extern "C" fn migrate_len() -> usize {
    MIGRATION.len()
}
```

### Core side (Go)

```go
// core/internal/types/modules.go
type Migration struct {
    Entity     string      `json:"entity"`
    Version    int         `json:"version"`
    Operations []Operation `json:"operations"`
}

type Operation struct {
    Type     string `json:"type"`     // currently: "add_column"
    Table    string `json:"table"`
    Column   string `json:"column"`
    SQLType  string `json:"sql_type"`
    Nullable bool   `json:"nullable"`
}
```

The core reads the WASM linear memory region indicated by the pointer and length, deserializes the JSON, and applies each operation using parameterized DDL statements.

### Supported Operations

| Operation | DDL Generated |
|---|---|
| `add_column` | `ALTER TABLE t ADD COLUMN IF NOT EXISTS col TYPE` |

Future operations planned: `drop_column`, `add_index`, `create_table`, `rename_column`.

---

## Dependency Resolution

`core/internal/common/filemeta.go`

```mermaid
graph LR
    subgraph "Priority 0"
        Core
    end
    subgraph "Priority 1"
        CRM
        Accounting
        HR
    end
    subgraph "Priority 2"
        Invoicing
        Payroll
    end

    CRM --> Core
    Accounting --> Core
    HR --> Core
    Invoicing --> CRM
    Invoicing --> Accounting
    Payroll --> HR
    Payroll --> Accounting
```

The resolver also validates that all declared dependencies are present:

```go
ok, missing := fmMap.CheckDependencies()
// missing = map[depName][]modulesThatNeedIt
```

Missing dependencies cause the dependent module to be skipped, not the entire system.

---

## Interactions

```mermaid
graph LR
    main["main.go"] -->|calls| loader["module/load.go"]
    loader -->|calls| detector["module/detector.go"]
    detector -->|reads| fs["Filesystem (module.json, .wasm)"]
    detector -->|uses| resolver["common/filemeta.go (dep resolution)"]
    loader -->|uses| wasmtime["Wasmtime engine"]
    loader -->|executes DDL via| db["orm.DB"]
    loader -->|reads| snapshot["cache/modules (change detection)"]
    main -->|wires| gosvcs["Go services (e.g. crm.New(db))"]
    gosvcs -->|queries via| db
```

---

## Extension Points

| Extension | Mechanism |
|---|---|
| New operation type | Add case to `Operation.Type` handler in `load.go` |
| New WASM export | Export function from Rust, call from `load.go` |
| Hot reload | **Shipped** — see [Live Activation](#live-activation-no-restart) below |
| Module isolation | Per-module Wasmtime `Store` (shipped, see below); resource limits remain future work |
| Module API | Future: Go functions linked into WASM linker, called from Rust via imports |

---

## Live Activation (no restart)

`active: false` in `module.json` no longer means "skip loading" — it means "load, but gate access." `Registry.Boot` (`core/internal/module/runtime.go`) loads **every** discovered module at startup regardless of `active`, and tracks each one's flag in an in-memory map. `ActiveGateMiddleware` checks that map on every generic-CRUD request and returns `403 MODULE_INACTIVE` for a deactivated module's table; the route itself stays mounted for the process's life, since the router has no safe way to add or remove a route while serving traffic.

```mermaid
sequenceDiagram
    participant Admin as App Store UI
    participant API as PUT /api/v1/modules/:id
    participant Reg as Registry (in-memory)
    participant FS as module.json
    participant MW as ActiveGateMiddleware

    Admin->>API: { active: false }
    API->>Reg: SetActive(name, false)
    Reg->>FS: persist (atomic write, after the gate flips)
    Note over Reg,MW: Next request onward
    MW->>Reg: IsTableActive(table)?
    Reg-->>MW: false
    MW-->>Admin: 403 MODULE_INACTIVE
```

Consequences worth knowing when working in this area:

- A deactivated module's table still exists and is still migrated at boot — "deactivated" means inaccessible via the generic CRUD surface, not unloaded. Data written before deactivation reappears the moment the module is reactivated.
- Table ownership (which module's flag gates which table) is **attributed, not declared**: the first module whose migration creates a table is recorded as its owner. A module that only adds columns to another module's table (`ExtendSchema`/`orm.WithTableName` inheritance) never claims ownership of it — deactivating it has no effect on the table it extends.
- `POST /api/v1/modules/:id/reload` re-reads a WASM module's `.wasm` file from disk into a fresh Wasmtime `Store` and re-runs its migration — a real hot-swap. For a Go module (statically compiled into the backend binary) there is nothing to hot-swap; `Reload` re-validates schema registration as a no-op and says so in the log, rather than pretending a reload occurred.
- This only reaches modules already known at the **last build** — a module folder that didn't exist at that build has no mounted route at all yet, on either side. Truly unseen-code hot-install remains deferred, larger infrastructure.

The management API this backs (`PUT /api/v1/modules/:id`, the App Store UI) and the reasoning behind each constraint are recorded in [ADR-009: Module Lifecycle via API](../adrs/009-module-lifecycle-api.md) and [ADR-010: Live Module Lifecycle](../adrs/010-live-module-lifecycle.md).

---

## Security Considerations

WASM modules run inside a Wasmtime sandbox. They cannot:

- Access the host filesystem directly
- Open network connections
- Crash the Go process on panic

They can only communicate with the core through the defined ABI (exported functions + linear memory) and through imported host functions that the core explicitly exposes via the Wasmtime linker.

---

## Related

- [Module Discovery (frontend)](../frontend/module-discovery.md) — the build-time mirror of this loader on the Next.js side.
- [ADR-009: Module Lifecycle via API](../adrs/009-module-lifecycle-api.md) · [ADR-010: Live Module Lifecycle](../adrs/010-live-module-lifecycle.md) — the App Store management API and the live activate/deactivate/reload design.
