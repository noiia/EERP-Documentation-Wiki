# ADR-021: Graph calculated fields and multi-line charts

**Status**: Accepted
**Date**: 2026-09-20

---

## Problem
Graph tiles could only plot columns that exist on the entity. Users want derived figures
(e.g. `rent_price - loan_amount`) and several lines on one xy chart, without a schema change.

## Decision
- A **calculated field** is a row in `graph_field` (`internal/graphfield`), scoped to one entity's
  Graph view, holding an infix formula and an optional role list. It is created and deleted from the
  Graph view's edit mode (left-hand list, delete button on hover).
- The formula is **evaluated in the browser** over the already-fetched records and injected as a plain
  numeric column (`withCalculatedFields`), so every tile type and picker treats it like a real field.
  Because records reach the browser after field-level gating (ADR-014), a formula cannot expose a
  gated column.
- **Security:** `roles` filters the list and guards delete server-side. Formula text is charset-checked
  on write; it is never `eval`'d.
- **Delete** is a hard delete (`HardDelete`): the row and its unique-index entry disappear. Tiles keep
  the dangling `calc_*` key in their config and read it as `0`.
- **Multi-line:** xy/bar tile config gains `yFields: string[]`; `xySeries` emits one series per entry.
  `seriesField` (split by a category) still wins if both are set.

## Consequences / pitfalls
- Aggregation is client-side over the current page (same limit as every Graph tile — see
  `docs/roadmaps/list-view-modes.md`). A formula is aggregated *after* per-record evaluation
  (sum of `a-b`, not `sum(a)-sum(b)`; equal for sum, not for avg of ratios).
- Calc-of-calc resolves in creation order; a forward reference reads 0.
- Roles are typed as technical names (no picker yet).
- **Dated variables:** a variable created with "Date variable" is computed once per dated child row
  instead of once per listed record. The entity flags that relation with
  `ViewDescriptor.graphDatedRows: {entity, link}` on the list descriptor the graph renders (property → its parent rent receipts; not on a form relation field, which the list descriptor does not carry). For a tile that uses such
  a variable the graph fetches those rows (`in[<inverse fk>]=<ids>`), replaces each property by one row per
  receipt (`expandByChildren`: receipt columns such as the snapshotted `rent_price` win, the property's own
  `loan_amount` carries over, properties with no receipt drop out) and evaluates every variable per row.
  Tile config `datedMode: "lastPerDay"` keeps only the latest receipt per property per day; default is every
  receipt. Child rows are fetched with a single page of 1000 — beyond that the chart is truncated.
- `PropertyManagement.generated_at` (latest parent receipt's date, copied on Generate and backfilled)
  gives the property's own graph an X date field for tiles that don't use a dated variable.
- Edit-mode left column: "+ Add widget", then a Variables bloc ("+ Add field" first, one sub-bloc per
  calculated field, × on hover).
