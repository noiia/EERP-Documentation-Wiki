# ADR-007: Runtime-Configurable View Fields (Kanban/Calendar)

**Status**: Accepted
**Date**: 2026-07-09

## Context

Every `tree` (list) view gained a display-mode switcher: `List | Kanban | Calendar | Graph`. Kanban needs to know which field holds a record's status (to become its columns); Calendar needs to know which field holds a date (to position records on a grid). Both are per-entity choices — `crm`'s status field is `status`, another entity's might be `stage` or nothing at all.

Every other per-field concern already living in this codebase — `widget`, declarative states, `compute`, `default`, `relation` — is something a **module author** commits in a `FrontModule`'s descriptor. [ADR-006](006-view-inheritance.md) went further and made even *reshaping another module's view* a build-time, developer-authored concern (`ViewExtension`, resolved at registration). The reflex, following that precedent, would be to add `ViewDescriptor.kanbanStatusField?: string` and `calendarDateField?: string` next to `formPath`/`createPermission`.

That reflex is wrong here, and this ADR exists to say why — and to bound the exception so it doesn't become precedent for moving other descriptor concerns into runtime config.

## Decision

### Kanban/Calendar field choice is workspace admin state, not descriptor data

Unlike `widget` or declarative states, which encode something true about the *data model* (a boolean is naturally a switch; a comment is naturally hidden while a deal is incoming) and therefore belong with the module that defines the field, "which field is the Kanban column" is a **presentation preference an administrator makes after the module ships**, with no natural single right answer, changeable without a rebuild or a deploy. Two workspaces running the identical `crm` module might reasonably choose different status fields to kanban by (or none at all). That is the same shape of decision as a locale or number-format setting — both already live in tenant-scoped `app_settings`, edited from a Settings page, never in a descriptor — not the shape of decision `widget` or declarative states represent.

Concretely: `views.<entity>.fields = { kanban_status_field, calendar_date_field }` is a tenant-scoped `app_settings` key (`core/internal/settings`), read/written through dedicated handlers `GET|PUT /api/v1/settings/views/:entity/fields` (permission `settings:views:read|write`) — the same pattern as the existing i18n/format settings, not a new mechanism.

### The frontend still sources the choices from the descriptor, just not the choice

Settings → Views does not ask an admin to type a field name. It reads the already-registered `ViewDescriptor` for each entity (via `moduleRegistry.buildRegistry()`, the same accessor the catch-all route uses) and offers only that entity's `type: 'selection'` fields as Kanban candidates and `type: 'date'` fields as Calendar candidates. So the descriptor still owns *what fields exist and what type they are* — the developer-authored, build-time truth — while `app_settings` owns *which of those the workspace picked* — the admin-authored, runtime truth. Neither side duplicates the other's job.

### Absence is a normal state, not an error

An entity with no configured Kanban/Calendar field is not a misconfiguration: most entities will never need one. `GetViewFieldsSettings` returns `{null, null}` for an unconfigured entity with a 200, not a 404, and the frontend's mode switcher simply keeps those two buttons disabled ("Configure in Settings → Views") until set. Graph needs no such gate — an empty canvas is itself a valid state — so it's the one mode that's never disabled.

## Consequences

- `ViewDescriptor` gains **no new fields** for this feature. `FrontModule` authors write nothing to get Kanban/Calendar available on their entity — an admin configures it later, purely from Settings, purely at runtime.
- Two workspaces running the same module build can have different Kanban/Calendar configurations without a rebuild, redeploy, or descriptor diff — by design, since this is workspace state, not code.
- This is a **narrow, named exception**, not a new default. The test for the next "should this be a descriptor field or `app_settings`?" question: does the value encode something true about the field itself (→ descriptor, developer-owned), or is it a workspace's presentation preference over an otherwise-unopinionated field (→ `app_settings`, admin-owned, this ADR's pattern)? Most future concerns will still be the first case.
- Settings → Views has a dependency [ADR-006](006-view-inheritance.md)'s other settings pages don't: it must enumerate every registered module's tree-view descriptors, so it needs the same generated-manifest side-effect import the catch-all route and the landing menu use.

## Reference implementation

`core/internal/settings` (`GetViewFieldsSettings`/`PutViewFieldsSettings`, key `views.<entity>.fields`); `core-front/packages/core-front/src/api/view-fields.ts` (`ViewFieldsConfig`, `DisplayMode`, `availableDisplayModes`); the `TreeRenderer` mode switcher and `useUiStore.viewMode`; `apps/shell/app/settings/views/` (the admin UI, sourcing field choices from `moduleRegistry.buildRegistry()`).

## Related

- [View Engine](../frontend/view-engine.md) — the descriptor contract this ADR deliberately keeps unchanged.
- [ADR-006: Frontend View Inheritance](006-view-inheritance.md) — the build-time counterpart this ADR is an exception to.
- [ADR-008: Default Form Anatomy](008-form-anatomy.md) — the three-way descriptor / `app_settings` / record-anchored-data split this ADR establishes half of.
