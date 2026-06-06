# ADR-002: WebAssembly for Module Isolation

**Status**: Accepted
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

Use **WebAssembly** (specifically [Wasmtime](https://wasmtime.dev/)) as the module runtime. Modules are compiled to `wasm32-unknown-unknown` and loaded by the core at startup.

The module contract (ABI) is:
- `migrate() → *u8` — returns a pointer to a migration JSON in WASM linear memory
- `migrate_len() → usize` — returns the byte length of the migration data
- Future: `handle(handler_id, request_ptr, request_len) → (response_ptr, response_len)` for HTTP handler dispatch

The reference implementation is in Rust, but any language that compiles to WASM can implement this ABI.

---

## Consequences

**Positive:**
- **Sandboxed by default**: A panic or infinite loop in a WASM module cannot crash the Go process. Wasmtime enforces memory boundaries and resource limits.
- **Language agnostic**: Module authors can use Rust, Go (via TinyGo), C/C++, AssemblyScript, or any other WASM-capable language.
- **Defined ABI**: The module contract is simple and versioned; the core can evolve independently.
- **Future hot-loading**: WASM modules can be loaded and unloaded at runtime without recompiling the core.
- **Portable**: The same `.wasm` binary works on any OS where Wasmtime runs.

**Negative:**
- **Complexity**: The core must maintain a Wasmtime engine, store, and linker. The shared-memory protocol (pointer + length) is error-prone.
- **Performance overhead**: WASM execution is slower than native Go. For CPU-bound workloads this matters; for database-bound workloads (most ERP operations) it is negligible.
- **Debugging difficulty**: Debugging a running WASM module requires DWARF debug info and special tooling.
- **Early ecosystem**: Wasmtime's Go bindings and the WASM component model are still maturing.
- **Build toolchain**: Module authors need a Rust (or other WASM-capable) toolchain in addition to Go.

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
