# Address Widget

`type: 'address', widget: 'form'` — a composite field that owns **seven sibling columns**
(`<name>_number|complement|street|zip_code|city|state|country`) rather than mapping to a single
database column. Declaring one `address` field expands into a small, consistent group of inputs
wherever it's used.

---

## Descriptor

```ts
{ name: 'billing_address', label: 'Billing Address', type: 'address', widget: 'form' }
```

The engine derives the seven sibling field names from `billing_address` automatically
(`billing_address_number`, `billing_address_street`, …) — you declare one field, not seven.
`propertymanagement`'s `Address*` fields are the shipped example.

## Map autocomplete

When the workspace has configured an OpenStreetMap/Nominatim connector (Settings → Global settings
→ Integrations), the widget offers live address autocomplete, proxied through a Next.js BFF route
(`apps/shell/app/api/integrations/osm/search/route.ts`) — the browser never calls Nominatim
directly, and the connector's base URL/user-agent/API key never reach client JavaScript. See
[Settings → OpenStreetMap connector](../../core/settings.md#openstreetmap-connector).

Without a configured connector, the widget still works as seven plain text/selection inputs — the
map lookup is a progressive enhancement, not a hard dependency.

## Pitfalls

- The seven underlying columns are real, individually-queryable database columns — a `filter[]` or
  `search[]` against, say, `billing_address_city` works exactly like any other text column (see
  [ORM → Query Parameters](../../core/orm.md#query-parameters-generic-crud)); there's no single
  "address" column to query.
- Field-level group gating ([ADR-014](../../adrs/014-field-level-group-gating.md)) is applied per
  underlying column, not to the composite as a whole — gating `billing_address_street` doesn't
  automatically gate the other six.

## Related

- [Totals Widget](totals-widget.md) — the other composite-field primitive
- [Settings & Workspace Configuration](../../core/settings.md#openstreetmap-connector)
