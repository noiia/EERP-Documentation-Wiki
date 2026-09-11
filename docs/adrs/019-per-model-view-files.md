# ADR-019: One View File per DB Model, One File per Report

**Status**: Accepted
**Date**: 2026-08-27

---

## Context

Every module's frontend contribution had grown into a single monolithic `<Module>Views.ts` file —
`sale/views/SaleViews.ts` reached 892 lines covering four entities and two printable reports;
`propertymanagement`'s reached 708 lines covering six entities. Finding "the quote workflow" or
"the rent receipt report" meant scrolling one large file mixing unrelated entities, with no
filesystem structure mirroring the actual data model.

**A real engine constraint surfaced first**: `ModuleRegistry.register()` is idempotent **by module
name** — a second `register()` call under an already-seen name is silently skipped, not merged. A
naive split (each entity's file independently calling `register()` under the same module name)
would silently drop every entity past the first discovered.

## Decision

1. **One `<model>_views.ts` per owned entity, one `reports/<name>_report.ts` per report.** Each
   entity file holds its TypeScript interface, `ViewDescriptor`s, and any `register*` side-effect
   calls. Reports live in a `reports/` folder that is a **sibling** of `views/`, at the same level
   `i18n/` already sits.
2. **Exactly one file per module still default-exports the `FrontModule`** — a thin assembler,
   `<module>_views.ts`, importing routes/pieces each entity file exports and combining them into
   the single object `module.json`'s `static_files.views` lists. This is the *only* file the
   discovery script ever imports for that module; every entity file is reached from there by an
   ordinary import, invisible to discovery. This solves the registry-idempotency constraint with
   zero engine changes.
3. **Two naming resolutions, applied consistently**: a module with exactly one owned entity (e.g.
   `crm`, `contact`) skips the separate assembler — its one file both declares the entity's pieces
   and default-exports the `FrontModule`. A module whose name collides with one of its own entities
   (e.g. `cron`'s `cron` entity alongside `cron_history`) lets that entity's file double as the
   assembler. A module owning zero entities (`crminheritdemo`, pure view-extension) names its one
   file after the module itself.
4. **Route order across files must reconstruct the original order exactly** — a module's landing
   tile opens `routes[0].path`, and tile/menu ordering reads `routes` in declaration order. Every
   assembler pulls the dashboard route into its own export (forced first) and preserves each
   entity's original relative order.

## Consequences

- A new entity added to an existing module is a new file plus one import line in the assembler —
  never appended to a growing shared file.
- `module.json`'s `static_files.views` names only the assembler; adding an entity/report file never
  touches it.
- Each module's test file stays one combined `<assembler>_views.test.ts` — the split applies to
  source structure, not test structure.
- A new module scaffolded by `tools/eerp-init-module` starts in this shape directly.

## Reference Implementation

`core/modules/sale/views/sale_views.ts` (assembler) + `invoice_views.ts`/`sale_line_views.ts`/
`quote_views.ts`/`quote_line_views.ts` + `reports/invoice_report.ts`/`reports/quote_report.ts` —
applied identically across `crm`, `contact`, `appstore`, `crminheritdemo`, `cron`,
`propertymanagement`, `warehouse`. `core-front/packages/core-front/src/registry/registry.ts`
(`ModuleRegistry.register()`'s idempotent-by-name contract). See [View Engine → Field
Widgets](../frontend/view-engine.md), [Creating a Frontend Module](../developer-guide/creating-a-frontend-module.md).
