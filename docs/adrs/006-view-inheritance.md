# ADR-006: Frontend View Inheritance

**Status**: Accepted
**Date**: 2026-07-09

## Context

The Go backend already had a working answer for "let one module extend another's shape without editing it": `crminheritdemo` embeds `crm.CRM`, re-registers the `crm` table under `orm.WithTableName("crm")`, and the generic CRUD API gains `date`/`comment` columns — the `crm` module's own Go source is never touched. That pattern (declare, don't patch) is the whole reason [`orm.Register[T](orm.WithTableName(...))`](../core/orm.md) exists.

The frontend had no equivalent. `ViewDescriptor.fields` was a flat, closed array a module declared once (see [View Engine](../frontend/view-engine.md#descriptors)); nothing else could see or reshape it. So `crminheritdemo`'s extra columns existed in the API but could never appear on the CRM form or list — the one place users actually look — without editing `CrmViews.ts` directly. That breaks the module-isolation promise in exactly the place it matters most, and it meant the backend's own showcase module had no frontend at all.

Three sub-questions had to be answered before any code:

1. **When does an extension apply — render time, or earlier?**
2. **How does an extension describe a change — component overrides, or something else?**
3. **What guarantees a base view exists before something tries to extend it?**

## Decision

### 1. Resolution happens once, at registration — never at render

`ModuleRegistry.register()` applies a module's `extends` immediately, merging the result into a `resolvedRoutes: Map<path, RouteConfig>` the registry already needed for `buildRegistry()`. Every accessor (`buildRegistry()`, `menu()`, `listViews()`, `formDescriptorFor()`) reads that map directly — none of them, and none of the client renderers (`FormRenderer`, `TreeRenderer`, the relation create-from-search wizard), have any awareness that `extends` exists. A renderer receives one plain, already-merged `ViewDescriptor` and walks it exactly like it always has.

This mirrors the Go loader's own posture: [module loading](../core/module-system.md) resolves the module graph once at startup, not per-request. Resolving per-render instead would mean re-running every extension's operations on every page load (wasted work, since the operations are pure and deterministic) and — worse — would leak the *concept* of inheritance into rendering code that has no business knowing about it.

### 2. Extensions are serializable operations, not component overrides

The alternative most frameworks reach for — override a component, wrap it, or monkey-patch a render function — was never on the table: descriptors cross the RSC boundary as props from a Server Component to a Client Component, and React Server Components can only pass JSON-serializable data across that boundary. A function reference cannot survive the trip. This was already the standing rule for a field's `compute`/`on_change` (registered by name, not passed as a closure) and for declarative field states (a `Condition` object, not a predicate function); view extensions are the same constraint applied one level up, to the *shape* of the view instead of one field's value.

Odoo solved the identical problem for server-rendered XML views: `<xpath expr="//field[@name='email']" position="after">…</xpath>` is data an interpreter walks, not code that runs. `Operation` (`addField` / `removeField` / `setField` / `move` / `addNode` / `setDescriptor`) is that same idea in typed TS instead of XPath — the anchor is a field `name` or an explicit layout node `id` (no XPath expression language to parse or sandbox), and `applyExtension()` is the interpreter: a pure function, `(descriptor, operations) → descriptor`, fully unit-testable without a DOM, a registry, or a running app.

**Why this shape stays cheap even as the operation set grows**: every operation is a plain tagged record (`{ op: 'addField', ... }`); adding a new operation kind is a new union member and a new `case` in `applyExtension`'s switch, not a new escape hatch into arbitrary code. The registry's `register()` step still validates the *result* through the same widget/behavior/layout validation gate a base descriptor goes through — an extension that produces a broken field or a dangling layout reference fails exactly where a hand-written bug would, at registration, naming the module and the operation.

### 3. Dependency-ordered registration is what makes "already registered" true

An extension's very first requirement — "the path I'm targeting must already resolve to something" — only holds if modules register in the right order. Sorting modules alphabetically (the prior behavior) made `crminheritdemo` register after `crm` *by coincidence of spelling* — a module named `aaa-something` extending `crm` would have silently failed to find its target.

`module.json`'s `depends` field already existed — the Go loader reads it (see [Module System → Dependency Resolution](../core/module-system.md#dependency-resolution)) — but nothing on the frontend acted on it. `topoSortModules` (in `module-discovery.mjs`) computes a real topological order from that graph (name as tie-break for determinism; a cycle is a build error naming the chain), and the generated manifest registers modules in that order. This turns "the target is already registered" from a lucky accident into a build-time invariant. A module that extends a path without declaring the owning module in its own `depends` still *works* (registration order already guarantees the target exists) but gets a `console.warn` naming the gap — a hygiene signal, not a hard gate.

## Consequences

- Renderers, stores, and loaders stayed untouched — the entire feature lives in the registry layer, which is exactly what "resolve once, render a plain descriptor forever after" was meant to buy.
- A base module's route path is now part of its public contract: renaming `/crm/:id` breaks every extension targeting it, loudly, at the extending module's registration — the same blast radius a breaking API change has, which is the correct severity.
- `applyExtension` defines precise semantics for cases that would otherwise be implicit — a target-less `addField`/`move` inserts into the last top-level container's children (not as a stray top-level sibling), and `addNode` extracts its referenced fields from their current position before re-homing them (so wrapping already-placed fields into a new row doesn't produce a duplicate-field validation error). Both are pinned by tests.
- The "depends-coverage" warning could not live in the static discovery script as a codegen-time warning, because that script never executes a module's TypeScript — it only writes `import` statements for the bundler to resolve. The check lives in `ModuleRegistry.register()`, which has full runtime access to `.extends` and already knows which module owns which path.

## Reference implementation

`core/modules/crminheritdemo` is the proof end to end: its Go side (`module.go`, `internal/crm.go`) adds `date`/`comment` columns to the `crm` table without touching `core/modules/crm`; its frontend side (`views/CrmInheritViews.ts`) extends `/crm/:id` and `/crm/list` — adding those same two fields, reordering `email` before `name`, and hiding `comment` while `status` is `incoming` — without touching `core/modules/crm/views/CrmViews.ts`. Deactivating `crminheritdemo` (`module.json` `active: false`) and rebuilding removes both the Go columns' API surface and the frontend extension, restoring the stock CRM view.

## Related

- [View Engine](../frontend/view-engine.md) — the descriptor/renderer contract this extends.
- [Module Discovery](../frontend/module-discovery.md) — build-time registration and dependency ordering.
- [ADR-007: Runtime-Configurable View Fields](007-runtime-view-fields.md) — the narrow, deliberately *non*-descriptor exception to this ADR's pattern.
- [ADR-008: Default Form Anatomy](008-form-anatomy.md) — how synthesized layout nodes stay addressable by these same operations.
