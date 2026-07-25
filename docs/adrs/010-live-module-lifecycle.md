# ADR-010: Live Module Lifecycle — Activate/Deactivate/Reload with No Restart

**Status**: Accepted
**Date**: 2026-07-11
**Supersedes**: [ADR-009](009-module-lifecycle-api.md) Decision 1 ("File-write + restart, not hot reload")

## Context

[ADR-009](009-module-lifecycle-api.md) shipped the App Store's management API as a pure `module.json` file editor: `PUT /api/v1/modules/:id` wrote `active` to disk and returned `requires_restart: true`, deliberately deferring anything that made the change *live* to a larger, future runtime module registry project.

That framing turned out to overstate the work. The larger story — hot-*installing* a module the running processes have never seen before: fetching a versioned bundle/binary at runtime, mounting brand-new routes with no prior registration — genuinely is a separate, larger project (a registry/bucket, bundle externalization, dynamic routing) and stays deferred.

But "flip an *already-known* module on or off, or swap in an updated binary, without restarting" is a much smaller problem once two constraints are taken as given rather than fought:

1. Echo's router has no safe way to add or remove a route while serving traffic, and re-registering a route on every activate/deactivate would still leave the old one racing the new one. So routes, once mounted, stay mounted for the process's life.
2. The frontend's module discovery is build-time by design (see [Module Discovery](../frontend/module-discovery.md)) — a route/tile literally does not exist in the compiled bundle unless discovery saw it at build time.

Given those, "live" doesn't require touching either of those systems' shape — it requires loading everything discovery already knows about (which constraint 2 already requires anyway) and gating *access*, not *existence*, from a value that can change after boot.

## Decisions

### 1. Preload everything at boot; `active` becomes a request-time gate, not a load-time filter

`internal/module/runtime.go`'s `Registry.Boot` replaces the old module-loading entry point: it loads **every** discovered module — WASM and Go, `active: true` or `false` — and records each one's active flag in an in-memory map. `Registry.IsTableActive`/`ActiveGateMiddleware` then gate each generic-CRUD request against that live map, 403ing (`MODULE_INACTIVE`) a request to a deactivated module's table.

`Registry.SetActive` flips the in-memory flag first, then persists to `module.json` via the same atomic write `Manager.Patch` always used — file state changes **at the end** of the operation, once the live gate has already moved. A toggle is visible to the very next request.

This is why nothing about the router's shape had to change: every table's route is mounted once, unconditionally, at boot, and `ActiveGateMiddleware` — one extra middleware on the existing route-registration call — decides per-request whether that route is reachable right now.

The cost: a module that is `active: false` still gets its WASM instantiated / its `Register()` called / its migration run at boot. Its table exists, just inaccessible via the generic CRUD surface while gated off. This is a real, deliberate trade — the alternative (skip loading, load lazily on first activate) reintroduces exactly the "add a route while serving traffic" problem the router can't do safely.

### 2. Table ownership is attributed, not declared

