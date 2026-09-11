# Authentication (BFF)

Authentication on the frontend is owned entirely by the **Next.js server**. Credentials are exchanged server-side, the token lives in an `HttpOnly` cookie on the Next domain, and identity is resolved on the server. **The token never reaches browser JavaScript.** This is the frontend half of the model in [ADR-005](../adrs/005-jwt-auth.md); the backend's token issuance and validation are documented in [Authentication (core)](../core/authentication.md).

---

## Why the BFF owns the session

The refresh token is kept in an `HttpOnly` cookie precisely so client scripts cannot read it. Only a server can honor that end-to-end. The Next server therefore:

- exchanges credentials with Go and sets the cookie itself,
- resolves identity from the cookie on every server render (`next/headers` `cookies()`),
- attaches `Authorization: Bearer …` to outbound Go calls,
- and hands the browser only a **non-secret session mirror** (identity + permissions) for UI gating.

The browser holds no token and talks to no origin but Next.

---

## Identity

```ts
interface Identity {
  userId: string
  tenantId: string
  roles: string[]
  permissions: string[]
}
```

The server resolves `Identity` from the cookie in `apps/shell/src/lib/session.ts` for RSC and guards. On first render the client `useSessionStore` is hydrated from that server-resolved identity; its `permissions` feed `<Can>` and `usePermission` (UI gating only — the server re-authorizes every request). See [View Engine → Permission gate](view-engine.md#permission-gate).

---

## Token lifetimes

| Token | TTL | Rule |
|---|---|---|
| Access | **1 hour** | attached to Go calls by the server |
| Refresh | **7 days** | **single-use** (rotation) |

A refresh token is spent the moment it is used; reusing a spent refresh is treated as **theft**: Go kills the session, Next clears the cookie, and the user is redirected to `/login`. These TTLs come from `eerp-config.json` (`access_ttl_seconds`, `refresh_ttl_seconds`).

---

## BFF route handlers

The handlers live under `apps/shell/app/api/auth/`. The browser calls these; they proxy to Go.

| Route | Does |
|---|---|
| `POST /api/auth/login` `{email, password}` | calls Go `POST /auth/login`; on success sets an `HttpOnly; Secure; SameSite` session cookie on the Next domain and returns the non-secret identity for the client mirror |
| `POST /api/auth/logout` | clears the cookie; best-effort Go logout |
| `POST /api/auth/refresh` | server-side single-use rotation; a reused/spent refresh clears the cookie |

```mermaid
sequenceDiagram
    participant B as Browser
    participant N as Next BFF
    participant G as Go backend
    B->>N: POST /api/auth/login {email,password}
    N->>G: POST /auth/login
    G-->>N: tokens + identity
    N->>N: set HttpOnly cookie (Next domain)
    N-->>B: identity (non-secret, for session mirror)
    Note over B,N: later — access token expired
    B->>N: GET /crm/contacts (cookie)
    N->>G: GET /crm/ (Bearer) → 401 expired
    N->>G: POST /auth/refresh (single-flight)
    G-->>N: rotated tokens
    N->>G: retry GET /crm/ (Bearer)
    G-->>N: records
    N-->>B: HTML
```

The refresh+retry is driven by the engine's `ApiClient`: a single in-flight refresh promise serializes concurrent `401`s so the single-use refresh token is never spent twice. On refresh failure the client clears the cookie and signals session-expired; callers redirect to `/login`. See [View Engine → ApiClient](view-engine.md#apiclient-the-bff-data-client).

---

## Route guarding

`RequireAuth` is a **server** check: an anonymous request to a protected route is redirected to `/login` before any page code runs. The catch-all module route additionally runs the per-route **permission** guard. The login page (`app/(auth)/login/page.tsx`, a client MUI form) posts to the BFF login route, shows the server's `ApiError` message inline on bad credentials, and redirects to the intended route on success.

The net effect: an unauthenticated user cannot reach a module route (server-enforced, no flash of protected UI), bad credentials surface the backend message, and a stolen/rotated refresh cleanly logs the user out.

---

## Configuration

Server-side environment only — never exposed to the browser:

| Var | Meaning |
|---|---|
| `API_BASE` | Go backend origin |
| `API_VERSION` | API version (default `1`) → `{API_BASE}/api/v{API_VERSION}` |

Because the browser only ever talks to Next, the Go backend can sit on a private network reachable solely by the frontend service.

---

## Declarative permission gating: `<Can>`

`<Can permission="crm:contacts:write">...</Can>` (`auth/Can.tsx`) is the declarative counterpart to
the `usePermission` hook mentioned in [View Engine → Permission
gate](view-engine.md#permission-gate) — it renders its children only when the session mirror's
effective permissions satisfy the check, and nothing otherwise. Like `usePermission`, it is UI
gating only: the server re-authorizes every request regardless of what the client renders.

A second, narrower gate exists at the **field** level, independent of route permissions:
`FieldDescriptor.groups` mirrors a server-side field-group gate (see [ORM → Field-Level Group
Gating](../core/orm.md#field-level-group-gating) and
[ADR-014](../adrs/014-field-level-group-gating.md)). The server already omits a gated field from
the response entirely — the client-side check only avoids rendering an empty slot for a field the
caller was never sent, decoded from the JWT's `groups` claim into
`useSessionStore`'s `Identity.groups`.

## Related

- [ADR-005: JWT Authentication](../adrs/005-jwt-auth.md) — the token + cookie decision.
- [ADR-013: Multi-Company](../adrs/013-multi-company.md) — the per-user active-company preference alongside identity.
- [ADR-014: Field-Level Group Gating](../adrs/014-field-level-group-gating.md) — the `groups` claim and `<Can>`'s field-level sibling.
- [Authentication (core)](../core/authentication.md) — backend issuance and validation.
- [Permissions (core)](../core/permissions.md) — the permission model the DSL maps onto.
- [View Engine](view-engine.md) · [Frontend Overview](index.md).
