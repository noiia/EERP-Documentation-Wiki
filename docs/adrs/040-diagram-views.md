# ADR-040: WBS and PERT diagram view modes

**Status**: Accepted · builds on [ADR-007](007-runtime-view-fields.md) (view fields) and [ADR-011](011-pdf-report-generation.md) (server-side PDF reports)
**Date**: 2026-11-12

---

## Context

The Project app's task lists need two planning views: a **WBS** (work breakdown structure, tasks
nested by parent) and a **PERT** chart (dependency network with a critical path). Both are
node-and-arrow diagrams users arrange by hand, and the arrangement must survive a reload without
being shared with colleagues. Nothing about them is specific to tasks: any entity with a parent
link or a dependency table could use them.

## Decision

### Generic engine modes, enabled by descriptor keys

WBS and PERT are view modes of the core-front engine, like Kanban or Gantt. An entity opts in through
its `viewModeDefaults`:

| Key | Mode | Meaning |
|---|---|---|
| `wbsParentField` | WBS | field holding the parent record (tree edges) |
| `wbsGroupField` | WBS | one tree per value (e.g. `project_id`) |
| `pertDependencies` | PERT | `{entity, fromField, toField}` dependency table, same shape as `ganttDependencies` |
| `pertHoursField` | PERT | estimate in hours (duration) |
| `wbsOrderField` | WBS, PERT | dotted order number (`3.1.2`), optional — see below |

PERT start and end dates reuse `ganttStartField`/`ganttEndField`. The Project task lists set all five keys.

### Order numbers (2026-11-13)

A task's order number says where it sits in the tree: top-level tasks are `1`, `2`, `3`…, the
children of `3` are `3.1`, `3.2`… It exists so the PERT chart can be laid out from the plan's own
order, and so people can name tasks by number.

- **Stored and maintained by Postgres**, not the client: `project_task.sequence` is the position
  among live siblings (kept `1..n`), `wbs_number` the dotted path. Triggers append a new task last,
  shift siblings when a task is placed at a position, close the gap on delete, and renumber the
  descendants. A moved top-level task goes last in its new project.
- **Writing a number moves the task**: a PUT with `wbs_number: "2.4"` makes it the 4th child of the
  task numbered `2` in the same project (`"3"` = 3rd top-level task); an unknown parent number or a
  malformed one is a 422. A re-parent without a number goes last.
- **WBS**: siblings are drawn in number order; a box dropped on a parent, or on empty space among its
  siblings, writes the number for where it landed (one past the siblings left of it) and the diagram
  re-reads every record, since siblings renumber too.
- **WBS lines are the parent links**, edited like PERT arrows (write permission only): drawing a
  line from a box's bottom to another box's top makes the first the parent of the second (a task is
  parent, child or both); deleting a line clears the child's parent (it hangs under its project
  root); dragging a line's end moves the link — the parent end changes the parent, the child end
  gives the parent to the new box and clears the old child's. Each is a plain parent write, so the
  task goes last under its new parent and the diagram re-reads the renumbered records. A project
  root's lines can't be edited; cycles and links across projects are refused before any write.
- **List, Kanban, Calendar, Gantt** show it with the task's name, `1.2 - Design`: a number alone names
  nothing. Display only; the stored value and its sort stay the bare number.
- **PERT** only reads it: within a linked group the auto-layout puts each task at least in the
  column of its top-level number (lowest numbers first, highest last), dependencies still placing a
  blocker left of what it blocks; unlinked tasks get one column per top-level number (see *PERT
  conventions*). Moving a PERT box never changes a number.

Pitfalls: the number is text, so the list's sort on it is lexical (`10` before `2`); the update's
answer can carry the pre-renumber number when the move also renumbered the new parent — re-read.

```mermaid
flowchart LR
    D[descriptor viewModeDefaults] --> E[engine: WBS / PERT renderer]
    E --> C[shared diagram canvas]
    C -->|GET/PUT /api/v1/me/view_layout/:entity/:mode| L[(user_view_layout)]
    C -->|html-to-image + jspdf| X[PNG / PDF download]
    E -->|normal save path| G[generic CRUD]
```

### Per-user layouts

On both canvases, Shift+click adds a box to the selection and Shift+drag on empty space draws a
selection rectangle (React Flow's own keys); dragging a selected box moves the whole selection, each
box landing on the nearest free spot. A group move changes only the layout, never a WBS parent.

Box positions and folded branches are stored per user in `user_view_layout`, through
`GET|PUT /api/v1/me/view_layout/:entity/:mode` (`mode` is `wbs` or `pert`). A second user sees their own
layout, never the first one's. Edits to the records themselves (hours, parent, dependency arrows) are not
layout: they go through the normal save path and follow the caller's write permission (an arrow, the
dependency entity's). A saved layout keeps the positions of boxes not drawn right now (a folded branch, a
narrower filter), so they come back where they were.

### Help

An info button at the start of the canvas toolbar opens a short list of how to use the diagram. It
lists only what this canvas allows (no linking tip without the right to link, the drop-to-re-parent tip
on WBS only, the notes tip where notes are on), so it never describes a gesture that does nothing.

### Notes (PERT)

