# Form Chrome: Actions Menu, Header Buttons & Status Bar

Three pieces of always-present form UI, all declared as data on the `ViewDescriptor`, none
requiring a custom component. See [ADR-012](../../adrs/012-form-actions-menu.md) for the design
that replaced the old, form-only page title and one-off buttons with this generic chrome.

---

## Actions menu

`actions?: MenuNode[]` — a small recursive tree rendered as a kebab-icon options menu, present on
every form (disabled, not absent, when empty):

```ts
type MenuNode =
  | { kind: 'action'; label: string; action: string }
  | { kind: 'submenu'; label: string; children: MenuNode[] }
```

```ts
actions: [
  { kind: 'submenu', label: 'Print', children: [
    { kind: 'action', label: 'Invoice', action: 'print-invoice' },
  ]},
]
```

An action leaf names its handler by **name** — register the actual function separately, at import
time, in the module's views file:

```ts
registerMenuAction({
  entity: 'invoice',
  name: 'print-invoice',
  handler: (recordId) => exportReportPDF('sale.invoice', recordId),
})
```

An unregistered or mismatched action name fails at **module registration**, never silently at
click time. There is no per-action permission gating yet — every action on a form a user can
already open is visible in the menu (the handler itself still goes through the same authorized
paths, so this is a UI-affordance gap, not a security one).

## Header buttons

`headerButtons?: HeaderButtonDescriptor[]` are always-visible workflow buttons in the form's top
toolbar, right of the options menu, for actions important enough not to bury in the menu. Several
entries with different `states.visible` conditions make one slot "change label" across a workflow.
`sale`'s Quote form (Confirm / Send / Accept / Decline) is the reference example:

```ts
// core/modules/sale/views/quote_views.ts
headerButtons: [
  { name: 'sale.confirmQuote', label: 'Confirm',
    states: { visible: { field: 'status', op: 'eq', value: 'draft' } } },
  { name: 'sale.sendQuote', label: 'Send',
    states: { visible: { field: 'status', op: 'eq', value: 'confirmed' } } },
  { name: 'sale.declineQuote', label: 'Decline', variant: 'secondary',
    states: { visible: { field: 'status', op: 'eq', value: 'sent' } } },
]

registerHeaderButtonAction({
  entity: 'quote',
  name: 'sale.confirmQuote',
  handler: async (ctx) => { await ctx.runAction!('confirm') },
})
```

`states.visible` unmounts the button; `states.readOnly` renders it disabled. The handler receives a
context with `draft`, `setFieldAndCommit` (a plain field edit saved through Save's path),
`relationOps`, `navigate(path)` (opens an ERP path) and `runAction(action, {body?, revalidate?})`.

**Server-side workflow steps.** `runAction` calls `POST /{entity}/{id}/{action}` through the generic
`EntityActions.action` Server Action and re-seeds the form from the `record` Go answers with;
`revalidate` names other entities whose cached lists the step changes. Prefer it whenever the step
must be checked or atomic on the server (sale's quote confirm/send/accept, invoice confirm/send:
`core/modules/sale/workflow.go`). A refusal's Go message shows beside the buttons.

## Status bar

`statusBar?: { field: string; editable?: boolean }` names a `selection` field rendered as a
breadcrumb of its values across the top of the form. A value the field's options leave out still
shows, last.

```ts
statusBar: { field: 'status' },                 // sale invoices/quotes, event bookings: display only
statusBar: { field: 'status', editable: true }, // crm: the breadcrumb is the field's widget
```

- **Display only** (default): the field keeps its own widget in the form body.
- **`editable: true`**: the field leaves the form body and the breadcrumb becomes its widget. Each
  other step is a button and the current one opens a menu of every step (on a phone only the current
  step shows). A pick sets the field, runs its `on_change`, then saves through the same path as Save
  (chatter log included), or only sets the draft on an unsaved record. Needs
  `<entity>:<entity>:write`; a read-only field keeps it a display.

**Runtime override.** An admin can pick, per entity, another selection field and/or a subset of its
values as steps, from Settings → Apps → *module* (`StatusBarSettings`, listed for every form that
declares `statusBar`). It is stored in `app_settings` `views.<entity>.status_bar` as `{field, steps}`
(null part = not overridden) through `GET|PUT /api/v1/settings/views/:entity/status_bar`
(`settings:views:*`). An override can't add a breadcrumb to a form without one; an unknown field
falls back to the module's, unknown steps are dropped, and saving the module default stores nulls so
values the module adds later show up on their own.

## Related

- [Form View](form-view.md) — where all three mount
- [Chatter Panel](chatter-panel.md) — the other always-present form-adjacent piece
- [ADR-012: Form Actions Menu](../../adrs/012-form-actions-menu.md)
