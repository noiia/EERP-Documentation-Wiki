# Search & Filter Bar

Every `viewType: 'tree'` route gets a search/filter bar automatically — the same "structural chrome
the engine always provides" posture `CreateBar` and the display-mode switcher take. No opt-in is
needed; `search` on the descriptor only *customizes* it. See
[ADR-015](../../adrs/015-search-filter-bar.md) for the full design.

---

## What it does

- **Live-typed search** — up to three sequential debounced single-column requests (name, then id,
  then module-specified fields), merged client-side. Every match is still a real server-computed
  `ILIKE` result (see [ORM → Query Parameters](../../core/orm.md#query-parameters-generic-crud)) —
  nothing is filtered client-side.
- **Structured filters** — a dropdown of `eq`/`contains`/`in`/`gt`/`gte`/`lt`/`lte` conditions
  against any filterable field, rendered as always-visible chips.
- **Group-by** — reflects a field's actual distinct values (via `?distinct=<column>`), not a
  predeclared static list, unlike Kanban's fixed status columns.
- **Saved filters** — a user can save a filter+group-by combination privately or share it
  tenant-wide (see [Record-Anchored Services → Saved Filters](../../core/record-anchored-services.md#saved-filters)).
  Deleting a saved filter shows the [undo toast](undo-toast.md).

## Customizing per entity

```ts
const listView: ViewDescriptor = {
  entity: 'crm',
  viewType: 'tree',
  fields,
  search: {
    liveFields: ['name', 'id', 'email'],  // live-search priority order
    filterableFields: ['status', 'company', 'created_at'],
    groupableFields: ['status', 'company'],
  },
}
```

All three lists are plain data, validated at module registration — an entity that declares nothing
still gets a working bar with sensible defaults derived from its fields.

## Field-level group gating applies here too

A field gated via `orm.WithFieldGroups` (see [ADR-014](../../adrs/014-field-level-group-gating.md))
is invisible to filtering, searching, *and* group-by for a caller outside its groups — the exact
same server-side `Repository.checkColumn` check the response body already goes through. There's no
separate opt-in for this; gating a field once covers both surfaces.

## Overriding another module's search bar

A module extending a base module's view (see [View Engine → View
inheritance](../view-engine.md#view-inheritance-extends)) can replace the `search` block wholesale
via the existing `setDescriptor` extension operation — it's a whole-block replace, not a deep
merge, the same as the other patchable descriptor keys.

## Pitfalls

- Live search costs up to three sequential round trips per keystroke (debounced) — if this proves
  laggy for a very large table, the documented upgrade path is a real backend OR-search endpoint,
  not built today.
- `distinct=<column>` shares the entity's existing `table:table:read` permission rather than a
  dedicated one — group-by can't be gated more narrowly than ordinary reads without a future,
  separate permission design.

## Related

- [List View](list-view.md) — where the bar mounts
- [Record-Anchored Services → Saved Filters](../../core/record-anchored-services.md#saved-filters)
- [ADR-015: Search/Filter Bar](../../adrs/015-search-filter-bar.md) · [ADR-014: Field-Level Group Gating](../../adrs/014-field-level-group-gating.md)
