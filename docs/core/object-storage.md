# Object Storage (Pictures, Signatures & Attachments)

EERP stores binary field content — pictures, hand-drawn signatures, and generic file attachments — in S3-compatible object storage, keyed by metadata rows in PostgreSQL. This page covers both backend services (`internal/pictures` and its sibling `internal/attachments`); see [View Engine → Field Widgets](../frontend/view-engine.md#field-widgets) for the `picture`/`signature`/`file` widgets that use them.

---

## Why a separate service, not a column

A picture or signature is binary content anchored to one field of one record — not a business entity of its own, and not something that belongs in a `bytea` column on the owning table. `core/internal/pictures/` follows the same shape record-anchored data always takes in this codebase (see [ADR-008 → Decision 3](../adrs/008-form-anatomy.md)): a dedicated Go package, its own metadata table, off the generic CRUD surface, with routes derived from that table's name.

---

## Metadata model

```go
// core/internal/pictures/models.go — table: picture
type Picture struct {
    ID        uuid.UUID `db:"id,pk"`
    CreatedAt time.Time
    UpdatedAt time.Time
    TenantID  uuid.UUID `db:"tenant_id,index"`
    TableName string    `db:"table_name"`
    RecordID  uuid.UUID `db:"record_id"`
    Field     string    `db:"field"`
    ObjectKey string    `db:"object_key"`
    Mime      string
    Size      int64
}
```

`Picture` deliberately does **not** embed `model.BaseModel` — it has no `deleted_at`. A soft-deleted row would still satisfy the anchor's uniqueness constraint and silently block a re-upload, so deletion here is always a hard delete (see [Delete](#delete) below).

The anchor `(tenant_id, table_name, record_id, field)` is unique:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_picture_anchor
    ON picture (tenant_id, table_name, record_id, field);
```

One field of one record can have at most one picture at a time — uploading again replaces it.

---

## API

Routes mount only when object storage is configured (see [Configuration](#configuration) below); if it isn't, the routes don't exist rather than existing and failing.

| Method | Route | Permission | Behavior |
|---|---|---|---|
| `POST` | `/api/v1/pictures` | `pictures:pictures:write` | Multipart upload: `file` + `table_name`/`record_id`/`field`. Replaces any existing picture at that anchor. |
| `GET` | `/api/v1/pictures?table=&record=&field=` | `pictures:pictures:read` | Resolves an anchor to its metadata; `404` if none exists (a normal state, not an error — most fields never get a picture). |
| `GET` | `/api/v1/pictures/:id` | `pictures:pictures:read` | Streams the image bytes. |
| `DELETE` | `/api/v1/pictures/:id` | `pictures:pictures:delete` | Hard-deletes the metadata row, then best-effort deletes the S3 object. |

Allowed MIME types are whitelisted: `image/png`, `image/jpeg`, `image/webp`. The object key is derived, never client-supplied: `{tenant}/{table}/{record}/{field}/{uuid}` — so a listing of a tenant's bucket prefix is already scoped correctly, independent of the metadata table.

### Delete

Deletion is **hard**, in this order: the metadata row is removed first, then the S3 object is deleted best-effort. A row can never point at nothing (removing the row is the authoritative "this anchor has no picture" state); an orphaned S3 object on a failed second step is a cleanup concern, not a correctness one.

---

## Object storage backend

`core/internal/pictures/storage.go` talks to S3 through `minio-go/v7` (any S3-compatible endpoint works — AWS S3, MinIO, or the [Garage](#local-development-garage) instance used for local dev):

```go
type ObjectStore interface {
    Put(ctx context.Context, key, contentType string, size int64, body io.Reader) error
    Get(ctx context.Context, key string) (io.ReadCloser, string, error)
    Delete(ctx context.Context, key string) error
}

func NewS3Store(cfg *types.Config) (ObjectStore, error)
func S3Configured(cfg *types.Config) bool // true iff s3_endpoint and s3_bucket are both non-empty
```

`S3Configured` is the single gate: main.go only mounts the `/api/v1/pictures` routes when it returns true, so a deployment that never configures object storage simply has no picture/signature capability — not a half-wired one.

---

## Configuration

Five fields on `types.Config` (see [Configuration → Field Reference](configuration.md#field-reference)), all optional as a set:

| Field | Type | Description |
|---|---|---|
| `s3_endpoint` | string | S3-compatible endpoint URL, e.g. `http://garage:3900` |
| `s3_region` | string | Region string the client sends (Garage accepts any consistent value, e.g. `garage`) |
| `s3_bucket` | string | Bucket to store objects in |
| `s3_access_key` | string | Access key |
| `s3_secret_key` | string | Secret key |

---

## Local development: Garage

Local dev runs [Garage](https://garagehq.deuxfleurs.fr/) — a lightweight, single-binary S3-compatible object store — as a `compose.yml` service, so no external cloud account is needed to exercise picture/signature widgets locally.

```yaml
# compose.yml
garage:
  image: dxflrs/garage:v2.3.0
  volumes:
    - ./infra/garage/garage.toml:/etc/garage.toml:ro
    - garage-meta:/var/lib/garage/meta
    - garage-data:/var/lib/garage/data
  expose:
    - "3900"   # S3 API (internal network only)
  healthcheck:
    test: ["CMD", "/garage", "status"]
```

`infra/garage/garage.toml` configures a single-node layout (`db_engine = "sqlite"`, `replication_factor = 1`) with the S3 API on `3900`, RPC on `3901`, and a tokenless admin/health API on `3903`.

Bring it up and bootstrap it once:

```bash
make garage-init
```

This starts the `garage` container and runs `infra/garage/init.sh`, which is idempotent: it assigns the single-node layout, imports a fixed development access key, and creates and grants read/write/owner on the `eerp` bucket. `make run` / `make run-back` start the `garage` container as part of the compose stack but do **not** run `garage-init` automatically — it's a one-time (or re-runnable) bootstrap step, not a boot-time dependency.

!!! note "Dev credentials are fixed, not secret"
    The development access/secret key pair `init.sh` imports is committed and identical for every clone — it has no reach outside the local `garage` container. Never reuse it in a real deployment; production configuration should point `s3_*` at real, per-environment credentials for whatever S3-compatible store is in use (self-hosted Garage or otherwise).

---

## Attachments (Generic Files)

`internal/attachments` is the non-image sibling of `internal/pictures`, backing the `boolean/file`
field widget for arbitrary files a picture's image whitelist would reject (a purchase invoice, a
generated rent-receipt PDF). Same one-row-per-`(tenant, table, record, field)` anchor and S3-backed
storage — it reuses `pictures.NewS3Store`/`ObjectStore` verbatim, a second client instance off the
same `s3_*` config, since the object-store layer was already provider-agnostic. The differences:

- No MIME whitelist — any file type is accepted.
- A real `Filename` column, round-tripped as the download's `Content-Disposition` header — a
  picture is only ever rendered inline as an `<img>`, never offered as a named download.

| Method | Route | Permission |
|---|---|---|
| `POST` | `/api/v1/attachments` | `attachments:attachments:write` |
| `GET` | `/api/v1/attachments?table=&record=&field=` | `attachments:attachments:read` |
| `GET` | `/api/v1/attachments/:id` | `attachments:attachments:read` |
| `DELETE` | `/api/v1/attachments/:id` | `attachments:attachments:delete` |

Mounted only when `s3_*` is configured — the same gate as pictures.

---

## Related

- [View Engine → Field Widgets](../frontend/view-engine.md#field-widgets) — the `boolean/picture`, `boolean/signature`, and `boolean/file` widgets that upload/render through this service.
- [Views & Components → Picture, Signature & File Widgets](../frontend/views-and-components/picture-signature-file-widgets.md)
- [ADR-008: Default Form Anatomy](../adrs/008-form-anatomy.md) — the record-anchored-data category this service exemplifies; see [Record-Anchored Services](record-anchored-services.md) for its siblings (chatter, notebook, saved filters).
- [Reports & PDF Generation](reports.md) — another consumer of the same Garage/S3 backend.
- [Object Storage Across Layers](../architecture/object-storage-topology.md) — pictures, attachments, and reports compared side by side.
- [Configuration](configuration.md) — the full `eerp-config.json` field reference.
- [Getting Started](../getting-started.md) — local environment setup, including `make garage-init`.
