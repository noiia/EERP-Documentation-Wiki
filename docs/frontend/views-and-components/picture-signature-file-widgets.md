# Picture, Signature & File Widgets

Three `boolean`-typed widgets whose actual bytes live in S3-compatible object storage, addressed
by `{table, recordId, field}` — the field's boolean value only tracks whether the binary exists.
All three are **service-authoritative**: on mount, each resolves the anchor against its backing
service and reconciles the draft boolean with what actually exists there, rather than trusting the
record's own field value. See [Object Storage](../../core/object-storage.md) for the backend.

---

## `boolean/picture` and `boolean/signature`

Backed by `internal/pictures`. `signature` renders an HTML5 `<canvas>` the user draws on with
pointer events; "done" calls `canvas.toBlob()` and uploads the PNG. Both accept only
`image/png`/`image/jpeg`/`image/webp`.

```ts
{ name: 'photo', label: 'Photo', type: 'boolean', widget: 'picture' }
{ name: 'signed_off', label: 'Signature', type: 'boolean', widget: 'signature' }
```

## `boolean/file`

Backed by `internal/attachments` — the non-image sibling for arbitrary files (a purchase invoice, a
generated PDF) a picture's MIME whitelist would reject. Renders as a filename + download link
rather than a thumbnail; the download's `Content-Disposition` carries the original filename.

```ts
{ name: 'purchase_invoice', label: 'Invoice', type: 'boolean', widget: 'file' }
```

## Shared chrome

`WidgetFrame` is the common wrapper all three use for upload/preview/remove affordances — a
consistent look across pictures, signatures, and files without each widget re-implementing its own
frame.

## Pitfalls

- One field, one anchor: uploading again **replaces** the existing image/file at that anchor —
  there is no versioning or history.
- Deletion is always hard, never soft — a soft-deleted metadata row would still satisfy the
  anchor's uniqueness constraint and silently block a re-upload. See [Object Storage →
  Delete](../../core/object-storage.md#delete).
- These widgets do nothing if object storage isn't configured (`s3_*` fields unset) — the field
  simply has no working upload affordance rather than erroring, matching the backend's "routes
  don't mount at all" posture.

## Related

- [Object Storage](../../core/object-storage.md) — the pictures/attachments backend and S3 configuration
- [Address Widget](address-widget.md) · [Totals Widget](totals-widget.md) — the other composite/special-purpose widgets
