# Graph View

A display mode of `viewType: 'tree'` (or a standalone `viewType: 'dashboard'`) — drag/resize tiles
(charts, KPI numbers, aggregates) built on `react-grid-layout`. Like Kanban and Calendar, tile
*layout* is a per-workspace admin setting, not descriptor data.

---

## Storage

A Graph mode's tile layout lives in `app_settings` under `views.<entity>.graph`
(`GET|PUT /api/v1/settings/views/:entity/graph`) — see [Settings & Workspace
Configuration](../../core/settings.md). Reading an unconfigured entity's Graph settings returns an
**empty canvas**, not a 404: a fresh entity starts with nothing laid out, and an admin adds tiles
from the UI.

The backend validates each tile's shape (a stable id, non-negative/non-zero geometry, a closed set
of tile types, no duplicate ids) but never inspects a tile's own opaque `config` — the same "the
backend owns shape, never semantics" posture `SavedFilter.Config` and `report_page_format` take
elsewhere in the codebase.

## Aggregation

Tile data is computed client-side from the entity's already-fetched records
(`graph-aggregate.ts`) — sums, counts, and group-bys over whatever the tree view's live record set
already holds, not a separate backend aggregation endpoint. This keeps a Graph tile consistent with
whatever filters the [search bar](search-filter-bar.md) currently has applied.

## Layout persistence

Dragging or resizing a tile calls `applyRGLLayout`, which patches just that tile's geometry in the
stored layout and persists via the same settings endpoint — every viewer with edit rights sees
their own arrangement, since the setting is per-company (see
[ADR-013](../../adrs/013-multi-company.md)), not per-user.

## Related

- [Kanban View](kanban-view.md) · [Calendar View](calendar-view.md)
- [Dashboard View](dashboard-view.md) — the standalone (non-tree) sibling of this same tile machinery
- [Settings & Workspace Configuration](../../core/settings.md)
