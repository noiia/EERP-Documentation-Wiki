# Project App

`core/modules/project` (`type: go`, `app_mode: true`, `depends: [auth, contact]`): projects, kanban
stages, tasks with subtasks, dependencies, milestones, tags, color groups, assignees, timesheets,
an OBS chart and a risk register. It is the first user of [row scope](orm.md#row-scope)
([ADR-039](../adrs/039-row-level-access.md)).

## Visibility

A project is seen when `visibility = 'everyone'` (default), or the caller is its manager, or a live
member. A members-only project's children follow it, except that a task **assignee** still sees that
task. Admins (`project_admin` group or `project:project:admin`) skip the scope. Hidden records are 404.

## Server-maintained values

Postgres triggers own the aggregates (`task_count`, `spent_hours`, subtask counts, `blocked`,
`closed`, milestone counts) and new projects' default stages (New / In progress / Done). Never write
them by hand.

### Order numbers

Each task's `wbs_number` (`3.1.2`) and `sequence` are maintained by triggers. Writing `wbs_number`
moves the task to that parent and position (422 for an unknown parent number). Lists show
`<order> - <name>`.

## Write rules

Managing a project (PUT/DELETE, members, stages) is manager/admin only (403). Cycles in parents or
dependencies are 422; deleting a project with live tasks, or a stage holding tasks, is 409.
`POST /api/v1/project/:id/restore` brings back the stages, milestones and members deleted with it.
A task PUT changing `project_id` moves it with its subtasks.

Extra list filters: `filter[assignee]=me`, `filter[assignees]=<user>`, `filter[color_groups]=<color>`.

## Views

Task lists offer List, Kanban (stages as columns), Calendar, Graph,
[Gantt](../frontend/views-and-components/gantt-view.md),
[WBS, PERT and OBS](../frontend/views-and-components/diagram-views.md) and
[Risk](../frontend/views-and-components/risk-view.md).

## Risk analysis

`project_risk` (AMDEC row: likelihood, detectability, computed or manual severity, generated
`criticity`), `project_risk_task` and `project_risk_category`. Severity is recomputed on every
`GET /api/v1/project_risk`; pin `filter[project_id]` on large tenants. See
[ADR-041](../adrs/041-risk-analysis.md).

## Pitfalls

- Typed `Repository[T]` reads bypass the row scope; row-scoped tables are never read-cached.
- Project roles need `users:users:read` for the user pickers.
- Permission checks cache 5 minutes, so revoking admin lags.
