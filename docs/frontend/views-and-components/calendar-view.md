# Calendar View

A display mode of `viewType: 'tree'`: cards placed on a date field, draggable to reschedule.
Like Kanban, the field comes from the module's `viewModeDefaults.calendarDateField` or a workspace
admin's override (`views.<entity>.fields`, which wins when non-null). See
[ADR-007](../../adrs/007-runtime-view-fields.md).

---

## What it shows

A month grid (the current month's own days only: no adjacent-month filler, no week or day view)
positioning records by their date field, plus an **Unscheduled** panel for records with none.
The visible month is fetched with a `gte`/`lt` range on the date field (up to
`CALENDAR_MONTH_LIMIT`, with a "shown this month" caption past it) and the unscheduled records with
`empty[<date>]`, again on every month change. Counts render through `formatTotal`.

```ts
// Nothing calendar-specific in the descriptor: any date field is eligible.
{ name: 'execution_date', label: 'Run at', type: 'date' }
```

Settings → Views offers only date fields as Calendar candidates.

## Drag behavior

Every drag acts **immediately** and reverts on error; there is no confirmation. Dropping a card on
the Unscheduled panel clears its date field and shows the [undo toast](undo-toast.md)
([ADR-016](../../adrs/016-undo-toast.md)). Writes go through `useOptimisticFieldMove`, shared with
Kanban and Gantt: a card ignores new moves while its write is pending, and a refusal restores only
that card's fields. Without write permission nothing drags. There is no keyboard path yet.

## Quick create

With `<entity>:<entity>:write`, a click on an empty spot of a day opens the entity's form as a
dialog, pre-filled with that date and the many2one values the list is filtered on. The created
record is added in place.

## Card coloring

- `ViewModeDefaults.calendarColorField?: string` names a boolean field whose `true` value gives the
  card a red accent. It is module-declared only (no runtime override). [Cron](../../core/cron.md) is
  the reference example: a failed run's card renders red.
- `ViewModeDefaults.colorTagsField` adds a 4px color ribbon on top of each card, one segment per
  color group (see [Gantt View](gantt-view.md#color-groups)).

```ts
viewModeDefaults: { calendarColorField: 'failed' }
```

## Related

- [Kanban View](kanban-view.md) · [Gantt View](gantt-view.md) · [Graph View](graph-view.md)
- [Undo Toast](undo-toast.md)
- [ADR-007: Runtime-Configurable View Fields](../../adrs/007-runtime-view-fields.md)
