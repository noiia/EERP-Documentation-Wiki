# ADR-034: Website forms write into registered tables

**Status**: Accepted. Builds on [ADR-025](025-public-access-and-website-identities.md) (public access, website identities) and [ADR-026](026-website-routing-and-erp-base-path.md) (page model).
**Date**: 2026-11-02

---

## Context
The public site needs to collect data — contact requests, sign-ups, registrations — straight into the
ERP's own records, designed in the page builder without code. A public form is an anonymous write
path into business tables, so it must not become a generic "insert anything" endpoint: the visitor
controls the request, the designer controls the form, and neither may reach a table or column a
module did not agree to expose.

## Decision

### 1. Targets are declared in code, picked by the designer
A module registers, in Go, the tables and columns a public form may write — the same "declare in
code, choose as admin" shape as `orm.WithPublicFields`:

```go
// core/modules/crm/module.go — Register()
formtarget.RegisterFormTarget("crm", "name", "company", "phone", "notes", "status", "contact_id")
```

`core/internal/website/formtarget` is a leaf package (standard library only), so any module can
register without an import cycle. The page builder lists the registry
(`GET /api/v1/settings/website/form_targets`, `settings:website:read`) — only for **active** modules.

A `form` block's config (`FormConfig`) names one or more **targets** (tables, written in order in one
transaction), the **fields** (each mapped to a column of one target; an `address` field maps a prefix
onto the 7 address columns), per-target **links** (`crm.contact_id ← the record target 0 created`)
and **fixed** values (`crm.status = lead`). Saving a layout runs `formtarget.ValidateFormConfig`
(website module's layout validation, 400 on failure):

- 1–10 targets, ≤ 60 fields, unique field ids, a `select` has options;
- every table and column is registered; a column is written at most once per target, across
  fields, links and fixed values;
- a link points to an **earlier** target;
- a visitor-typed field never maps a `*_id` column — ids come only from links or fixed values, so a
  visitor can't point a record at another one by typing its id.

### 2. The server reads the definition, never the request
`POST /api/v1/website/forms/:page_id/:block_id` (anonymous or website token — never an ERP token;
public rate limit) takes only `{values: {<field id>: value}}`. Go loads the form from the **stored,
published** page layout, re-validates it against the current registry (a module may have dropped a
column since), refuses it while any target's module is inactive (422 "not available"), validates each
value against its field type and column type (422 `VALIDATION_ERROR` with `fields: [ids]`), and
writes only mapped columns. Request keys that aren't a field id are ignored. Unpublished page or
missing block: 404. `login_required` and anonymous: 401.

### 3. Contact rules
A `contact` target is special, because people already exist in the ERP:

- **Signed-in visitor:** the form updates the visitor's **own website contact** (created if their
  account predates it) — only the mapped columns; the email stays the account's (a typed email is
  ignored, and the site shows it read-only). The `users` row is never written by a form: the account
  is edited from *My account* only. Fields are prefilled from that contact, falling back to the
  account (`GET /api/v1/website/me/contact`, then `/website/me`).
- **Anonymous visitor:** the contact goes through `contact.FindOrCreateContact` by email. A **new**
  contact gets the typed values. An **existing** one is never overwritten (an anonymous request
  can't prove it owns that email): later targets still link to it, and the typed values are posted
  as a `kind: "log"` chatter message on it (`Website form "<page>": Phone: …; Address: …`) so staff
  see them. Without an email the contact is simply created.
- **Create an account:** with `allow_signup`, an anonymous visitor can tick *Create an account*.
  The browser runs the **signup first** (`/api/site-auth/signup` — a 409 becomes an error on the
  email field and nothing is submitted), which signs the visitor in; the form is then submitted as
  that visitor, so rule one applies to the new website contact. Keeping it client-side reuses the
  signup endpoint and its rules as they are, instead of a second account-creation path in the form
  endpoint.

### 4. Login as a gate
`login_required` (default off) shows an anonymous visitor a *Log in to continue* button and a
*Sign up* link instead of the form (`LoginGate`), both returning to `after_login_slug` or the same
page through a same-site `?next=`.

Only a form's `login_required` is enforced (Go answers 401 to an anonymous submit). A booking
block's `login_required` is presentational: the booking API stays open to anonymous visitors, so
restrict the event itself if bookings must be account-only.

```mermaid
sequenceDiagram
    participant V as Visitor (browser)
    participant N as Next (BFF)
    participant G as Go
    participant DB as PostgreSQL
    opt "Create an account" ticked
        V->>N: POST /api/site-auth/signup {email, password, name}
        N->>G: POST /api/v1/website/auth/signup
        G-->>N: tokens (409 = email taken → field error, stop)
        N-->>V: site session cookies set
    end
    V->>N: POST /api/site-forms/:page/:block {values}
    N->>G: POST /api/v1/website/forms/:page/:block (site token if any)
    G->>DB: load published page layout → form block config
    G->>G: re-validate against registry, active modules, value types
    G->>DB: BEGIN; per target: contact rules / INSERT; links; COMMIT
    G-->>N: 201 {ok} · 422 {fields} · 401 · 404
    N-->>V: message, or redirect to the chosen page
```

## Consequences
- A new form target is one `formtarget.RegisterFormTarget` call in the owning module's `Register()`;
  forgetting it means the builder never offers the table and a hand-written layout is refused.
- Forms are submit-only: no submissions inbox, file fields, multi-step forms or notification emails
  (each can come later — e.g. via mail templates). Bookings are not form targets: seats are written
  only by the booking service.
- Pitfall: an anonymous form can't update an existing contact by design — staff merge the chatter
  log by hand if needed.
