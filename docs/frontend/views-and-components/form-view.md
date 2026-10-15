# Form View

`viewType: 'form'` — a single-record editor. Fields render via MUI inputs bound to a Zustand
`draft`; **Save** commits via the entity's Server Action and is disabled until the draft is dirty.

---

## The default anatomy — you don't have to lay anything out

Declare no `layout` and the engine synthesizes one: a header row (the first `widget: 'picture'`
field, then the first text field rendered large as a title), a two-column group holding every
other field, and a "Settings" notebook tab collecting every `widget: 'long'` field. See
[ADR-008: Default Form Anatomy](../../adrs/008-form-anatomy.md) and [View Engine →
Layout](../view-engine.md#layout-the-default-form-anatomy) for the full mechanism.

```ts
const formView: ViewDescriptor = {
  entity: 'crm',
  viewType: 'form',
  fields: [
    { name: 'name', label: 'Name', type: 'text', required: true },
    { name: 'email', label: 'Email', type: 'text' },
    { name: 'notes', label: 'Notes', type: 'text', widget: 'long' }, // lands in the Settings tab
  ],
  permissions: ['crm:contacts:read'],
}
```

## Always-present chrome

Every form route gets, unconditionally, in one toolbar row above the form:

- **Save** and an icon-only **Reset** — Save is disabled until the draft is dirty.
- The [form actions menu](form-chrome.md) — the descriptor's `actions`, plus a built-in
  **Delete** when the caller holds `<entity>:<entity>:delete`. Delete commits at once, returns to
  the list and offers the [undo toast](undo-toast.md) (Recover calls the generic restore).
- [Header buttons](form-chrome.md#header-buttons), if `headerButtons` is declared.
- A [status bar](form-chrome.md#status-bar), if `statusBar` names a `selection` field.
- A **record navigator** (`<` / `>`) stepping through the same filtered, sorted list the user just
  browsed (session-only `list-nav-store`), without going back to the list.
- A [chatter panel](chatter-panel.md) — **on by default**; a module opts out with
  `showChatter: false`, and a workspace can override per entity
  (`/settings/views/:entity/chatter`).

Errors from a save show in an `ErrorAlert`: missing required fields are named ("Fill in: …"),
fields the form doesn't show are flagged as a model/form mismatch to report, and a **Copy
details** button copies code, message, request id, page and time for an administrator.

None of these require a custom component. See [ADR-012: Form Actions Menu](../../adrs/012-form-actions-menu.md)
for why the form's own page title was dropped in favor of this chrome.

## An explicit layout

Declaring `layout` opts out of the synthesized anatomy entirely — you get exactly what you
declare, using the same node types the synthesized layout is built from:

```ts
const layout: LayoutNode = {
  kind: 'group',
  children: [
    { kind: 'row', children: [{ kind: 'field', name: 'name' }, { kind: 'field', name: 'email' }] },
    { kind: 'notebook', pages: [{ id: 'settings', label: 'Settings', children: [{ kind: 'field', name: 'notes' }] }] },
  ],
}
```

`LayoutNode` kinds: `group`, `row`, `section`, `notebook`, `page` (a notebook tab), and `field`
leaves. The synthesized header/columns nodes carry stable ids (`__form_header`,
`__form_columns`) so a [view extension](../view-engine.md#view-inheritance-extends) can address
and reshape them even when a base module never declared an explicit layout.

## Related

- [View Engine → Layout](../view-engine.md#layout-the-default-form-anatomy) · [→ View inheritance](../view-engine.md#view-inheritance-extends)
- [Form Chrome](form-chrome.md) · [Chatter Panel](chatter-panel.md)
- [ADR-008: Default Form Anatomy](../../adrs/008-form-anatomy.md)
