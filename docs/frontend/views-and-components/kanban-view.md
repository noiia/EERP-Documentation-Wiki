# Kanban View

A display mode of `viewType: 'tree'`: cards grouped into columns by a status field. There is no
separate Kanban descriptor; any tree view becomes Kanban-capable once its status field resolves,
either from the module's own `viewModeDefaults` or from a workspace admin's choice.

---

## How the status field is chosen

Which field backs the columns is resolved from two sources, merged by `effectiveViewFields()`:

1. the module's optional baseline, `ViewDescriptor.viewModeDefaults.kanbanStatusField`;
2. the workspace admin's **runtime override** in Settings → Apps → *module* → Views
   (`app_settings` key `views.<entity>.fields`), which always wins when non-null.

A `null` override means "not overridden", not "off". See
[ADR-007](../../adrs/007-runtime-view-fields.md) and
[Settings & Workspace Configuration](../../core/settings.md).

```ts
// A selection field is enough: its options become the columns, in declared order.
{ name: 'status', label: 'Status', type: 'selection',
  selection: { options: ['incoming', 'running', 'won', 'lost', 'closed'] } }
```

With a **selection** status field, every column is exactly one option, in declared order, plus a
trailing "No status" column for records with a null value. There is no per-column visibility
toggle: declare a low-priority status such as `archived` **last** so it lands at the end.

## Many2one columns

A **many2one** status field takes its columns from the related entity's records instead, when the
module declares `viewModeDefaults.kanbanColumns` (module-declared only; Settings → Views offers a
many2one as a status field only then). The Project app's task board uses it for its stages:

```ts
// core/modules/project/views/project_views.ts
viewModeDefaults: {
  kanbanStatusField: 'stage_id',
  kanbanColumns: {
    orderField: 'sequence',          // column order
    labelField: 'name',              // column title
    foldField: 'closed',             // truthy ⇒ the column shows collapsed (header + count)
    scopeField: 'project_id',        // one column per stage when the list is filtered to one project
    canEdit: 'project.canEditStages', // name of a registered guard
  },
  kanbanBadgeField: 'blocked',       // boolean: an error chip on cards where it is true
}
```

- Columns are loaded through `RelationOps.listPage` (`order=<orderField>`, 200 at a time until a
  short page; a safety stop at 2000 records shows the first ones with a warning).
- When the list's filter pins `scopeField` to one id, there is one column per related record.
  Otherwise columns are **merged by label** across scopes: a merged column reads its cards with
  `in[<status>]`, and a dropped card takes the column record of its own scope, or is refused with
  "No column named {name} exists for this card."
- On a scoped board, when the guard registered under `canEdit`
  (`registerKanbanColumnsGuard(name, (scopeId, relationOps) => Promise<boolean>)`) resolves true,
  the board offers *Add column*, per-column rename and header drag-reorder (rewriting `orderField`
  as 10, 20, …). A failed column write shows as an error banner and re-reads the columns.
- A card's many2one fields show the related record's label, never its id.

## Counts and paging

Each column fetches its first 50 cards (`KANBAN_COLUMN_LIMIT`) with its real total in the header and
a "+N more" caption. Counts come from the server, never from a loaded page; a total above 10 000 is
Go's estimate and renders through `formatTotal` (see [List Read Performance](../../core/list-performance.md)).
The search bar's structured filters apply to every column.

## Moving cards

Dragging a card to another column PATCHes the status field through the same `actions.update`
Server Action the form's Save uses, optimistically, with a revert and an error banner on refusal
(`useOptimisticFieldMove`, shared with Calendar and Gantt). A card ignores new moves while its own
write is pending, and a refused write restores only that card's patched fields. Without
`<entity>:<entity>:write` nothing drags; a click opens the form. Kanban uses HTML5 drag and drop and
has no keyboard path yet.

## Quick create

With `<entity>:<entity>:write`, a click on an empty spot of a column opens the entity's own form as a
dialog (the relation create wizard), pre-filled with that column's status and the many2one values
the list is filtered on (a project's task board creates tasks in that project). A merged many2one
column, or *No status*, leaves the status to the form. The new card is added in place. Clicks on
cards, buttons and inputs never count.

## Color ribbons

When the module declares `viewModeDefaults.colorTagsField` (a many2many to records carrying a
`color`, e.g. a task's *Color groups*), each card gets a 4px ribbon along its top edge, in equal
segments for several colors. See [Gantt View](gantt-view.md#color-groups) for how colors are read
and cached.

## An entity with no status field

Kanban is **omitted** from the mode switcher (not shown disabled) until its status field resolves.
A fresh module ships with List working immediately and Kanban/Calendar/Graph as later, optional
configuration. A mode persisted in the browser that has since been turned off falls back to List.

## Related

- [List View](list-view.md) · [Calendar View](calendar-view.md) · [Gantt View](gantt-view.md) · [Graph View](graph-view.md)
- [ADR-007: Runtime-Configurable View Fields](../../adrs/007-runtime-view-fields.md)
- [Project App](../../core/project.md): the many2one board's reference consumer
