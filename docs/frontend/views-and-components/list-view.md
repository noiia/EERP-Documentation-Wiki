# List View

The default display mode of a `viewType: 'tree'` descriptor — an MUI X `DataGrid` (with a
`RichTreeView` fallback for genuinely hierarchical data carrying `parent_id`). This is what you get
with zero configuration; Kanban/Calendar/Graph are opt-in modes a workspace admin switches to later.

---

## Minimal descriptor

```ts
const listView: ViewDescriptor = {
  entity: 'crm',
  viewType: 'tree',
  fields: [
    { name: 'name', label: 'Name', type: 'text', required: true },
    { name: 'company', label: 'Company', type: 'text' },
    { name: 'status', label: 'Status', type: 'selection', selection: { options: ['lead', 'customer'] } },
  ],
  permissions: ['crm:contacts:read'],
}
```

No column configuration is needed beyond the field list — every field becomes a DataGrid column in
declaration order, `relation` fields excepted (they render on forms only, never in the list).

## What ships for free

- The [search/filter bar](search-filter-bar.md), mounted automatically inside the same renderer.
- A `CreateBar` tied to the entity's form route and `createPermission`.
- The List/Kanban/Calendar/Graph mode switcher, even if the entity has no Kanban/Calendar field
  configured yet (the corresponding button just stays disabled — see [Settings & Workspace
  Configuration](../../core/settings.md)).
- Soft-delete-aware pagination and, on a destructive row action, the [undo toast](undo-toast.md).

## Customizing what's searchable/filterable/groupable

```ts
const listView: ViewDescriptor = {
  entity: 'crm',
  viewType: 'tree',
  fields,
  search: {
    liveFields: ['name', 'id'],         // live-typing search priority order
    filterableFields: ['status', 'company'],
    groupableFields: ['status'],
  },
}
```

See [Search & Filter Bar](search-filter-bar.md) for the full `SearchDescriptor` shape.

## Navigation label

By default a tree route auto-populates the module's top-bar header menu using its path segment.
Override the label or opt out entirely:

```ts
{ path: '/crm/contacts', descriptor: listView, permission: 'crm:contacts:read' }
// on the descriptor itself:
navLabel: 'Contacts',
hideFromTopBar: false,
```

See [Header Menu & Navigation](header-menu-navigation.md).

## Pitfalls

- A field with `groups` set (see [ADR-014](../../adrs/014-field-level-group-gating.md)) is simply
  absent from the response for a caller outside those groups — don't build UI that assumes every
  declared field is always present in a row.
- `relation` fields never render as list columns. If you need a related record's name in the grid,
  add a computed field (`compute`, see [View Engine → Computed & Reactive
  Fields](../view-engine.md#computed-reactive-fields)) rather than expecting the relation itself to
  flatten into a column.

## Related

- [Kanban View](kanban-view.md) · [Calendar View](calendar-view.md) · [Graph View](graph-view.md) — the other `tree` display modes
- [View Engine → Descriptors](../view-engine.md#descriptors)
- [Search & Filter Bar](search-filter-bar.md)
