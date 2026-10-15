# Graph View

A display mode of `viewType: 'tree'` (or a standalone `viewType: 'dashboard'`): a canvas of
drag/resize **tiles** — charts, KPI numbers, lists — built on `react-grid-layout`. Like Kanban and
Calendar, the tile *layout* is a per-workspace setting, not descriptor data.

The Graph button appears once graphs are enabled for the entity — `viewModeDefaults.enableGraphs`
in the module, or the workspace override in Settings → Apps → *module* → Views.

## Tile types

| Type | Shows | Config highlights |
|---|---|---|
| `xy` | smoothed line chart over a date axis | X date field, `bucket` day/week/month, `yFields` (several lines) or legacy `yField`, aggregate sum/avg/count, optional `seriesField` (one line per value) |
| `bar` | grouped or stacked bars over the same data | as `xy`, plus `mode: 'grouped' \| 'stacked'` |
| `pie` | donut + legend | group field; slices **always sized by record count** (a `valueField` only annotates the tooltip); small slices fold into "Other" |
| `stat` | one big number | mean / median (a real middle value) / sum / count |
| `list` | a filtered list of records | a real server query (`filter[col]=value`) |

Charts use the engine's light/dark categorical palette and animate in. On an `xy`/`bar` axis a
value far from all others (beyond 3 × IQR **and** more than one axis span away) doesn't stretch
the scale: it is drawn cropped — an arrowhead on the plot edge with its value written beyond it,
the axis marked broken there.

## Aggregation: server first

When the host binds `GraphOps.aggregate` (the shell does), `xy`/`bar`/`pie`/`stat` tiles are
aggregated **by Postgres over every matching row**: the tile config becomes
`GET /api/v1/<entity>?aggregate=…` requests carrying the search bar's filters and the
descriptor's `listFilter` ([ADR-024](../../adrs/024-graph-server-aggregation.md)), reassembled into
the same shapes the widgets draw.

The client-side path (`graph-aggregate.ts`, over the records already loaded) remains the fallback:
no host support, a failed call, `list` tiles, or a tile using a dated calculated field. It shows a
**partial data** badge whenever the record total exceeds what was loaded.

## Calculated fields

From edit mode, a user can define a named formula — field keys, other calculated fields, numbers,
`+ - * /`, parentheses (`rent_price - loan_amount * 0.5`) — that every tile type can plot like a
real column. Stored per entity in `graph_field` (`GET|POST /api/v1/graph_fields`,
`DELETE …/:id`), optionally restricted to roles; evaluated by a hand-rolled parser (never `eval`),
or compiled to SQL for server aggregation. An unknown or gated identifier reads 0 — which is also
how a deleted field "becomes 0" in tiles that used it. See
[ADR-021](../../adrs/021-graph-calculated-fields.md).

## Editing and storage

- **Edit** (needs `settings:views:write`) opens a draft: drag, resize, "+ Add widget", ✎ to
  reconfigure a tile; **Save** or **Cancel**. The config dialog only offers valid field choices and
  explains why Add is disabled.
- × hides a tile (`hidden: true`); it waits in a *Hidden widgets* row to be restored.
- Layouts live in `app_settings` `views.<entity>.graph`
  (`GET|PUT /api/v1/settings/views/:entity/graph`, per company). An unconfigured entity reads as an
  empty canvas. Go validates each tile's shape, never its opaque `config`.
- In read mode the grid shrinks to the columns the tiles use and is **centered**; in edit mode it
  spans the page so empty columns can receive tiles.
- Below 600 px the canvas is a read-only single column of the saved tiles — a phone visit can never
  rewrite a desktop layout.

Modules can seed a starting layout (the Event app does), and the full demo seed gives every large
list a Graph view ([Demo Data](../../core/demo-data.md)).

## Related

- [Kanban View](kanban-view.md) · [Calendar View](calendar-view.md) · [Dashboard View](dashboard-view.md)
- [Settings & Workspace Configuration](../../core/settings.md) · [ORM → Query parameters](../../core/orm.md#query-parameters-generic-crud)
