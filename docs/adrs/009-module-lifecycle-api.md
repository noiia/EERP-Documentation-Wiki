# ADR-009: Module Lifecycle Managed via API

**Status**: Superseded by [ADR-010](010-live-module-lifecycle.md) on the hot-reload decision (Decision 1); the rest of this record still stands
**Date**: 2026-07-10

## Context

An App Store gives every workspace a self-service view over its installed modules: a catalog page listing them, a form per module, and a way to turn one on or off without SSHing in and hand-editing a `module.json`. This was built in four phases — a Go management API over `module.json` (Phase 1), two small engine gaps the App Store's UI needed generically (Phase 2), the `appstore` module itself (Phase 3), and the Activate/Deactivate wiring (Phase 4) — and along the way several decisions were made that cut against the codebase's usual defaults. This ADR records why, so a future reader doesn't mistake any of them for oversights.

## Decisions

### 1. File-write + restart, not hot reload — **superseded by [ADR-010](010-live-module-lifecycle.md)**

> This decision described the original (Phases 1–4) design and is kept below for historical context. It no longer reflects the current behavior: `PUT /api/v1/modules/:id` now flips a live, in-process gate immediately and only writes `module.json` afterward — no restart, no `requires_restart` field. See [ADR-010](010-live-module-lifecycle.md) for the live-lifecycle design and why "hot reload" turned out to be smaller in scope than this decision originally assumed.

`Manager.Patch` (`core/internal/module/manager.go`) wrote straight to the module's `module.json` on disk and returned immediately — it did not re-trigger module loading, unload a WASM instance, or otherwise make the change live. Every successful `PUT` response carried `requires_restart: true`, and the frontend surfaced that as a persistent notice rather than pretending the toggle took effect.

Hot-reloading a WASM module mid-process — draining in-flight requests, tearing down its Wasmtime instance, re-running its migration, re-registering its routes — is real, general infrastructure work that belongs to the module *loading* system (see [Module System](../core/module-system.md)), not to a CRUD-shaped management API. Building it here would have meant solving it twice.

### 2. Raw-JSON patching, not a typed round-trip

`Manager` reads and writes `module.json` as a plain map, never deserializing into a typed `Module` struct. The typed, cached walk used elsewhere in module discovery exists for a different job — fast, repeated lookups during module loading — and only knows the fields the loader needs. The App Store's management API must round-trip *whatever keys a module.json actually has*, including ones no Go type declares yet — a typed struct would silently drop them on every write. Raw-map patching, field-whitelisted (`writableModuleFields`) rather than struct-whitelisted, is the only way a `PUT` can touch exactly one key and leave everything else on disk byte-for-byte equivalent.

This is also why `Manager` is deliberately stateless — no snapshot cache — a `PUT` must always patch what's on disk *right now*, never a cached view that a concurrent process (or a manual edit) has already moved past.

### 3. Activation is a button, not a field

The App Store's form page declares every field `readOnly: true`, `active` and `app_mode` included. The Activate/Deactivate control is host chrome rendered beside the generic entity view, never a field inside it, with its own Server Action hitting `PUT /api/v1/modules/:id` directly — the form's own commit path is never exercised, because a form with no writable fields never dirties.

The reason isn't mechanical (a `switch` widget bound to `active` would work fine); it's that flipping a module's active flag is not "editing a record." It has side effects a plain field commit doesn't: it needs the self-protection check (below), it needs to explain that the change is pending a restart (pre-[ADR-010](010-live-module-lifecycle.md)), and it needs to badge the catalog row so a workspace admin can see what they just touched even after navigating away. A button with its own action makes room for exactly that.

### 4. `app_mode` stopped being writable

`writableModuleFields` whitelists exactly `{"active": true}`. Early drafts considered letting `app_mode` and `display_name` be edited from the App Store too, since they're both plain `module.json` keys. That was narrowed to `active` alone: every other key is *deployment metadata* — how a module presents once compiled in, what version was compiled, which files load — decided when the module is authored or deployed, not something a workspace admin should be able to drift from the code that was actually shipped. `active` is the one exception because "is this module running" is squarely operational state, the same kind of on/off a workspace admin already expects to control. The whitelist being a single-entry map is the enforcement mechanism, not an oversight to widen casually.

### 5. Self-protection is server-enforced, not just a UI hint

`applyPatch` refuses `active: false` for the `appstore` module itself with a validation error, regardless of what the frontend sends. The Activate button also disables itself with a tooltip for this exact case — but that's a UX courtesy, not the enforcement boundary. A REST client hitting the endpoint directly still can't brick the one module that lets you turn modules back on.

### 6. Views/Reports data comes from the frontend's own registry, not Go

The App Store's form has a notebook with a "Views" tab (every view a module created or edited) and a "Reports" tab (currently inert, reserved for a future roadmap). Both are populated entirely from the frontend — reading `moduleRegistry.buildRegistry()` (which route a module registered, i.e. "Created") and `moduleRegistry.extendedPaths()` (which routes a module's own `extends` targets, i.e. "Edited"; see [ADR-006](006-view-inheritance.md)). Go never sees this data; there's no endpoint for it, because "which views does module X own or touch" is answered entirely by facts the frontend's `ModuleRegistry` already computes at registration time — the one place that has already resolved every module and every view extension for the whole running frontend.

## Consequences

- ~~Deactivating a module from the App Store changes `module.json` on disk immediately, but the module keeps running until the next rebuild~~ — **superseded by [ADR-010](010-live-module-lifecycle.md)**: deactivation now gates the module's routes live, in the same request cycle as the `PUT`.
- The App Store's own `active` flag has one extra guard the generic whitelist doesn't: it can be flipped to `false` for any *other* module by any caller with the right permission, but never for itself.
- Adding a new writable `module.json` field later means adding it to `writableModuleFields` **and** writing the argument for why it's operational state rather than deployment metadata (Decision 4) — this ADR is where that argument should be recorded or contested.
- ~~Hot reload deferred to a future runtime module registry~~ — **superseded by [ADR-010](010-live-module-lifecycle.md)**: activate/deactivate/reload are live for every module already known at the last build; only a module folder that didn't exist at that build still needs one rebuild to be discovered at all. A real Reports page is still out of scope, deferred to its own future roadmap.

## Reference implementation

`core/internal/module/manager.go` (`Manager`, `writableModuleFields`, `applyPatch`, `appstoreModuleName`), `handler.go` (`Handler`, the `requires_restart` response field — now removed, see ADR-010); `core/modules/appstore/views/AppStoreViews.ts` (the read-only form descriptor, the Views/Reports notebook pages); the App Store's Activate button (its own write path, optimistic update, revert-and-error-alert); the module-views helper reading `moduleRegistry.buildRegistry()` + `extendedPaths()`.

## Related

- [ADR-010: Live Module Lifecycle](010-live-module-lifecycle.md) — supersedes this ADR's hot-reload decision.
- [Module System](../core/module-system.md) — the loader this API sits in front of.
- [ADR-006: Frontend View Inheritance](006-view-inheritance.md) — the registry data the Views tab reads.
