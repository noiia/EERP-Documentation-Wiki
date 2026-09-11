# ADR-015: Built-In Search/Filter Bar for List Views

**Status**: Accepted
**Date**: 2026-08

---

## Context

Every `tree` list view had no search or filtering affordance beyond whatever a module manually
wired one-off. The ask: a search bar every list view gets automatically — the same "structural
chrome the engine always provides" posture `CreateBar` and the List/Kanban/Calendar/Graph mode
switcher already take — filtering entirely server-side, respecting field-level group gating
([ADR-014](014-field-level-group-gating.md)), with a group-by section reflecting a field's actual
distinct values, plus named filter combinations a user can save privately or share tenant-wide.

This also **closes a gap ADR-014 deliberately deferred**: `filter[col]=`/`search[col]=` were not
group-aware, letting a caller lacking a field's group infer values from which rows matched.

## Decision

1. **`Repository.checkColumn` closes the group-gating gap**, and every new filter kind below
   reuses this one function — gating a field via `WithFieldGroups` makes it invisible to
   filtering/searching/grouping automatically, no separate opt-in.
2. **Structured filters extend `ListFilter` with parallel maps**, not a generic operator DSL: `In
   map[string][]string` (`col::text = ANY($1)`) and `GT`/`GTE`/`LT`/`LTE map[string]string` (range
   comparisons, type-aware cast to `numeric` or `timestamptz` via `FieldMeta.GoType` — lexicographic
   `::text` comparison would be wrong for numbers). A "between" is just a `GTE` plus an `LTE` on
   the same column. OR-composition and `is_empty`/`is_set` are explicitly out of scope for v1.
3. **Group-by rides the existing list endpoint via `?distinct=<column>`**, not a new route — a
   literal new route would derive its own auto-permission no existing role has; folding it into
   `GET /api/v1/{table}?distinct=col` reuses the already-granted `table:table:read` permission and
   the same `checkColumn` gating. `Repository.DistinctValues` returns each value plus its row count
   in one query, capped at 500 distinct values.
4. **Saved filters get a dedicated Go package** (`internal/savedfilter`), mirroring
   `internal/notebook` — "private OR shared" visibility is an OR-composed WHERE the generic
   repository's AND-only chain can't express, and rename/delete need an owner check a bare
   column-whitelist handler doesn't do. Two hand-written partial unique indexes give private and
   shared names independent uniqueness scopes.
5. **Per-module customization is a descriptor field**, not a new registry: `ViewDescriptor.search?:
   SearchDescriptor` (`liveFields`, `filterableFields`, `groupableFields`) is plain RSC-safe data,
   validated at registration. A module overriding another's search bar uses the existing view
   extension `setDescriptor` op, widened to include `search`.
6. **The bar lives inside `TreeRenderer`**, in the same slot as the mode switcher, driving the same
   `liveRecords` state Kanban/Calendar already share. Live-typing does up to 3 sequential debounced
   single-column `search[col]=` calls (name, then id, then module-specified fields), merged
   client-side — every match is still a real server-computed `ILIKE` result.

## Consequences

- The live-search leg costs up to 3 sequential round-trips per keystroke (debounced). If that
  proves laggy, the upgrade path is a real backend OR-search endpoint.
- Saved filters are owner-only to rename/delete, even when shared — no admin-override in v1.
- `SavedFilter.Config` is opaque JSON the backend never validates semantically; the frontend
  re-validates against the live descriptor when a saved filter is applied, degrading gracefully if
  a field was since removed or regated.
- `distinct=<column>` shares `table:table:read` rather than deriving its own permission.

## Reference Implementation

`core/orm/internal/crud/repository.go` (`checkColumn`, `filterConditions`, `DistinctValues`),
`core/internal/savedfilter/`, `core/modules/savedfilter/`, `core-front/packages/core-front/src/
views/search-bar.tsx` (`SearchBar`), `views/descriptor.ts` (`SearchDescriptor`).
