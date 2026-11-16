# Risk View & Mind-Map Widget

The **Risk** display mode (`views/risk/*`) shows a project's AMDEC (FMEA) risk register as three
tabs: a criticity matrix, an Ishikawa diagram and the register itself. The backend model and the
scoring rules are in [ADR-041](../../adrs/041-risk-analysis.md) and
[Project App](../../core/project.md#risk-analysis).

---

## Enabling it

```ts
// core/modules/project/views/project_views.ts (task lists)
viewModeDefaults: {
  risk: {
    entity: 'project_risk',
    linkEntity: 'project_risk_task',
    categoryEntity: 'project_risk_category',
    projectField: 'project_id',
    formPath: '/project/risks/:id',
  },
}
```

Like OBS, the mode is offered only while the list is pinned to one project
(`/project/tasks?filter[project_id]=<id>`).

## The tabs

- **Matrix**: likelihood × severity grids, before and residual, stretched to the view. A cell
  holding at most three risks names them (`6 - Budget cut`); a busier one shows only the criticity.
  Bands: criticity up to 4 green, up to 12 amber, above 12 red.
- **Ishikawa**: a fishbone by category, scaled to fit, long labels cut (full text as tooltip).
- **Register**: the table of risks with their scores.

A *New risk* button opens the risk form as a dialog with the project preset. The matrix and the
Ishikawa export to PNG/PDF through `views/diagram/export.ts`.

## The risk form

Severity is computed by the server for `delay` and `cost` risks (`severity_computed`) and can be
overridden by a manual `severity`; a severity that can't be computed shows a readable note
(`no_estimate`, `cycle`, `no_planned_hours`). The form's linked-task grid edits
`project_risk_task` rows with their `delay_days` / `extra_hours`.

!!! warning "Known v1 limit"
    The linked-task grid shows raw task ids and its task picker is not limited to the risk's
    project; Go still refuses a task of another project.

## Mind-map widget (`text/mindmap`)

The risk form's header is a read-only mind-map: a centre box with satellites around it.

```ts
// core/modules/project/views/project_views.ts (risk form)
{
  name: 'risk_map', label: 'Risk map', type: 'text', widget: 'mindmap',
  store: false, readOnly: true, hideLabel: true,   // a virtual field: nothing is saved
  widgetOptions: {
    center: 'name',                                // the field shown in the centre box
    satellites: [
      { field: 'category_id', label: 'Risk category', entity: 'project_risk_category' },
      { field: 'description', label: 'Risk type' },
      { field: 'phase_task_id', label: 'Project phase', entity: 'project_task' },
    ],
  },
}
```

Each satellite is `{field, label, under?, entity?, labelField?}`; a many2one satellite needs
`entity`. Malformed satellites are ignored. The mind-map exports to **PNG only**.

## Related

- [Diagram Views](diagram-views.md) · [Gantt View](gantt-view.md)
- [ADR-041: Project Risk Analysis](../../adrs/041-risk-analysis.md)
