# ADR-013: Multi-Company — Several Companies per Tenant, Company-Scoped Settings

**Status**: Accepted
**Date**: 2026-08

---

## Context

Every workspace setting (`core/internal/settings`: default locale, number format, Kanban/Calendar
field config, report page formats) was scoped by `tenant_id` alone — one copy per tenant. Invoices
re-entered the seller's own name/address/phone/email on every document, with no workspace-wide
company-profile concept to draw from.

The ask: let one tenant host several **Companies** (legal entities), each with its own copy of
every workspace setting, switchable per user, with a shared name/address/phone/email profile other
features can read from instead of duplicating.

**Deliberately not built here: per-record data isolation.** A company is *not* a second tenancy
dimension under the first — business tables (invoice, contact, crm, …) are untouched, carry no
`company_id`, and are not filtered by the active company. This ADR covers settings scoping and a
shared company-profile lookup only.

## Decision

1. **`Company` is a plain generic-CRUD entity**, mirroring `contact` exactly — `orm.Register[Company]()`,
   free routes, permissions `company:company:*` auto-derived.
2. **Active company is a per-user preference, not a JWT claim** — `Users.ActiveCompanyID`, read/
   written through the existing `GET/PUT /api/v1/me/preferences` endpoint (extended, not
   duplicated), mirroring how `preferred_locale` already works. Switching is instant, no token
   re-issue.
3. **Bootstrap is race-safe via a partial unique index, not a lock** — the tenant's first company
   ("Default Company") is created lazily on first touch via `INSERT ... ON CONFLICT ... DO
   NOTHING` against `uq_company_tenant_default`, proven with a live-Postgres concurrency test
   (20 concurrent goroutines).
4. **`app_settings` grows a `company_id` column**; every settings handler now resolves the caller's
   active company and threads it through. The unique index moves from `(tenant_id, key)` to
   `(tenant_id, company_id, key)`. Pre-existing rows are backfilled once at boot, before the index
   swap, so a tenant upgrading keeps its existing settings as its new default company's settings.
5. **Creating a company is a one-time deep copy, not ongoing inheritance** — a bespoke Server
   Action clones the caller's *current* active company's settings into the new one via a dedicated
   `clone-settings` endpoint; later edits to either never affect the other.
6. **`report_page_format` is company-scoped client-side only** — it rides the fully generic CRUD
   surface, which has no per-request "active company" context, so scoping there is UI-enforced,
   not server-enforced. This mirrors the same "no second scoping column on business tables"
   boundary drawn in Decision's Context.
7. **Invoice fields fall back to the active company at print time, not form-load time** — `compute`/
   `on_change` handlers are synchronous-only (no fetch), so a new invoice form can't seed issuer
   fields from a company lookup. Instead, `ReportFieldNode.companyFallback` fills in the active
   company's value only when the record's own value is empty, at report-render time.

## Consequences

- No `company_id` on any business table — a user's view of contacts/invoices/CRM records is
  identical regardless of active company. Real per-record segregation would mean doubling the
  ORM's tenant-scoping mechanism across every table — a much larger change, not attempted here.
- `report_page_format`'s company scoping is client-enforced only — a user with direct API access
  can see or create page formats across companies within their own tenant.
- No FK constraints on `active_company_id`/`company_id`, matching this codebase's existing
  no-FK convention.
- Invoice `Issuer*` columns remain live and editable; only the *printed* value now prefers the
  active company when the invoice's own snapshot is blank. Removing them as redundant is deferred.

## Reference Implementation

`core/internal/company/` (model, repository, bootstrap), `core/modules/company/`,
`core/internal/settings/` (company-scoped handlers + clone-settings endpoint),
`apps/shell/app/settings/company/`, `core/modules/sale/views/sale_views.ts` (the `companyFallback`
issuer fields).
