# Mail: Outbox & Templates

`core/internal/mail` sends every transactional email (booking confirmations, account
verification, reminders). Two rules shape it:

1. **An email commits with the business write.** Code never sends inline from a request; it
   enqueues a row in the same transaction, and a background sender delivers it.
2. **An email is a template.** Bodies are registered, translatable and overridable per
   workspace — never concatenated in code. See [ADR-028](../adrs/028-mail-templates.md).

```mermaid
sequenceDiagram
    participant R as Request handler
    participant DB as Postgres
    participant S as mail.Sender (every 30 s)
    participant SMTP as SMTP relay
    R->>DB: BEGIN; business write; INSERT mail_outbox; COMMIT
    S->>DB: claim ≤ 20 due rows FOR UPDATE SKIP LOCKED
    S->>SMTP: send
    alt accepted
        S->>DB: mark sent
    else error
        S->>DB: attempts+1, retry in 2^attempts min (failed after 5)
    end
```

## Sending an email

```go
// 1. Declare the template once, at init().
func init() {
    mail.RegisterTemplate(mail.TemplateDef{
        Key:   "crm.lead_assigned",
        Label: "Lead assigned",
        Vars:  []string{"name", "lead"},
        Defaults: map[string]mail.Content{ // "en" is required — the last fallback
            "en": {Subject: "New lead: {{lead}}", HTML: "<p>Hello {{name}}, {{lead}} is yours.</p>"},
            "fr": {Subject: "Nouveau prospect : {{lead}}", HTML: "<p>Bonjour {{name}}, {{lead}} vous est attribué.</p>"},
        },
    })
}

// 2. Render it in the recipient's language and enqueue it in the write's transaction.
err := orm.Transact(ctx, db, func(tx *orm.Tx) error {
    // … business write through tx …
    locale, err := mail.ResolveLocale(ctx, tx, tenant, &userID)
    if err != nil { return err }
    msg, err := mail.Render(ctx, tx, tenant, "crm.lead_assigned", locale,
        map[string]string{"name": user.Name, "lead": lead.Name})
    if err != nil { return err }
    msg.TenantID, msg.To = tenant, user.Email
    return mail.Enqueue(ctx, tx, msg)
})
```

- `Render` does `{{var}}` substitution only; values are HTML-escaped and the text part is derived
  from the HTML.
- Language: account `preferred_locale` → workspace `i18n.default_locale` → `en`. Lookup goes
  locale → base language → `en`, a workspace override beating the code default at each step.
- `Message.Attachments` (`Filename`, `ContentType`, `Data`) turn the message into
  `multipart/mixed` — calendar invites use it.

## Delivery

- `mail.Sender` starts only when `smtp_host` is set (unset = emails stay queued).
- Claims use `FOR UPDATE SKIP LOCKED`, so several `core-back` processes are safe.
- Delivery is **at-least-once**: a crash between the relay accepting and the COMMIT re-sends.
- Admin view: `GET /api/v1/mail_outbox`, `POST /api/v1/mail_outbox/:id/retry`
  (`mail_outbox:mail_outbox:*`) — Settings → Website → Outgoing emails.

| Config | Meaning |
|---|---|
| `smtp_host`, `smtp_port` | the relay |
| `smtp_from` | sender address |
| `smtp_user`, `smtp_password` | credentials; with only a password, the login is `smtp_from`'s address (OVH, Gmail, Microsoft 365 mailboxes) |
| `smtp_tls` | `starttls` \| `implicit` \| `none` |

Boot refuses a password over `none` to a remote host, and warns when a remote host has no
credentials — the usual cause of `530 not authenticated`. In dev, the `mailpit` service catches
everything (UI on `127.0.0.1:8025`).

## Workspace overrides

Settings → **Email templates** edits every registered template per language:

| Route (`settings:mail_templates:*`) | Purpose |
|---|---|
| `GET /api/v1/settings/mail_templates` | every template, its variables, defaults and overrides |
| `PUT /api/v1/settings/mail_templates/:key/:locale` | save an override |
| `DELETE /api/v1/settings/mail_templates/:key/:locale` | back to the code default |

Bodies are sanitized to an allowlist on save, and an unknown `{{variable}}` is a 400 — a typo
can't silently ship an empty placeholder.

!!! warning "Pitfalls"
    - Never send from a request: a slow relay would fail the business write.
    - Don't build bodies by string concatenation — register a template.

## Related

- [Events & Booking](events.md) — the main producer · [Configuration](configuration.md)
