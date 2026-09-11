# Views & Components

This section is a practical, per-piece usage guide: one page per view type and one page per major
UI component the `@eerp/core-front` engine ships. Each page answers "how do I use this in a
descriptor," with a real example from a shipped module. For **how the engine derives these from a
descriptor** — the architecture, not the usage — see [View Engine](../view-engine.md).

---

## View Types

Every entity route picks one `ViewType`. `tree` additionally has four **display modes**, switched
by the workspace, never by the descriptor.

| Page | `viewType` | What it renders |
|---|---|---|
| [List View](list-view.md) | `tree` (default mode) | An MUI X DataGrid — the default for any flat or hierarchical entity |
| [Kanban View](kanban-view.md) | `tree` (`Kanban` mode) | Cards grouped into columns by a `selection` field |
| [Calendar View](calendar-view.md) | `tree` (`Calendar` mode) | Cards placed on a date field, drag-to-reschedule |
| [Graph View](graph-view.md) | `tree` (`Graph` mode) or `dashboard` | Drag/resize dashboard tiles (charts, KPIs) |
| [Form View](form-view.md) | `form` | A single-record editor with a synthesized or explicit layout |
| [Catalog View](catalog-view.md) | `catalog` | Icon/title/subtitle rows — an app-picker-style list |
| [Dashboard View](dashboard-view.md) | `dashboard` | A responsive grid of summary widget cards |
| [Report View](report-view.md) | *(reports, not routes)* | A printable PDF layout, same descriptor model as a form |

## Components

| Page | What it is |
|---|---|
| [Relation Widgets](relation-widgets.md) | Search, tags, list, carousel, and summary — the five ways a related record shows up |
| [Address Widget](address-widget.md) | A composite 7-column address field with optional map autocomplete |
| [Totals Widget](totals-widget.md) | A live, computed recap over a set of relation lines (e.g. tax breakdown) |
| [Picture, Signature & File Widgets](picture-signature-file-widgets.md) | Object-storage-backed binary field widgets |
| [Search & Filter Bar](search-filter-bar.md) | The automatic search/filter/group-by bar every list view gets |
| [Chatter Panel](chatter-panel.md) | Per-record comment/activity feed |
| [Form Chrome: Actions Menu, Header Buttons & Status Bar](form-chrome.md) | The always-present form toolbar pieces |
| [Header Menu & Navigation](header-menu-navigation.md) | Per-app top-bar menus and landing-page tiles |
| [Undo Toast](undo-toast.md) | The generic recovery affordance for destructive actions |

## How to read these pages

Each page follows the same shape: what problem it solves, the descriptor fields that control it,
a copy-pasteable example from a real module, and pitfalls worth knowing before you reach for it.
None of these need a custom React component — if you find yourself writing one, that's an [engine
gap](../view-engine.md), not a per-module escape hatch (see [Creating a Frontend
Module](../../developer-guide/creating-a-frontend-module.md)).
