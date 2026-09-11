# Calendar View

A display mode of `viewType: 'tree'` — cards placed on a `date` field, draggable to reschedule.
Like Kanban, which field backs the Calendar is a per-workspace admin setting
(`views.<entity>.fields`), not descriptor data — see [ADR-007](../../adrs/007-runtime-view-fields.md).

---

## Drag behavior

Every drag in the Calendar renderer (and in Kanban) acts **immediately** and reverts on error —
there is no blocking "are you sure?" confirmation. Dragging a record off the calendar grid clears
its date field the same way; because that's a destructive-feeling action, it's the one place in
the engine that shows the [undo toast](undo-toast.md) rather than acting silently (see
[ADR-016](../../adrs/016-undo-toast.md)).

```ts
// Nothing calendar-specific in the descriptor — any `type: 'date'` field is eligible:
{ name: 'execution_date', label: 'Run at', type: 'date' }
```

Settings → Views only offers `type: 'date'` fields as Calendar candidates, mirroring Kanban's
`type: 'selection'` restriction.

## Card coloring

`ViewModeDefaults.calendarColorField?: string` names a boolean field whose `true` value tints a
card — a fixed, module-declared hint, not a workspace preference (no runtime override path exists,
unlike the date-field picker above). [Cron](../../core/cron.md) is the reference example: a failed
run's card renders red.

```ts
// on the FrontModule route's descriptor:
viewModeDefaults: { calendarColorField: 'failed' }
```

See [ADR-017: Background Cron Scheduler](../../adrs/017-cron-scheduler.md) for why this shipped as
a generic engine primitive instead of a cron-only special case.

## Related

- [Kanban View](kanban-view.md) · [Graph View](graph-view.md)
- [Undo Toast](undo-toast.md)
- [ADR-007: Runtime-Configurable View Fields](../../adrs/007-runtime-view-fields.md)
- [Background Cron Scheduler](../../core/cron.md) — the `calendarColorField` reference consumer
