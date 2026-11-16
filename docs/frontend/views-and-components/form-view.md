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
- A [status bar](form-chrome.md#status-bar), if `statusBar` names a `selection` field (editable
  with `editable: true`, overridable per workspace).
- A **record navigator** (`<` / `>`) stepping through the same filtered, sorted list the user just
  browsed (session-only `list-nav-store`), without going back to the list.
- A [chatter panel](chatter-panel.md) — **on by default**; a module opts out with
  `showChatter: false`, and a workspace can override per entity
  (`/settings/views/:entity/chatter`).

Errors from a save show as an error [banner](../index.md#banners) between the toolbar and the form card: missing required fields are named ("Fill in: …"),
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

### Notebook pages that hide themselves

A notebook page whose every field is hidden right now (`invisible`, `states.visible`, `groups`) drops
its tab, and a selected page that hides itself falls back to the first one shown. That is how a form
shows one of two pages by a record's kind: a contact of kind *company* shows its *Contacts* page, a
person its *Companies* page.

## Form context

A form may name a settings endpoint in `formContext`. The loader reads it server-side (unreadable ⇒
empty), and conditions test its keys as `context.<key>`. The context is never part of the draft, so it
is never sent on save nor lost on reload.

```ts
// core/modules/warehouse: the product reference is typed only while auto-numbering is off
formContext: '/settings/warehouse',
// on the `reference` field:
states: { readOnly: { field: 'context.auto_reference', op: 'eq', value: true } },
```

## Seeding a new record from the list filter

The list URL's `filter[<col>]=` params ride along to the new form, which starts its **many2one** fields
from them (other types are skipped). Creating from `/project/tasks?filter[project_id]=<id>` starts the
task in that project.

## Related

- [View Engine → Layout](../view-engine.md#layout-the-default-form-anatomy) · [→ View inheritance](../view-engine.md#view-inheritance-extends)
- [Form Chrome](form-chrome.md) · [Chatter Panel](chatter-panel.md)
- [ADR-008: Default Form Anatomy](../../adrs/008-form-anatomy.md)
