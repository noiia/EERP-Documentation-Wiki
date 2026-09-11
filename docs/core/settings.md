# Settings & Workspace Configuration

`core/internal/settings` is a tenant- (and, since [ADR-013](../adrs/013-multi-company.md),
company-) scoped key/value store for workspace preferences that don't belong on any one business
entity: default locale, number formatting, which field backs a Kanban's status column or a
Calendar's date, a Graph mode's tile layout, the OpenStreetMap connector configuration, and the
tax pricing mode. It sits deliberately off the generic CRUD surface — each key has its own
narrow, purpose-built `GET`/`PUT` pair rather than a free-form `app_settings` CRUD endpoint,
because most of these values need validation the generic column-whitelist handler doesn't do
(e.g. a Graph tile's shape, or the closed `tax_excluded`/`tax_included` enum).

---

## Why not generic CRUD

`app_settings` is a single JSON blob per `(tenant_id, company_id, key)`. Exposing it generically
would mean any writable key could be created ad hoc from the frontend with no server-side shape
validation. Instead, each setting has a dedicated handler that validates its own JSON shape before
persisting it — the same "off generic CRUD because this needs a rule the column-whitelist chain
can't express" posture `internal/chatter`/`internal/notebook`/`internal/savedfilter` take for
different reasons. See [Record-Anchored Services](record-anchored-services.md) for that family.

## Storage shape

```go
// core/internal/settings — table: app_settings
type AppSetting struct {
    model.BaseModel
    TenantID  uuid.UUID `db:"tenant_id"`
    CompanyID uuid.UUID `db:"company_id"`
    Key       string    `db:"key"`
    Value     []byte    `db:"value"` // opaque JSON, shape owned by the key's own handler
}
```

Unique index on `(tenant_id, company_id, key)`. `Repository.Get`/`Set` take `companyID` as a
parameter — every handler below resolves the caller's **active** company
(`companies.ResolveActive`) once per request and threads it through, so the same key can hold a
different value per company within one tenant.

## Settings keys and their endpoints

| Key | Endpoint | Permission | Shape |
|---|---|---|---|
| `i18n.default_locale` | `PUT /api/v1/settings/i18n` | `settings:i18n:write` | Workspace default language |
| `format.number` | `PUT /api/v1/settings/format` | `settings:format:write` | Workspace number format (decimal/thousands separators) |
| `views.<entity>.fields` | `GET\|PUT /api/v1/settings/views/:entity/fields` | `settings:views:read`/`write` | Which field is that entity's Kanban status column / Calendar date field — see [ADR-006](../adrs/006-view-inheritance.md)'s sibling, [ADR-007: Runtime-Configurable View Fields](../adrs/007-runtime-view-fields.md) |
| `views.<entity>.graph` | `GET\|PUT /api/v1/settings/views/:entity/graph` | `settings:views:read`/`write` | An entity's Graph-mode tile layout (id, geometry, closed type set per tile) |
| `integrations.osm` | `GET\|PUT /api/v1/settings/integrations/osm` | `settings:integrations:read`/`write` | `{enabled, base_url, user_agent}` for the OpenStreetMap/Nominatim connector backing the [Address widget](../frontend/views-and-components/address-widget.md) |
| `tax.price_mode` | `GET\|PUT /api/v1/settings/tax` | `settings:tax:read`/`write` | `{price_mode: "tax_excluded" \| "tax_included"}` |

Plus one self-service, JWT-scoped endpoint outside the tenant-admin set: `GET/PUT
/api/v1/me/preferences` — the caller's own `preferred_locale` and (since multi-company)
`active_company_id`.

Every `GET` on an unconfigured key reads as its documented zero value (an empty canvas for
`views.<entity>.graph`, `tax_excluded` for `tax.price_mode`, a disabled connector for
`integrations.osm`) — **not a 404**. An unconfigured setting is a normal state a fresh workspace
starts in, not an error condition.

## Tax pricing mode

`tax.price_mode` decides how a `SaleTax`'s percentage/fixed amount interacts with a line's base
price, resolved server-side via the exported `ResolveTaxIncluded` helper so `sale` and
`propertymanagement`'s own tax computation can use the same effective value without an HTTP
round-trip:

- **`tax_excluded`** (the default): tax is computed *on top of* the base price. `12€ + 20% tax =
  14.40€`.
- **`tax_included`**: the base price is treated as already tax-inclusive, and the pre-tax subtotal
  is back-derived. `12€ including 20% tax stays 12€ total, of which 10€ is pre-tax`.

Each billing/sale line persists its own tax-excluded `Subtotal` alongside `Total`, computed once at
write time, so invoice/receipt rollups can sum it directly rather than re-deriving it from
`UnitPrice` — which no longer safely stands in for the tax-excluded figure once prices can be
tax-inclusive.

## OpenStreetMap connector

The workspace's OSM/Nominatim configuration is proxied through a Next.js BFF route
(`apps/shell/app/api/integrations/osm/search/route.ts`), never called from the browser directly —
so the connector's base URL, user agent, and any future API key never reach client JavaScript. The
[Address field widget](../frontend/views-and-components/address-widget.md) is the sole consumer.

## Multi-Company Scoping

Every key above became company-scoped in one mechanical pass ([ADR-013](../adrs/013-multi-company.md)):
`Repository.Get`/`Set` gained a `companyID` parameter, threaded through each handler by resolving
`companies.ResolveActive` once per request. Pre-existing single-tenant rows were backfilled once at
boot, before the unique index moved from `(tenant_id, key)` to `(tenant_id, company_id, key)`, so a
tenant upgrading from before multi-company shipped sees its existing settings become its new
default company's settings — nothing resets. Creating a second company is a one-time deep copy
(`POST /api/v1/company/:id/clone-settings`) of every settings row, not an ongoing inheritance chain
— a later edit to either company never affects the other.

## Interactions

```mermaid
graph LR
    Handler["Settings handler\n(i18n / format / views / osm / tax)"] -->|resolves| Company["companies.ResolveActive"]
    Handler -->|Get/Set with companyID| Repo["settings.Repository"]
    Repo -->|unique on tenant+company+key| DB[("app_settings")]
    OSMProxy["Next BFF osm/search route"] -->|reads| Handler
    ViewsSettings["Settings → Views UI"] -->|sources field choices from| Descriptor["registered ViewDescriptor"]
    ViewsSettings -->|writes chosen field to| Handler
```

## Related

- [ADR-007: Runtime-Configurable View Fields](../adrs/007-runtime-view-fields.md)
- [ADR-013: Multi-Company](../adrs/013-multi-company.md)
- [Authentication → Multi-Company](authentication.md#multi-company-within-a-tenant)
- [View Engine → Runtime view settings](../frontend/view-engine.md#runtime-view-settings-kanbancalendargraph)
