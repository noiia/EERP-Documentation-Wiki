# Chatter Panel

A per-record comment/activity feed, shown beside or below a form, resizable. Backed by
[`internal/chatter`](../../core/record-anchored-services.md#chatter).

---

## Enabling it

```ts
const formView: ViewDescriptor = {
  entity: 'crm',
  viewType: 'form',
  fields,
  showChatter: true,
}
```

Admins can also override chatter visibility workspace-wide independent of the descriptor
(`chatter-visibility.ts`) — a module's own `showChatter: true` is the default a workspace can then
turn off, not an unconditional guarantee it always shows.

## What posts to it

- **User comments** — typed directly into the panel's composer. `Ctrl`/`Cmd`+`Enter` sends.
- **Automatic edit logs** — after a successful form save, the frontend posts a `kind: "log"` entry
  summarizing which fields changed (`summarizeFieldChanges`). The backend never diffs a record's
  fields itself — it only stores whatever the caller posts.
- **System messages from other subsystems** — e.g. [Cron](../../core/cron.md) posts a `kind: "log"`
  message when a scheduled run's permission check fails, since a background scheduler has no live
  HTTP caller to return an error to.

## Pitfalls

- Chatter is append-only — there is no edit or delete on a posted message. Don't build UI that
  assumes a message can be corrected after the fact; post a follow-up instead.
- The panel's presence doesn't gate what it shows — any message anchored to a record a user can
  already read is visible in the feed. There's no per-message visibility rule beyond the record's
  own read permission.

## Related

- [Record-Anchored Services → Chatter](../../core/record-anchored-services.md#chatter) — the backend model and routes
- [Form Chrome](form-chrome.md) — the other always-present form-adjacent UI
- [Background Cron Scheduler](../../core/cron.md) — a system-message producer into this same feed
