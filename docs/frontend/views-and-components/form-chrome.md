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

`headerButtons?: HeaderButtonDescriptor[]` — always-visible workflow buttons rendered via
`HeaderButtonContainer`, for actions important enough not to bury in the options menu. `sale`'s
Quote workflow (Confirm / Send / Accept / Decline) is the reference example.

```ts
headerButtons: [
  { label: 'Confirm', action: 'quote-confirm', states: { visible: { field: 'status', equals: 'draft' } } },
]
```

## Status bar

`statusBar?: string` — names a `selection` field rendered as a read-only breadcrumb across the top
of the form, showing the record's progression through its states at a glance.

```ts
statusBar: 'status', // the same field Kanban might use as its column source
```

## Related

- [Form View](form-view.md) — where all three mount
- [Chatter Panel](chatter-panel.md) — the other always-present form-adjacent piece
- [ADR-012: Form Actions Menu](../../adrs/012-form-actions-menu.md)
