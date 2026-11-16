# Dashboard View

`viewType: 'dashboard'` — a responsive grid of summary widget cards, built on the same tile
machinery [Graph View](graph-view.md) uses for a `tree` entity's Graph mode. The difference is
scope: a dashboard is its own standalone route (a module's landing page, e.g. `/sale` before
drilling into `/sale/quote`), not a display mode of one entity's list.

---

## Descriptor

```ts
const dashboardRoute: ViewDescriptor = {
  entity: 'sale', // used for permission scoping; a dashboard isn't "of" one entity's rows
  viewType: 'dashboard',
  fields: [],
}
```

Per [ADR-019](../../adrs/019-per-model-view-files.md), a module's dashboard route is pulled into
its own export (`dashboardRoute`) in the views assembler and forced **first** in the `FrontModule`'s
`routes` array — the landing tile always opens `routes[0].path`, so getting this order right is
what makes a module's tile open its dashboard rather than a list buried later in the array.

## Count tiles and link tiles

A dashboard shows one count tile per list route of the module; each count is the list envelope's
`total` (a one-row request), not a page length, rendered through `formatTotal`. A tile whose list
failed to load makes the dashboard warn ("Some counts could not be loaded") in its banner slot.
Tiles navigate client-side through `IntentLink`.

`dashboardLinks` adds tiles after the count tiles, same size, for a module page that isn't a list
(the Website app's *Workflows* map):

```ts
dashboardLinks: [
  { title: 'Workflows', description: 'Pages and the buttons between them', icon: 'diagram-project',
    path: '/website/workflows' },
]
```

`title`/`description` are msgids (the module's translation catalog); `icon` is a
`byPrefixAndName.fas` name, so it must be listed in `views/icons.ts`.

## Related

- [Graph View](graph-view.md) — the same tile/aggregation machinery, scoped to one entity's Graph mode instead
- [ADR-019: Per-Model View Files](../../adrs/019-per-model-view-files.md)
