# Record-Anchored Services

A recurring shape in EERP's backend: data that belongs to *one field of one record* — not a
business entity in its own right, and not a fit for the generic CRUD surface because it needs a
visibility or ownership rule the generic column-filter chain can't express. `internal/pictures`
(see [Object Storage](object-storage.md)) was the first of this family; `internal/chatter`,
`internal/notebook`, and `internal/savedfilter` all mirror its shape. This page covers the three
that don't need a dedicated deep-dive of their own; `internal/pictures`/`internal/attachments` have
their own page because object storage adds a genuinely separate S3 concern.

Each service in this family is: a dedicated Go package, its own table anchored on
`(tenant_id, table_name, record_id, ...)`, off the generic CRUD surface (`orm.WithExcluded()` or
simply never registered generically), with hand-written, tenant-pinned routes whose permissions
still derive automatically from the route pattern. See [ADR-007 → Decision
3](../adrs/007-runtime-view-fields.md) for the pattern's origin.

---

## Chatter

`internal/chatter` is a record's activity feed: a user-posted comment, or the frontend's own
summary of a form edit, stored as one `ChatterMessage` row (`kind`: `"message"` or `"log"`)
anchored on `(tenant_id, table_name, record_id)`.

```go
type ChatterMessage struct {
    model.BaseModel
    TenantID    uuid.UUID `db:"tenant_id"`
    TableName   string    `db:"table_name"`
    RecordID    uuid.UUID `db:"record_id"`
    Kind        string    `db:"kind"` // "message" | "log"
    Body        string    `db:"body"`
    AuthorEmail string    `db:"author_email"` // snapshotted at write time
}
```

**Append-only** — no `Update`/`Delete` — an activity log reads wrong if entries can change after
the fact. `AuthorEmail` is resolved once at write time via `auth.UserRepository` so a feed read
never needs a per-message author lookup.

| Method | Route | Notes |
|---|---|---|
| `GET` | `/api/v1/chatter_messages?table=&record=` | Newest first |
| `POST` | `/api/v1/chatter_messages` | |

The frontend posts a `kind: "log"` entry itself after a successful form edit
(`summarizeFieldChanges` in `renderers.tsx`) — the backend never diffs a record's fields itself, it
only stores whatever the caller posts. [Cron](cron.md) also posts here to surface run-as-permission
failures, since a background scheduler has no live HTTP caller to return an error to. See the
[Chatter Panel](../frontend/views-and-components/chatter-panel.md) for the client side.

## Notebook

`internal/notebook` gives a user their own rich-text pages on **one** record — e.g. free-form
meeting notes on a single CRM row. The third category [ADR-007](../adrs/007-runtime-view-fields.md)
names alongside descriptor structure and workspace `app_settings`.

```go
type NotebookPage struct {
    model.BaseModel // soft-deletable — unlike Picture, no per-anchor uniqueness depends on absence
    TenantID  uuid.UUID `db:"tenant_id"`
    TableName string    `db:"table_name"`
    RecordID  uuid.UUID `db:"record_id"`
    Title     string    `db:"title"` // ≤200 chars
    Position  int       `db:"position"` // stable append order
    Content   string    `db:"content"`
}
```

| Method | Route |
|---|---|
| `GET`/`POST` | `/api/v1/notebook_pages?table=&record=` |
| `PUT`/`DELETE` | `/api/v1/notebook_pages/:id` |

Mounted unconditionally — no external dependency (like object storage's `s3_*`) to gate on. The
default form anatomy's synthesized "Settings" tab (see [ADR-008](../adrs/008-form-anatomy.md)) is
itself a notebook-style `page` layout node, and a module's own cron `Action.Source` is rendered as
a read-only notebook page (see [Cron](cron.md)).

## Saved Filters

`internal/savedfilter` stores named, reusable search-bar filter combinations — a user builds a set
of filters/group-by choices in one entity's search bar and saves it, either private or shared
tenant-wide.

```go
type SavedFilter struct {
    model.BaseModel
    TenantID uuid.UUID `db:"tenant_id"`
    UserID   uuid.UUID `db:"user_id"`
    Entity   string    `db:"entity"`
    Name     string    `db:"name"`
    Shared   bool      `db:"shared"`
    Config   []byte    `db:"config"` // opaque JSON — never inspected server-side
}
```

**Why off generic CRUD**: "private OR shared" visibility is an OR-composed `WHERE` the generic
repository's AND-only filter chain can't express (`orm.Cond(...)`'s raw-SQL escape hatch is the
documented way to write OR in this ORM). Rename/delete also need an owner check even on a filter
someone marked shared — no admin override in v1.

Two hand-written partial unique indexes give private and shared names independent uniqueness
scopes:

```sql
CREATE UNIQUE INDEX idx_saved_filter_private_name
  ON saved_filter (tenant_id, user_id, entity, name) WHERE shared = false AND deleted_at IS NULL;
CREATE UNIQUE INDEX idx_saved_filter_shared_name
  ON saved_filter (tenant_id, entity, name) WHERE shared = true AND deleted_at IS NULL;
```

| Method | Route | Notes |
|---|---|---|
| `GET` | `/api/v1/saved_filters?entity=` | The caller's own rows plus every other user's *shared* ones |
| `POST` | `/api/v1/saved_filters` | |
| `PUT`/`DELETE` | `/api/v1/saved_filters/:id` | Owner-only, even on a shared row |

`Config` is re-validated by the frontend against the live descriptor when applied, so a filter
saved before a field was removed or regated degrades gracefully. See [ADR-015: Search/Filter
Bar](../adrs/015-search-filter-bar.md) and [Search & Filter
Bar](../frontend/views-and-components/search-filter-bar.md).

## Comparison

| Service | Anchor | Mutability | Visibility rule | Why off generic CRUD |
|---|---|---|---|---|
| [Pictures/Attachments](object-storage.md) | `(tenant, table, record, field)` | Replace-in-place | One per anchor | Binary content, S3-backed |
| Chatter | `(tenant, table, record)` | Append-only | Anyone who can read the record | No update/delete semantics |
| Notebook | `(tenant, table, record)` | Full CRUD | Anyone who can read the record | Ordered, titled pages — not a fit for a flat entity list |
| Saved Filters | `(tenant, user, entity)` | Owner-only mutation | Private OR shared | OR-composed visibility the generic filter chain can't express |
| [Cron](cron.md) | *(none — a plain tenant-scoped entity)* | Full CRUD | — | **Deliberately generic** — the one exception, so it gets List/Kanban/Calendar/Graph for free |

## Related

- [Object Storage](object-storage.md) — the pictures/attachments/S3 half of this family
- [Object Storage Across Layers](../architecture/object-storage-topology.md) — how pictures/attachments' anchor pattern compares to reports' deliberately different, non-anchored scheme
- [Background Cron Scheduler](cron.md) — the deliberate exception to this pattern, and why
- [ADR-007: Runtime-Configurable View Fields](../adrs/007-runtime-view-fields.md)