PERT's **Add note** button drops a free-text box in the middle of the view. A note explains a part of
the plan ("waiting on the supplier's quote") without becoming a record: it is part of the user's own
layout (`notes: [{id, text, links}]` beside `positions`, its position under its own id), so it is
private to that user, needs no write right on the tasks, and never shows in lists or exports of the data.
Dragging between a note's handle and a task box links them (a dashed line, any number per note); a
selected line is removed with Delete, the note with its trash button. The text is saved on blur. A link
to a task not drawn right now stays saved and comes back with the task. Re-arrange leaves notes where
they are. Limits (Go, 400 beyond): 200 notes, 2000 characters and 50 links each. The canvas opts in with
`DiagramCanvas`'s `notes` prop, so WBS could take notes the same way.

### Zoomed-out boxes

Below zoom 0.6 (`DETAIL_ZOOM`) a task box draws only its title (`<order> - <name>`, large type) at
its usual size, and a WBS project root only its name: the form widgets are unreadable there and are
what makes a zoomed-out diagram of hundreds of boxes slow. The box size and handles don't change, so
the layout and the arrows don't move; double-click still opens the record. Each box selects only
"near or far" from React Flow's store, so it re-renders when the zoom crosses the threshold, not on
every zoom step. Zoomed in, only the boxes in a zone around the camera draw in full: the visible area
plus half its width and height on each side (`DETAIL_MARGIN`), so the boxes just off screen are ready
before a pan reaches them; boxes further away stay light until the camera's zone reaches them. An
export always draws the full boxes. The website workflow map drops its arrow
labels below the same zoom.

### Client-side export

PNG and PDF are produced in the browser (`html-to-image` + `jspdf`, loaded on the first export), not through
`internal/reports`. That pipeline renders a server-known print route; the server cannot see the
user's arrangement, which lives in their layout and the current viewport.

### PERT conventions

- 8 hours = 1 day; durations and dates are in calendar days.
- A task with no estimate counts as 1 day and carries a "No estimate" badge.
- Time zero is the earliest start among the drawn tasks.
- Critical = slack < 1e-6 days.
- Dependency rows are read from both ends (`in[toField]` and `in[fromField]`), so a link whose other end is filtered out is counted as a hidden link and not drawn (over the cap, nothing is drawn at all).
- A record whose `closed` field is `true` is drawn faded — the one column name the engine assumes; it still counts in the critical path.
- A dependency cycle disables the critical path, with a warning.
- **Auto-layout** (new boxes and *Re-arrange*, `layoutPert`): linked tasks on the left, each
  connected group of dependencies laid out on its own and the groups stacked top to bottom so
  independent chains never interleave.
  - *Columns*: a blocker sits left of what it blocks; a task with more dependents than blockers
    moves right, next to its nearest dependent, so arrows stay one column long where possible;
    empty columns are dropped. Columns are 100px apart (5 dots of the canvas grid).
  - *Rows*: each task is placed inline with its blockers' mean height (a task nothing blocks, with
    its dependents'), so chains draw as straight lines; a column whose tasks want the same height
    is packed around it with the least total move (a fork centers on its blocker).
  - *Hidden lines*: an arrow spanning several columns is traced as React Flow draws it, and a box
    it would pass behind moves up or down its column to the nearest clear height (a few passes,
    best effort).
  - Unlinked tasks go to their right, after one empty column, one column per top-level order
    number, wrapped into the next column every 10 tasks, centered on the linked part's middle line.
  - Boxes are then separated so none overlap.

### Cap

A diagram draws at most 2000 records; beyond that it shows a notice asking to narrow the filters.

### OBS (organizational breakdown structure)

A third mode, `obs`, draws who is on a project: boxes for contacts, staff users and free text, joined
by parent lines (descriptor key `obs`, type `ObsConfig`: the box entity, the project field, the project entity, the optional
company field, a `canEdit` guard).

- *Shared, not per user.* WBS/PERT boxes are views of records that exist anyway, so each user may
  arrange them privately. An OBS box *is* the data (a `project_obs_box` row with its `x`/`y`), so
  the chart is one shared document: moves, colors and parents are record writes, allowed to the
  project manager and admins only (Go answers 403 to anyone else; the UI hides the editing controls).
- *One pinned project.* The mode is offered only while the list's filters pin the project field to a
  single id; a chart mixing projects has no meaning. A persisted `obs` mode falls back to List when
  the pin is lost.
- *Controlled canvas.* `DiagramCanvas` takes `positions` + `onMove` (a rejected write snaps the box
  back) and never reads or saves a per-user layout in this mode; boxes never placed are laid out like WBS.
- *Colors.* A box has a free `#rrggbb` color; the text color is derived for contrast.
- *Deleting.* Deleting a box clears its children's `parent_id` in the same transaction, so the
  children become roots instead of disappearing.
- *Contacts.* The contact picker offers the project company's people (`contact_company`) when the
  project has a company, else every person. Its last line, *Create a new contact*, opens the
  contact form as a dialog (the relation create wizard, kind preset to person) and links the new
  person to the project's company (`contact_company`), so it is offered next time too.

See also [ADR-041](041-risk-analysis.md): the risk severity reuses these conventions for its critical path.

## Consequences

- Any entity gets the modes by adding descriptor keys, no new code.
- The diagram code (and the export libraries) is lazy-loaded, so lists that never open it pay nothing.

## Pitfalls

- A role without `contact:contact:read` / `users:users:read` sees every contact/user box labelled "Deleted contact" / "Unknown user".
- A box drag only changes the user's layout; a re-parent or arrow change is a real record write and fails for a user without write permission.
- The layout row is replaced whole on each PUT (≤ 5000 ids, finite coordinates within ±10⁶, else 400).
- Hidden-end links silently shrink the critical path; the hidden count is the only hint.
- Export captures the DOM canvas, so it needs the diagram chunk loaded first.
