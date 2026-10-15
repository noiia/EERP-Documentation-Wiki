# Relation Widgets

A `type: 'relation'` field carries a `relation: RelationDescriptor` (see [View Engine → Relation
Widgets](../view-engine.md#relation-widgets)) and renders as one of five widgets — three defaults,
one per relation kind, plus two overrides.

---

## The three defaults

| Kind | Default widget | Component | Renders |
|---|---|---|---|
| `many2one` | `search` | `RelationSearchWidget` | A debounced MUI `Autocomplete` |
| `many2many` | `tags` | `RelationTagsWidget` | A chip picker; links are junction rows written immediately, not part of the record's own draft |
| `one2many` | `list` | `RelationListWidget` | A read-only embedded grid of the inverse-side records |

```ts
{ name: 'contact_id', label: 'Contact', type: 'relation',
  relation: { entity: 'contact', kind: 'many2one', labelField: 'name' } },
{ name: 'tags', label: 'Tags', type: 'relation',
  relation: { entity: 'tag', kind: 'many2many', via: 'crm_tag', labelField: 'name' } },
```

## Options worth knowing

| Option | Kind | Effect |
|---|---|---|
| `relation.filter: { col: value }` | m2o, m2m | static server-side scope on every search/prefill — the picker only ever offers matching rows |
| `relation.formPath: '/x/:id'` | o2m | clicking a row opens that record's own form |
| `relation.inside: { field, zone }` | o2m | instead of `inverseField`: the records whose point lies in this record's zone ([Geographic Widgets](geo-widgets.md)) |
| `widgetOptions.fillFields: { col: field }` | m2o | picking a record copies its columns into sibling fields (e.g. an invoice's bill-to snapshot) — no extra fetch |
| `widgetOptions.deletable` | o2m | a trash column; the row disappears only once Go confirms the delete |
| `widgetOptions.reverse` | o2m | newest first (`order=-created_at`) |

### Paged one-to-many grids

When the host binds `RelationOps.listPage` (the shell does), the embedded o2m grid is
**server-paged**: one request per page, sorted by `created_at` so pages are stable, 10 rows by
default; a rows-per-page selector (25/50/100) appears once the linked rows don't fit. Deleting a
row reloads the page so it refills. Without `listPage` it loads the first 100 rows once. A wide
grid scrolls horizontally inside its own box.

## Create-from-search

The `many2one` search widget's dropdown appends a synthetic "+ Create new" option after its (max 6)
results. Picking it opens `RelationCreateWizard`, a real form dialog that reuses the related
entity's **own registered form descriptor** — seed defaults, `on_change`, `compute`, and permission
checks all behave exactly as they would on that entity's real form. A `preset` seeds and hides
fields the caller already knows (e.g. the inverse FK for an o2m context). This is the mechanism
behind "add a new contact without leaving the CRM form."

## Overrides: carousel and summary

```ts
// o2m override — photo-gallery carousel over embedded rows, each backed by a boolean/picture field
{ name: 'photos', label: 'Photos', type: 'relation', widget: 'carousel',
  relation: { entity: 'equipment_photo', kind: 'one2many', inverseField: 'equipment_id' } }

// many2one override — an inline card summarizing the linked record instead of a search box
{ name: 'primary_contact_id', label: 'Primary Contact', type: 'relation', widget: 'summary',
  relation: { entity: 'contact', kind: 'many2one' } }
```

`propertymanagement`'s Equipment "Photos" field is the shipped `carousel` example.

## Batched many-to-many resolution

Resolving a set of linked records from a set of junction rows is **one** call, not one per row:
`resolveManyToManyLinks` fetches the junction list, then a single `ops.list(relatedEntity, { in: {
id: [...] } })` — reusing the ORM's `in[column]` filter (see [ORM → Query
Parameters](../../core/orm.md#query-parameters-generic-crud)). Both `tags` and `summary`'s nested
resolver share this one helper; a dangling junction row (its related record since deleted) falls
back to showing the raw id as a placeholder label rather than erroring. See
[ADR-018](../../adrs/018-http2-edge-rest-batching.md) — this is the REST answer to the N+1 problem
GraphQL is usually reached for.

!!! note "Still open: the carousel's own N+1"
    The carousel widget's per-slide picture-metadata lookup is a *different* N+1 shape (one anchor
    per binary resource) that ADR-018 explicitly left open — fixing it needs a batch endpoint on
    [Object Storage](../../core/object-storage.md) that doesn't exist yet.

## Related

- [View Engine → Relation Widgets](../view-engine.md#relation-widgets) · [→ Relations (ORM side)](../../core/orm.md#relations)
- [Totals Widget](totals-widget.md) — often paired with an o2m relation of line items
- [ADR-018: HTTP/2 Edge & REST Batching](../../adrs/018-http2-edge-rest-batching.md)
