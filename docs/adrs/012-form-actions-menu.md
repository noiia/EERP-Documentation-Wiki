# ADR-012: Form Actions Menu — Default Form Chrome for Custom Actions

**Status**: Accepted
**Date**: 2026-08

---

## Context

Before this decision, `ReportExportButton` was the *only* way a module could hang a custom action
off a form — the catch-all route special-cased it directly (`viewType === 'form'` plus a
registered report resolved a print button). That doesn't generalize: a "Send by email,"
"Duplicate," or "Mark as paid" action would each need its own bespoke special case in a component
meant to stay generic across every module.

Separately, a form's page title was redundant: the default form anatomy
([ADR-007](007-runtime-view-fields.md)'s sibling, [ADR-008](008-form-anatomy.md)) already promotes
the record's name-like field into a large title, so a form showed its title twice.

## Decision

**One generic options menu, declared as data.** `ViewDescriptor.actions?: MenuNode[]` is a small
recursive tree (`{ kind: 'action', label, action }` or `{ kind: 'submenu', label, children }`). An
action leaf names its handler by **name**, never a function reference — the same
data-crosses-the-RSC-boundary rule `compute`/`on_change` already follow. `registerMenuAction({
entity, name, handler })` is where a module's views file registers the actual handler at import
time, mirroring `registerFieldFunction`/`registerOnChange` exactly, down to "an unregistered or
mismatched action name fails at module registration, never silently at click time."

This makes "add a custom form action" a two-line addition to a module's own views file — no
catch-all change, no new special case — for any action, printing included (printing is simply the
first handler that happened to get registered, calling `exportReportPDF(reportName, recordId)`).

**The button is default chrome, not opt-in.** `FormActionsMenu` renders unconditionally for every
`viewType: 'form'` route, the same "the engine always provides this structural piece" posture
`CreateBar` takes for tree views. A descriptor with no `actions` still gets the button, just
disabled — a deliberate trade favoring one fewer special case in the catch-all over a mostly-empty
button on unconfigured forms. It is also disabled on an unsaved draft (`recordId === 'new'`).

**The page title is dropped from forms.** The title row now branches on `viewType === 'form'`
(forms render none; tree/dashboard/catalog keep it). `FormActionsMenu` moved into `FormRenderer`
itself, alongside Save/Reset in the same row, immediately to its left.

**Nesting is a real MUI submenu.** A `submenu` node opens a second, right-anchored MUI `Menu` —
closing the root menu unmounts every open submenu automatically, no explicit bookkeeping needed.

## Consequences

- `ReportExportButton` is deleted outright — every entity wanting a print trigger registers a menu
  action instead.
- A module wanting a form action must both declare the `MenuNode` (data) and register its handler
  (code) — two places, on purpose, mirroring `compute`'s split.
- No per-action permission gating exists yet — every action on a form a user can already open is
  visible in the menu. The underlying handler still goes through the same authorized paths, so this
  is a UI-affordance gap, not a security one.

## Reference Implementation

`core-front/packages/core-front/src/views/form-actions-menu.tsx`, `views/menu-actions.ts`
(`registerMenuAction`), `views/descriptor.ts` (`MenuNode`). `core/modules/sale` (`Invoice`'s Print
→ Invoice menu action) is the first consumer.