Neither the WASM migration protocol (see [Module System → Migration Protocol](../core/module-system.md#migration-protocol)) nor a Go module's `Register()` call previously recorded *which module* a table belongs to — the ORM's schema registry only ever knew about tables, not their owners. `ActiveGateMiddleware` needs that mapping to know which module's active flag gates which route.

Rather than inventing a new declaration module authors have to remember, `Registry` derives ownership from what already happens:

- **WASM path:** the loader already parses a migration's operations, each naming a table — the first module to create a table (i.e. touch it in a migration at all, since only one module's migration ever runs `CREATE TABLE` for a given name) is recorded as its owner.
- **Go path:** Go module loading already diffs the schema snapshot before/after `Register()` to find new tables *and* new columns (this is how `ExtendSchema`-based inheritance, e.g. `crminheritdemo` adding columns to `crm`, was already detected). Ownership is attributed only on the **new-table** branch of that diff — a module that merely adds columns to another module's table never claims ownership of it.

This keeps gating at the granularity `ActiveGateMiddleware` can actually enforce (a whole table's routes), and means `crminheritdemo` deactivating itself has no visible effect on `crm`'s routes — it owns nothing of its own, by design.

### 3. One WASM `Store` per module, not one shared `Store`

The pre-ADR-010 code created a single Wasmtime `Store` and instantiated every WASM module into it. That was fine when nothing was ever unloaded, but `Registry.Reload` needs to replace a module's instance without disturbing every other module sharing the same `Store` — and wasmtime-go exposes no per-instance free, only whole-`Store` teardown. So each module now gets its own `Store` (all still sharing the one `Engine`, which is designed to be shared); `Reload` builds a fresh `Store`, re-instantiates into it, and drops the old reference for GC.

### 4. `Reload` is real for WASM, a re-validation no-op for Go

`POST /api/v1/modules/:id/reload` is the "upgrade directly on run" affordance: for a WASM-type module it re-reads the `.wasm` file from disk into a fresh `Store` and re-runs its migration — genuinely picking up a binary that was replaced on disk without a backend restart. For a Go-type module there is nothing to hot-swap: its code is statically compiled into the same backend binary serving the request. `Registry.Reload` still runs (re-validating schema registration, harmless and idempotent) and logs exactly this constraint rather than pretending a reload occurred; the frontend's Reload button hides itself entirely for `type: "go"` modules rather than offering an affordance that can't do what its label says.

### 5. Frontend discovery compiles every module regardless of `active`; gating moves to request time there too

Mirroring Decision 1 on the frontend: [module discovery](../frontend/module-discovery.md) no longer skips `active: false` when building the generated module manifest — every module's views/tiles compile in. The landing menu and the catch-all route filter/block by the same live, Go-sourced active state the App Store's own catalog renders from.

The boundary this doesn't remove: a module folder that didn't exist under a `module_root` at the **last frontend build** still has no compiled route/tile at all — no amount of live gating can reach code discovery never saw. That's the genuinely-deferred bundle-federation problem, not this ADR's scope.

### 6. Operation logs, not just log lines

Every `SetActive`/`Reload` call threads an `OpLogger` through the same steps that already logged — WASM instantiate/migrate, DB DDL, the runtime gate flip itself — writing each step to a `module_operation_log` table (created via the same primitives module migrations already use, deliberately off the generic CRUD surface). Rows carry an `operation_id` (one per activate/deactivate/reload run) and a `source` (`backend` or `db`) so the App Store's Logs view can group by run and distinguish "the Go code did this" from "this SQL ran." A broken log write must never fail the module operation it's describing — logging falls back silently to the process log instead.

## Consequences

- `PUT /api/v1/modules/:id`'s response no longer carries `requires_restart` — the change already happened by the time the handler returns.
- A deactivated module's table still exists and is still migrated at boot; "deactivated" means "inaccessible via the generic CRUD surface," not "unloaded." Data written before deactivation is untouched and reappears the moment the module is reactivated.
- Reactivating/deactivating an already-discovered module is instant, frontend included. Discovering a module that didn't exist at the last frontend build still needs one rebuild — this ADR narrows, but does not eliminate, the boundary [ADR-009](009-module-lifecycle-api.md) originally drew around all of "hot reload."
- `Registry` duplicates a small amount of state Go's compiled-binary nature makes unavoidable to duplicate correctly: it tracks whether a module is WASM- or Go-typed because they have fundamentally different reload stories (Decision 4), not because of a modeling choice that could be simplified away.

## Reference implementation

`core/internal/module/runtime.go` (`Registry`, `Boot`, `IsTableActive`, `ActiveGateMiddleware`, `SetActive`, `Reload`); the loader's table-list return and `OpLogger` param; `oplog.go` (`ModuleOperationLog`, `OpLogRepository`, `OpLogger`); the `Reload`/`Logs` HTTP handlers; the extra `ActiveGateMiddleware()` argument on route registration. Frontend: `module-discovery.mjs` (dropped the `active` skip), `module-state.ts` (`activeModuleNames`), the landing menu and catch-all route (live gating), the App Store's Reload and Logs buttons.

## Related

- [ADR-009: Module Lifecycle Managed via API](009-module-lifecycle-api.md) — the decisions this one supersedes (Decision 1) and the ones it leaves untouched (raw-JSON patching, the single-writable-field whitelist, self-protection, Views/Reports sourcing).
- [Module System](../core/module-system.md) — the loader whose boot sequence this ADR changes.
- [Module Discovery](../frontend/module-discovery.md) — the frontend half of the live gate.
