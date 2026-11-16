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
    liveFields: [{ field: 'name' }, { field: 'email', priority: 2 }], // live-search order (lower first)
    filterableFields: ['status', 'company', 'created_at'],  // omitted ⇒ every field
    groupableFields: ['status', 'company'],                 // omitted ⇒ selection/relation/boolean fields
  },
}
```

All lists are plain data, validated at module registration; an entity that declares nothing still
gets a working bar with defaults derived from its fields (live search: name, then id, then other
text/relation fields).

### Relation filters are picked, not typed

A relation field's filter value is chosen from the related records (`RelationFilterInput`: the first
20 on open, then `search[<labelField>]=` as you type; several for `in`). A many2one value, in a filter
chip or a group-by value, shows its record's **label**, never the id (`useRelationLabels`: one
`in[id]=` read per batch of ids).

### Filter-only fields

`search.filterOnlyFields: FieldDescriptor[]` adds fields offered as filters only, never as list
columns, typically a many2many such as a task's *Assignees* or *Color groups*. Its filter is `eq` only
and goes out as `filter[<name>]=<id>`, which **the entity's own list handler must resolve** (the
generic list knows only columns; Project's `TaskFilters` does it for tasks). A name repeating one of
`fields` is refused at registration.

```ts
// core/modules/project/views/project_views.ts
search: { filterOnlyFields: [assigneesField, colorGroupsField] },
```

### Filters from the URL

A list URL's `filter[<field>]=<value>` (filterable fields only) seeds the bar with that exact-match
filter, so a form or a menu can link to a pre-filtered list (`/project/tasks?filter[project_id]=<id>`).
The chip stays removable. A route's `navQuery` (e.g. Project's `?filter[active]=true`) uses this to
give a menu link a default filter the user can drop, unlike a fixed `listFilter`. The new-record form
opened from such a list starts its many2one fields from these values.

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
