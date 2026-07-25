# ADR-008: Default Form Anatomy — Synthesized Header, Columns, Notebook

**Status**: Accepted (header/columns and the notebook node/default Settings page implemented; runtime, per-record notebook pages remain forward-looking, tracked below as Phase 5)
**Date**: 2026-07-10

## Context

Before this ADR, `FormRenderer` rendered every `viewType: 'form'` descriptor as one capped-width column, and layout normalization — the single place that resolves a descriptor's presentational structure — synthesized the same implicit fallback for every view type: one untitled group wrapping every field in declaration order. That fallback is what made the layout tree backward-compatible when it was introduced: a descriptor written before it existed renders unchanged.

A fundamentally different default form shape was wanted — a header (picture left, big title right), two responsive columns, and a notebook of tabbed pages underneath, modeled on Odoo's form view — as the shape every entity gets **without declaring anything**. That is a much bigger change than adding a rendering option: it means the one fallback layout normalization has always produced now needs to differ **by view type**, and the new fallback needs to compose with everything already built on top of the layout tree — view extensions ([ADR-006](006-view-inheritance.md)), declarative field states, behaviors.

Three questions had to be answered before any code:

1. Does the new anatomy live in `descriptor.layout` (stored, like an explicit layout), or does it stay synthesized (computed, like the old fallback)?
2. Extensions ([ADR-006](006-view-inheritance.md)) resolve against layout normalization's output — what happens to `crminheritdemo`'s existing ops, written against a flat form, once that output has structure?
3. Runtime, per-record notebook pages ("a user adds a Meeting Notes tab to *this* record") are neither build-time descriptor data nor workspace `app_settings` ([ADR-007](007-runtime-view-fields.md)) — what are they, and how does that boundary stay legible next to the other two?

## Decision

### 1. The anatomy is synthesized, exactly like the old fallback — never written to `descriptor.layout`

Layout normalization keeps its existing contract (declared `layout`, validated, or a computed default) and gains exactly one new branch: `viewType === 'form'` with no declared `layout` now computes a **richer** default — a header row (`__form_header`: the first `widget: 'picture'` boolean field, then the first `text` field rendered big via a new `variant: 'title'` hint) followed by a two-column group (`__form_columns`, a new `columns` hint) holding every other field, in declaration order. Every other view type (`tree`, `dashboard`, and any future one) keeps the original flat, untitled group, unchanged — this is a narrow, `viewType`-scoped addition to an existing mechanism, not a new one.

Nothing is ever written back to `descriptor.fields` or `descriptor.layout`. A module that declares an explicit `layout` gets exactly what it declared, at any view type — it has opted out of the default by definition, the same rule that already governed the flat fallback.

### 2. Synthesized nodes carry stable, well-known ids — extensions target the default anatomy exactly like a hand-authored one

`FORM_HEADER_ID = '__form_header'` and `FORM_COLUMNS_ID = '__form_columns'` are exported constants, not implementation details. `applyExtension` already normalizes the layout before applying operations; for a form view it now materializes the richer default first, so an extension's `addField`/`move`/`addNode` operations resolve against the header/columns structure exactly as they resolved against the flat group before. Two concrete consequences fall out of this:

- A no-target `addField` (`position` defaults to `'last'`, `target` absent) lands as the last child of `__form_columns` — the last top-level container — instead of at the top level of a flat group.
- `crminheritdemo`'s pre-existing `{ op: 'move', name: 'email', target: 'name', position: 'before' }` (written against a flat form) still resolved, but since `'name'` became the title field living inside `__form_header`, `'email'` landed as a sibling there, joining the header instead of the flat body it used to join — a real, visible consequence of a `move`'s anchor field moving out from under it as the default anatomy changed. Fixed by retargeting the op onto a field under the module's own control (`{ target: 'date', position: 'after' }`) instead. The general lesson: an extension anchored on a field it does not own can have its target's home change under it when the default anatomy evolves; anchoring on a field the same extension controls is more future-proof.

No new extension operation was needed — this is the point of stable node ids existing at registration-time already ([ADR-006](006-view-inheritance.md)): a synthesized node is addressable by the same mechanism as a hand-authored one.

### 3. Runtime notebook pages are per-record data — a third category alongside descriptor and `app_settings`

