# ADR-002: WebAssembly for Module Isolation

**Status**: Accepted (hybrid model — see Amendment below)
**Date**: 2024

---

## Context

EERP is designed to support multiple business domains (CRM, Inventory, Accounting, HR, etc.) that can be developed and deployed independently. The key constraints are:

1. **Isolation**: A bug in one module must not crash the entire system.
2. **Independent deployment**: Adding a new module must not require recompiling or restarting the core (long-term goal).
3. **Language agnosticism**: Module authors should not be forced to use Go.
4. **Schema ownership**: Each module controls its own database schema.
5. **Security**: Modules should not be able to access host resources they haven't been explicitly granted access to.

The choice of module isolation mechanism is fundamental — it determines the module ABI, the deployment model, and the security boundary.

---

## Decision

Use **WebAssembly** (specifically [Wasmtime](https://wasmtime.dev/)) as the module runtime.

!!! danger "Correction — the reference implementation is Go, not Rust"
    Earlier revisions of this ADR (and of the wiki generally) described the WASM path as a Rust
    toolchain compiling to `wasm32-unknown-unknown`. That subsystem never existed in this
    repository — there is no `Cargo.toml`, no `.rs` source, and no `.wasm` binary anywhere in the
    tree. The actual, current mechanism is: **every module directory is plain Go**, and `make
    build` cross-compiles it to WebAssembly System Interface (WASI) via `GOOS=wasip1 GOARCH=wasm
    go build`, producing `<module>/build/<name>.wasm`. See the Amendment below for how the result
    is actually used — spoiler: as of this writing, it isn't.

Modules are (optionally) cross-compiled to WASI and loaded by the core's Wasmtime engine at
startup.

The module contract (ABI) is:
- `migrate() → *u8` — returns a pointer to a migration JSON in WASM linear memory
- `migrate_len() → usize` — returns the byte length of the migration data
- Future: `handle(handler_id, request_ptr, request_len) → (response_ptr, response_len)` for HTTP handler dispatch

Because the WASM target is WASI rather than a bespoke ABI, and the source language is Go rather
than an arbitrary WASM-capable language, the "language agnosticism" goal below is aspirational
today: the Go compiler is what actually produces every `.wasm` binary in this codebase.

---

## Consequences

**Positive:**
- **Sandboxed by default**: A panic or infinite loop in a WASM module cannot crash the Go process. Wasmtime enforces memory boundaries and resource limits.
- **Language agnostic in principle**: the ABI itself doesn't require Go — a future module could target it from Rust, TinyGo, C/C++, or AssemblyScript. In practice every module in this codebase today is Go cross-compiled to WASI (see Amendment).
- **Defined ABI**: The module contract is simple and versioned; the core can evolve independently.
- **Future hot-loading**: WASM modules can be loaded and unloaded at runtime without recompiling the core.
- **Portable**: The same `.wasm` binary works on any OS where Wasmtime runs.

**Negative:**
- **Complexity**: The core must maintain a Wasmtime engine, store, and linker. The shared-memory protocol (pointer + length) is error-prone.
- **Performance overhead**: WASM execution is slower than native Go. For CPU-bound workloads this matters; for database-bound workloads (most ERP operations) it is negligible.
- **Debugging difficulty**: Debugging a running WASM module requires DWARF debug info and special tooling.
- **Early ecosystem**: Wasmtime's Go bindings and the WASM component model are still maturing.
- **Build toolchain**: producing the `.wasm` artifact needs `GOOS=wasip1 GOARCH=wasm` cross-compilation, one more build target alongside the native binary.

---

## Alternatives Considered

### Go plugins (`plugin` package)

Go has a built-in plugin system that loads `.so` files at runtime.

**Rejected because:**
- **No isolation**: A panic in a Go plugin crashes the host process.
- **Linux-only**: Go plugins only work on Linux (and partially macOS). Not portable.
- **ABI fragility**: Plugins must be compiled with the exact same Go version and build flags as the host. Any mismatch causes a load failure with an opaque error.
- **No language agnosticism**: Only Go modules are supported.

### gRPC / subprocess

Run each module as a separate process, communicating via gRPC.

**Rejected because:**
- **Operational complexity**: Managing N processes per deployment is significantly more complex than one process.
- **Latency**: A gRPC round-trip (even over localhost) adds latency to every module call. ERP operations may call into a module many times per request.
- **Resource overhead**: Each subprocess has its own memory footprint, connection pool, etc.

### Dynamic library loading (CGO)

Load native shared libraries (`.so`) using CGO.

**Rejected because:**
- **No isolation**: A crash in a C library crashes the Go process.
- **Memory safety**: C code can corrupt Go's memory.
- **Linux-only**: Similar portability limitations as Go plugins.
- **Build complexity**: CGO complicates the build pipeline significantly.

### Static compilation (monorepo)

Compile all modules into the core binary at build time.

**Rejected because:**
- **Defeats the purpose**: Every module addition requires recompiling and redeploying the core. The business value of a module system is independent deployment.
- **Dependency conflicts**: All modules share the same dependency tree; conflicting versions cannot coexist.

---

## Amendment 1: Hybrid Module Model (2025)

The original decision assumed all module functionality would run inside WASM. In practice, routing every HTTP request through the WASM boundary adds serialization overhead that is unnecessary for most ERP operations (which are already database-bound).

**The amended decision** splits module responsibilities:

| Responsibility | Mechanism | Rationale |
|---|---|---|
| Schema declaration | WASM `migrate()` ABI | Sandboxed; runs once at startup |
| Business logic | Go service compiled into core binary | Zero IPC overhead; full ORM access; single binary deploy |

This preserves the original goals for schema (isolation, independent schema evolution) while avoiding WASM overhead at request time.

The "Static compilation (monorepo)" alternative above is still rejected for business logic. The hybrid model is effectively a specialised form of it for the narrow schema-declaration concern, where the tradeoffs are acceptable: schema migrations run once per startup, not per request.

## Amendment 2: `module.json`'s `type` field decides which path a module actually takes (2026)

Every module directory is Go source. `module.json`'s `type` field decides what the core does with
it:

- **`"type": "go"`** — the module compiles directly into the `core` binary and self-registers via
  `module.RegisterGoModule` (blank-imported from `core/modules/all/all.go`). Its `migrate()`/
  `migrate_len()` exports, if it builds any, are never called — the ORM's own auto-migration
  (`orm.Register[T]` diffing) handles schema instead. See [Module System](../core/module-system.md).
- **`"type": "wasm"`** — the module's cross-compiled `.wasm` artifact is loaded dynamically at
  startup through Wasmtime, exactly as this ADR originally describes.

**Current state**: every module shipped in this repository today has `"type": "go"`. The
WASM-loaded path is fully implemented and exercised by the detector/loader/runtime code
(`core/internal/module/{detector,load,runtime}.go`), and `wasmtime-go` is a real, active
dependency — but no module currently uses it in production. It remains available for a module that
genuinely needs runtime schema isolation without a core rebuild.
