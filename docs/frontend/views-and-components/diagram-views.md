# Diagram Views: WBS, PERT & OBS

Three display modes of `viewType: 'tree'` draw records as boxes and lines on a shared canvas
(`DiagramCanvas`, React Flow based, lazy-loaded):

| Mode | Shows | Layout stored |
|---|---|---|
| **WBS** | records nested by a parent field, one tree per group | per user |
| **PERT** | the dependency network, with durations and the critical path | per user |
| **OBS** | who works on one project: contacts, staff users and text boxes | shared, as records |

The design is recorded in [ADR-040](../../adrs/040-diagram-views.md); this page is the usage guide.

---

## Enabling the modes

All keys are module-declared only (never overridable by a workspace admin):

```ts
// core/modules/project/views/project_views.ts (task lists)
viewModeDefaults: {
  wbsParentField: 'parent_id',      // WBS: parent link (tree edges)
  wbsGroupField: 'project_id',      // WBS: one tree per project
  wbsOrderField: 'wbs_number',      // optional dotted order number (3.1.2)
  pertDependencies: { entity: 'project_task_dependency', fromField: 'depends_on_id', toField: 'task_id' },
  pertHoursField: 'planned_hours',  // PERT duration; dates reuse ganttStartField/ganttEndField
  obs: { entity: 'project_obs_box', projectField: 'project_id', projectEntity: 'project',
         companyField: 'company_id', canEdit: 'project.canEditStages' },
}
```

WBS shows when `wbsParentField` is set, PERT when `pertDependencies` is set. OBS is offered only
while the list's filters pin `projectField` to one id; a persisted OBS mode falls back to List when
the pin is lost.

## Order numbers

With `wbsOrderField`, List columns, Kanban cards, Calendar labels and hierarchy tree items show
records as `<order> - <name>` (`1.2 - Design`). WBS sorts siblings by the number, and a box dropped
among siblings writes the number for where it landed, then re-reads every record (siblings
renumber too). The numbers are stored and maintained by the backend (see
[Project App](../../core/project.md#order-numbers)).

## Canvas gestures

| Gesture | WBS | PERT | OBS |
|---|---|---|---|
| Drag a box | layout only (or a re-order/re-parent drop) | layout only | moves the shared box (manager/admin) |
| Draw a line between handles | sets the child's parent | adds a dependency | sets the parent |
| Drag a line's end | moves the parent link | re-ends the dependency | moves the parent link |
| Select a line + Delete | clears the parent | removes the dependency | clears the parent |
| Drop an unlinked box on a line A → B | inserts it: A → box → B | inserts it | inserts it |
| Shift+click / Shift+drag rectangle | multi-select; a group move is layout only | same | same |

- While an unlinked box is dragged over a line, that line is highlighted with a "+". PERT creates
  the two new dependency rows before removing the old one, so a refusal keeps the old arrow.
- Every line or parent change is a real record write and follows the caller's write permission.
  Cycles and links across groups are refused before any write.
- An info button (`DiagramHelp`) lists only the gestures this canvas allows.
- **Undo / redo**: Ctrl/Cmd+Z, Ctrl/Cmd+Y or Ctrl/Cmd+Shift+Z (not while typing), and the toolbar
  buttons, replay box moves, link and parent changes, inserts, box field edits, WBS order drops,
  OBS colors, text edits and box creation/deletion (undoing a delete re-creates the box and puts its
  former children back under it). Notes are not in the history. A failed step is dropped and shown
  as an error; at most 100 steps are kept.

## Per-user layouts (WBS, PERT)

Box positions, folded branches and PERT notes are stored per user through
`GET|PUT /api/v1/me/view_layout/:entity/:mode` (`mode` = `wbs` | `pert`; see
[Settings](../../core/settings.md)). A colleague sees their own layout, never yours. A saved layout
keeps positions of boxes not drawn right now, so they come back where they were. A failed read is
the empty layout.

**PERT notes**: *Add note* drops a free-text box; dragging between a note's handle and a task links
them with a dashed line. Notes are private layout, never records. Limits: 200 notes, 2000 characters
and 50 links each.

## PERT conventions

- 8 hours = 1 day; a task without an estimate counts as 1 day with a "No estimate" badge.
- Critical tasks have zero slack; a dependency cycle disables the critical path, with a warning.
- A record whose `closed` field is `true` is drawn faded but still counts.
- Links whose other end is filtered out are counted as hidden and not drawn.
- *Re-arrange* lays linked groups out left to right, each task inline with its blockers, and moves
  boxes off arrows that would pass behind them; unlinked tasks go to the right, one column per
  top-level number, wrapped every 10.

## OBS

An OBS box *is* data: a `project_obs_box` row (`kind` `contact` | `user` | `text`, a parent, a
`#rrggbb` color, `x`/`y`). The chart is shared, so moves, colors and parents are record writes
allowed to the project manager and admins only; the canvas runs in **controlled mode**
(`positions` + `onMove`, a rejected move snaps back, read-only without the `canEdit` guard).
Deleting a box makes its children roots. The contact picker offers the project company's people,
and its last line, *Create a new contact*, opens the contact form as a dialog and links the new
person to that company.

## Performance

- Below zoom 0.6, and outside the camera's view plus half a screen on each side, boxes draw only
  their title at the same size, so diagrams of hundreds of boxes stay fluid. Connector dots keep
  about 12px on screen when zoomed out so links can be drawn from an overview.
- A diagram draws at most 2000 records; beyond that it asks to narrow the filters.

## Export

PNG and PDF are produced in the browser (`html-to-image` + `jspdf`, loaded on first export), at the
diagram's natural size, with the legend colors and the current theme; a very large diagram exports
at 1x. Exports always draw full boxes. Non-diagram views (the risk matrix, the mind-map widget) use
the same module's `exportElementPng` / `exportElementPdf`.

## Pitfalls

- A role without `contact:contact:read` / `users:users:read` sees OBS boxes as "Deleted contact" /
  "Unknown user".
- The layout PUT replaces the whole layout (≤ 5000 ids, finite coordinates within ±10⁶, else 400).
- The order number is text: a list sorted on it is lexical (`10` before `2`).

## Related

- [Gantt View](gantt-view.md) · [Risk View](risk-view.md)
- [ADR-040: Diagram Views](../../adrs/040-diagram-views.md)
- [Project App](../../core/project.md)