(Accepted here; implemented for the declared half — see decisions 4–5 below — with the runtime half, a user's own per-record pages, still forward-looking as Phase 5.) The notebook's declared pages (a `page` layout node inside a `notebook` node, holding fields) are descriptor structure, the same category as everything else in the layout tree. A page a **user** adds to one specific record at runtime ("Meeting Notes" on this one crm row) is neither of the two categories this codebase already has a home for:

- Not descriptor data ([ADR-006](006-view-inheritance.md)'s territory): it isn't build-time structure a module author commits, and it doesn't exist for every record of the entity, only the one the user added it to.
- Not workspace `app_settings` ([ADR-007](007-runtime-view-fields.md)'s territory): it isn't a tenant-wide admin preference either — two different `crm` records can have entirely different runtime pages.

It is **record-anchored content**, the same shape of thing the picture service already represents (metadata keyed on `(tenant, table, record, field)`, tenant-pinned dedicated routes off the generic CRUD surface, route-derived permissions). `internal/notebook/` follows that exact template. This is a deliberate third category: a future "where does this concern live" question should ask whether it exists for every record by construction (descriptor), is one value the whole tenant shares (`app_settings`), or varies per record at the user's own discretion (record-anchored data, this pattern).

### 4. Two new JSON-only layout hints, not new widget types

`variant: 'title'` and `columns: number` are rendering hints on the existing node shapes, not a fourth node kind or a new widget. `variant: 'title'` still dispatches to a real text input, restyled — required/disabled/error affordances all still apply, because it is still the same field, never a different component with its own validation story. `columns` renders as a CSS **container query** grid, deliberately never a viewport media query: the identical form layout renders both the full-width form page and the relation create-wizard's narrower dialog, and only the dialog should ever collapse to one column — a viewport query cannot tell those two render contexts apart, a container query naturally can.

### 5. The notebook is two new layout-tree node kinds, not a new extension operation

`{ kind: 'notebook', children }` and `{ kind: 'page', title, children }` are ordinary layout container nodes — no new TypeScript interface — with layout normalization enforcing the structural rules a hand-authored layout must follow exactly as strictly as a synthesized one: a `page` is legal only as a direct child of a `notebook`, every `page` declares a `title` (it doubles as the tab label), a `notebook`'s children are all `page`s, and at most one `notebook` exists per layout (v1). Because a page is just a node with an `id`, the existing extension operations already reach it — `addNode` targeting the notebook's id adds a page, `addField` targeting a page drops a field on it, `move` relocates fields between pages — so "a module creates a page as easily as it extends any other view" needed zero new API surface. The synthesized default (`FORM_NOTEBOOK_ID`, holding `PAGE_SETTINGS_ID` — title `'Settings'` — pre-loaded with every `widget: 'long'` field) renders even with zero long fields, since it doubles as where Phase 5's runtime pages will attach.

### 6. Switching pages is client-only, ephemeral state — panels never unmount

The active tab is a plain `useState<number>` inside the notebook's own renderer: it is view state, not data, and it resets freely on navigation with no persistence contract to honor. The panels themselves stay mounted at all times — the inactive ones toggle the native `hidden` attribute, never a conditional unmount — so a field's mount effects (a picture fetching its bytes, a relation widget querying its options) keep running on a page the user isn't looking at, and a dirty, uncommitted edit on one page survives switching to another and back. This costs a live subscription per hidden page at this scale, an accepted trade against losing in-progress edits or re-fetching on every tab click.

## Consequences

- `ViewDescriptor.layout` gains no new required shape — an un-layouted form gets the new anatomy for free; an explicit layout (at any view type) is untouched.
- Field-order output for `tree`/`dashboard`/`kanban`/`calendar` consumers (DataGrid columns, Kanban/Calendar card fields) is provably unchanged — pinned by a test asserting flat declaration order survives for those view types.
- Extensions targeting a form view now resolve against a nested default instead of a flat one. Order-relative assertions anchored on a field the extension itself controls keep holding; structure-exact assertions, or ones anchored on a field whose container can change out from under them, do not — the new nesting is the intended change, not an implementation leak.
- The relation create-from-search wizard, which reuses the exact same form layout a target entity's form uses, automatically renders the same header/columns default the entity's real form does — single-column, because its dialog is narrower than the two-column breakpoint — with no wizard-specific code.
- The three-way split this ADR names — descriptor (build-time, developer-owned) / `app_settings` (workspace-wide, admin-owned, [ADR-007](007-runtime-view-fields.md)) / record-anchored service data (per-record, user-owned, the pictures/notebook pattern) — is the reference answer for where a future "where does this new concern live" question should land.
- A synthesized form always ships a notebook, even with zero long fields and zero module-added pages — empty chrome in that case, kept because it is where Phase 5's runtime, per-record pages attach.

## Reference implementation

`core-front/packages/core-front/src/views/descriptor.ts` (`FORM_HEADER_ID`, `FORM_COLUMNS_ID`, `FORM_NOTEBOOK_ID`, `PAGE_SETTINGS_ID`, `synthesizeFormLayout`, the layout hints, and layout normalization's `notebook`/`page` structural validation); `layout-renderer.tsx` (`TitleField`, the container-query `columns` rendering, the notebook renderer — MUI `Tabs` + `hidden`-toggled, always-mounted panels); `renderers.tsx`'s `FormRenderer` (the width cap removed); `registry/extensions.ts` (the form-view materialization, and the target-less `addField` fallback logic).

## Related

- [View Engine](../frontend/view-engine.md) — the descriptor/renderer contract this ADR extends with layout anatomy.
- [ADR-006: Frontend View Inheritance](006-view-inheritance.md) — the extension mechanism synthesized nodes plug into.
- [ADR-007: Runtime-Configurable View Fields](007-runtime-view-fields.md) — the other half of the descriptor / `app_settings` split this ADR completes.
