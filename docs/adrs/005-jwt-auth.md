# ADR-005: JWT Authentication with Stateful Refresh Tokens

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-06-08 |
| Deciders | noiia |
| Branch | `28-feat-adding-authentification-service-to-the-backend` |

---

## Context

EERP needed an authentication mechanism for its HTTP API. The requirements were:

- Multi-tenant: every request must carry a tenant identity alongside the user identity.
- Role-bearing: the token must embed role names so permission checks do not require a DB round-trip on every request.
- Revocable: users must be able to log out and have their sessions invalidated.
- Theft-detectable: if a refresh token is stolen and replayed, the system must detect it and shut down the compromised session.
- No mandatory Redis or cache layer: the deployment target is a single PostgreSQL instance.

Three broad options were considered:

1. **Fully stateless JWT** — access token only, no refresh. No revocation possible without a blocklist.
2. **Session-based** — server stores session state, every request hits the DB. Simple revocation, but adds latency and statefulness to every request.
3. **Hybrid: stateless access + stateful refresh** — short-lived access tokens validated locally; refresh tokens stored in the DB for revocation and replay detection.

---

## Decision

EERP uses **HMAC-SHA256 signed JWTs (HS256) as access tokens** combined with **stateful refresh tokens stored as bcrypt hashes in PostgreSQL**.

- Access tokens are short-lived (default 1 hour, configurable via `access_ttl_seconds`).
- Refresh tokens are long-lived (default 7 days, configurable via `refresh_ttl_seconds`).
- The refresh token is delivered as an `HttpOnly; Secure; SameSite=Strict` cookie — never in the response body.
- The raw refresh token is never persisted; only its bcrypt hash is stored in the `refresh_tokens` table.
- Signing key is `master_key` from `eerp-config.json`; the server rejects startup if this key is empty or a known default.

---

## Rationale

**Why short-lived access tokens?**
Short TTLs mean that even if an access token is intercepted, it expires quickly. No revocation check is needed on every request — the JWT middleware validates the signature and expiry locally without a DB query.

**Why store refresh tokens in the DB instead of signing them as JWTs?**
A signed refresh JWT cannot be revoked without a blocklist. Storing a hash in the DB gives full revocation capability (per-token and per-user) at the cost of one DB query per refresh operation. Since refresh operations are infrequent (at most once per hour), this trade-off is acceptable.

**Why bcrypt hash on the refresh token?**
The refresh token is effectively a long-lived credential. If the `refresh_tokens` table is leaked (e.g. via a SQL injection or backup exposure), bcrypt hashes cannot be reversed to obtain live tokens. This is the same protection applied to passwords.

**Why replay detection via `RevokeAll`?**
If a refresh token is used twice, one of the two users is an attacker. Since it is impossible to know which session is legitimate, revoking all sessions for the user is the conservative and correct response. The legitimate user is forced to log in again; the attacker's stolen token is invalidated.

**Why HttpOnly cookie for the refresh token?**
An `HttpOnly` cookie is inaccessible to JavaScript, preventing theft via XSS. `SameSite=Strict` prevents CSRF. Delivering the refresh token in the response body would expose it to any JavaScript running on the page, including third-party scripts.

**Why HS256 instead of RS256?**
EERP is a self-contained framework without an external identity provider. Symmetric signing (HS256) is simpler to operate — there is only one secret to manage. RS256 would be preferred if EERP needed to share token validation with external services that cannot access the signing key.

---

## Consequences

### Positive

- Requests to protected endpoints require no DB query for auth (JWT validated locally).
- Sessions are fully revocable (individual token or all tokens for a user).
- Replay attacks on stolen refresh tokens are detected and shut down automatically.
- A DB breach does not expose live refresh tokens (bcrypt hashes only).
- No Redis or external cache dependency.

### Negative / Trade-offs

- Each token refresh requires one DB write (revoke old) and one DB write (store new hash) plus one DB read (lookup existing token). This is acceptable given refresh frequency.
- `master_key` is a single point of failure: all issued tokens become forgeable if the key is leaked. This is mitigated by the startup guard that rejects empty or known-default keys, and by standard secret management practices (environment variable injection, never committed to source control).
- Access tokens cannot be revoked before their natural expiry. A one-hour window exists between a forced logout and full access token invalidation. Handlers that require immediate revocation (e.g. privilege de-escalation) must check the `revoked` flag independently.
- In a multi-instance deployment, each instance signs and validates tokens independently with the same `master_key`. This is correct and requires no coordination, but key rotation requires a coordinated restart.

---

## Subsequent Hardening

The original decision stands; the following refinements were made afterwards and are noted here to keep the record current:

- **Atomic refresh rotation.** The revoke-old + store-new writes described under *Consequences* now run inside a single transaction (`orm.Transact`), so a partial failure can never leave a user with every token revoked and no replacement.
- **Constant-time login.** The unknown-user branch runs a real bcrypt comparison against a dummy hash generated at `bcrypt.DefaultCost`, so login timing no longer reveals whether an email exists.
- **Rate-limited auth endpoints.** `/api/v1/auth/*` is rate-limited per client IP to blunt brute-forcing (`auth_rate_limit_per_minute`).
- **Tenant isolation moved into the framework.** Row-level tenant scoping is now enforced automatically by the generic CRUD layer for any table with a `tenant_id` column (fail-closed), rather than relying on each service to filter. See [ORM → Tenant isolation](../core/orm.md#tenant-isolation).
- **Auth tables are not exposed via generic CRUD.** `users`, `roles`, `permissions` and `refresh_tokens` are registered for migration but excluded from the HTTP surface (`orm.WithExcluded()`).

## Related

- [Authentication](../core/authentication.md) — implementation details
- [Permissions](../core/permissions.md) — how roles in the token are used for access control
- [HTTP Pipeline](../core/http-pipeline.md) — middleware stack that enforces this design
