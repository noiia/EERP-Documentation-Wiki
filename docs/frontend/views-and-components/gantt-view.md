# Gantt View

A display mode of `viewType: 'tree'` (`gantt-renderer.tsx`): one row per record, a bar from its
start date to its end date on a timeline. Bars drag, resize and move with the keyboard; dependency
arrows and color groups are opt-in.

---

## Enabling it

Gantt shows in the mode switcher once **both** a start and an end field resolve, from the module's
`viewModeDefaults` or from a workspace override (`gantt_start_field` / `gantt_end_field` in
`views.<entity>.fields`, two date-field pickers in Settings → Views; the override wins when non-null).

```ts
// core/modules/project/views/project_views.ts (task lists)
viewModeDefaults: {
  ganttStartField: 'date_start',
  ganttEndField: 'deadline',
  ganttDependencies: { entity: 'project_task_dependency', fromField: 'depends_on_id', toField: 'task_id' },
  colorTagsField: 'color_groups',
}
```

## The timeline

- Rows are labeled by the record's `name`/`title` field, else the first field in layout order
  (never an order number).
- Three zooms: **Day** (2 weeks), **Week** (12 weeks, the default), **Month** (6 months), with
  previous / today / next buttons. The zoom picked is kept per entity in `sessionStorage`
  (`eerp.gantt.zoom.<entity>`) for the tab's session.
- **Shift + mouse wheel** over the timeline moves it a week per notch (a month in Month zoom).
- A red line marks today when it is in range.
- Records are **server-paged**: only those overlapping the visible range load (`lt[start]` = day
  after the range, `gte[end]` = its first day, a tighter search-bar bound being kept), ordered by
  start, 200 per page, stopping at 1000 with a caption.
- Records missing either date list in an **Unscheduled** panel (50 each, via `empty[start]` and
  `empty[end]`).

## Moving bars

| Gesture | Effect |
|---|---|
| Drag a bar's body | shifts both dates by whole days |
| Drag an edge handle | moves one date (the end never goes before the start) |
| Drag a bar off the timeline | unschedules it: the start is cleared (the end, e.g. a deadline, is kept), with the [undo toast](undo-toast.md) |
| Drag an Unscheduled card onto a day | start = that day; the end is kept when not before it, else = start |
| ← / → on a focused bar | move a day |
| Shift + ← / → | resize the end |
| Alt + ← / → | resize the start |
| Enter | open the form |

Each bar is a focusable button labeled `<label>: <start> – <end>`, so Gantt has the keyboard path
Kanban and Calendar still lack. Writes go through `useOptimisticFieldMove`'s `moveFields`: one
PATCH, one revert on refusal. A `date` field is written back as `YYYY-MM-DD`, a `datetime` one as a
UTC instant keeping its local time of day. While a bar's own write is pending it ignores new moves.
Without `<entity>:<entity>:write` nothing moves; a click or Enter opens the form. Pointer events
cover mouse and touch.

**Quick create**: with write permission, a click on an empty spot of a row's track opens the form as
a dialog with start = end = that day, plus the many2one values the list is filtered on.

## Dependency arrows

`viewModeDefaults.ganttDependencies: { entity, fromField, toField }` (module-declared only) draws an
SVG arrow from the blocker's (`fromField`) bar end to the dependent's (`toField`) bar start, for
links whose two records are both on screen (clipped bars draw to the range edge). Links are read
with `in[toField]` = visible row ids, 100 per request, and read again only when the set of row ids
changes. A refused read draws no arrows.

## Color groups

`viewModeDefaults.colorTagsField` names a many2many field (of the list descriptor, else of the
entity's form descriptor) whose related records carry a `color`:

- a bar is filled with its color, or equal hard-edged horizontal stripes for several (bars carry no
  text, so no color can hide a label);
- a palette button beside each row's name (`<entity>:<entity>:write` only) opens the
  [`relation/colortags`](relation-widgets.md#color-tags) widget for that record;
- Kanban and Calendar cards get a 4px ribbon in the same colors.

Colors are read by `useRecordColors`: junction rows by chunks of 100 ids (`order=created_at`, the
order stripes follow), then the related records. The last colors read are kept for the tab's
session (`record-colors-store.ts`, `sessionStorage`) and drawn at once on the next display while a
background read replaces them (stale-while-revalidate). The cache belongs to the signed-in user and
is wiped at logout.

## Related

- [Kanban View](kanban-view.md) · [Calendar View](calendar-view.md) · [Diagram Views](diagram-views.md)
- [Project App](../../core/project.md): the reference consumer
