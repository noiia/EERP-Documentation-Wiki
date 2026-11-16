# Demo Data

Settings → **Developer** fills a workspace with fake data, in two volumes:

| Volume | Who writes it | Size | Use |
|---|---|---|---|
| **Light** (default) | the frontend, through the normal generic API | dozens of records per entity, real pictures, a full Event demo set | click-through demos, UI work |
| **Full** | Go (`core/internal/devseed`), set-based SQL | ~100 000 rows per business table | performance work, Graph views, paging |

Both are **development only**: the full seed refuses outside `environment: "development"`; the
light one is gated by the frontend's `seedingAllowed()` (`NODE_ENV !== 'production'`, unless
`ALLOW_DEMO_SEED` overrides it — set to `true` only in the local Compose stack, never against a
real tenant). Each gate is checked server-side, not just by hiding the button.

## Full seed

`POST /api/v1/dev_seed {groups?}` (`dev_seed:dev_seed:write`) seeds by **groups**:

| Group | Contents | Depends on |
|---|---|---|
| `base` | 3 extra companies, VAT rates and stacked tax tags | — |
| `products` | products & variants | — |
| `contacts` | contacts | — |
| `crm` | CRM leads & tags | contacts |
| `quotes` | quotes, 2 lines each | base, contacts, products |
| `invoices` | invoices, 2 lines each | base, contacts, products |
| `property` | properties and rent receipts | contacts |
| `events` | events, sessions over ±6 months, bookings with realistic statuses | contacts |

- Absent `groups` = all. Selected groups pull in their dependencies; groups already seeded are
  skipped (one `app_settings` marker per group, `dev.seed.full.<group>`), so nothing is ever
  seeded twice. Nothing left to do → 409; a seed already running for the tenant → 409.
- It runs **in the background**: the POST validates, then answers `202 {notification_id}`. The
  run is a `dev_seed` [activity](notifications.md) with per-step progress, finished `done` (per-
  entity results in its `data`) or `failed`, plus a personal notification to the initiator.
- `GET /api/v1/dev_seed` lists the groups, their dependencies and seeded state, and `running`
  (the running seed's notification id) — the page resumes following a run after a reload.
- With `s3_*` configured, every picture field of the seeded rows gets a sample image (a small
  pool uploaded once per tenant under `<tenant>/_samples/`, shared by many rows).
- Afterwards every list over 10 000 rows gets a Graph view in every company, plus simple and
  nested calculated fields, and the [search indexes](list-performance.md) are built.

!!! warning "Pitfalls when editing the seed SQL"
    - An uncorrelated `LATERAL (SELECT … random())` is evaluated once for all rows, and the
      planner may push a `random()` filter into a small joined table — use per-row hashes.
    - Bulk-loaded temp tables need an index and `ANALYZE`, or joins go quadratic.
    - Sample-picture objects are shared: replacing or deleting such a picture removes only its
      row, never the object (`pictures.IsSampleKey`).

## Light seed

A Server Action loops `createServerApiClient().create(entity, body)` over the generic API in
dependency order, so every row goes through the same validation and permission checks as a real
user's write, and per-record failures are collected into a summary instead of aborting. Event
demo bookings go through the staff booking route, so seats, contacts and emails are real.

The light seed also creates:

- **Projects**: 3 small projects plus 2 large ones for the WBS and PERT views (10 phases → 6 work
  packages → 2–3 steps, 220 tasks and 175 dependencies each, the first phases done and in the past;
  `dev-seed-plan.ts`), tasks assigned to the signed-in admin, 4 color groups, OBS boxes linked to the
  project company's contacts, and demo risks with their categories. Aggregates are left to the
  database triggers. It is about 800 sequential requests, so the light seed takes noticeably longer.
- **A demo website** (`seedWebsite`, content in `src/lib/dev-seed-website.ts`): home with welcome
  text, an events carousel and a product grid, an events list, a product catalog and the detail pages
  they link to. It adds the fields those blocks read to each table's published selection (keeping
  existing ones and any forced filter), skips a page whose slug exists, and expires the site's
  cached reads.

!!! note "Re-running the light seed"
    Re-running it duplicates projects and color groups (it doesn't check what exists), while website
    pages with an existing slug are skipped.

Settings → Developer also links to the cron list and to the
[database manager](database-management.md) (`/database/management`, outside the ERP session).

## Related

- [Notifications](notifications.md) · [List Read Performance](list-performance.md) · [Testing](../developer-guide/testing.md)
