# Kanban View

A display mode of `viewType: 'tree'` — cards grouped into columns by a `selection` field's
options. There is no separate Kanban descriptor; any tree view becomes Kanban-capable the moment
its entity has at least one `selection` field, and a workspace admin picks which one.

---

## How the status field is chosen

Unlike a typical framework where a component takes a `groupBy` prop, EERP deliberately keeps this
**out of the descriptor**: which field backs Kanban's columns is a per-workspace admin setting
(`views.<entity>.fields`, Settings → Views), not something a module hardcodes. See
[ADR-007](../../adrs/007-runtime-view-fields.md) for why, and [Settings & Workspace
Configuration](../../core/settings.md) for the storage.

```ts
// The descriptor only needs a selection field to exist — nothing Kanban-specific:
{ name: 'status', label: 'Status', type: 'selection',
  selection: { options: ['incoming', 'running', 'won', 'lost', 'closed'] } }
```

Once a workspace picks `status` as the Kanban field (via Settings → Views, which only offers
`type: 'selection'` fields), every column is exactly one option, in declared order, plus a
trailing "No status" column for records with a null value. **There is no per-column visibility
toggle** — if you want a status like `archived` to read as low-priority, declare it **last** in
`options` so it lands as the trailing column; there's no way to hide it outright (see
[ADR-017](../../adrs/017-cron-scheduler.md)'s own "archived isn't hidden" note for a worked
example of this exact tradeoff).

## Card coloring

A boolean field can tint a card via `ViewModeDefaults.calendarColorField` — despite the name, this
mechanism is shared between Calendar and, by convention, could be reused for Kanban if a future
need arises; today it's Calendar-only (see [Calendar View](calendar-view.md)).

## An entity with no configured field

Reads as a normal, working state — the Kanban button is present but disabled until an admin picks
a field in Settings → Views. This is deliberate: a fresh module ships with List working
immediately, Kanban/Calendar/Graph as later, optional admin configuration.

## Related

- [List View](list-view.md) — the default mode every tree view starts in
- [Calendar View](calendar-view.md) · [Graph View](graph-view.md)
- [ADR-007: Runtime-Configurable View Fields](../../adrs/007-runtime-view-fields.md)
- [Settings & Workspace Configuration](../../core/settings.md)
