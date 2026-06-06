# Authentication

!!! note "Implementation status"
    Authentication is a planned component. The `master_key` field in the configuration is the foundation; the JWT issuance and validation logic is not yet implemented. This page documents the intended design.

---

## Purpose

Authentication answers the question: **who is making this request?** Every non-public endpoint must establish an identity before allowing the request to proceed.

---

## Responsibilities

- Issue signed tokens on successful login
- Validate tokens on every protected request
- Inject the authenticated identity into the request context
- Refresh tokens before they expire
- Invalidate tokens on logout

---

## Intended Design: JWT with `master_key`

EERP uses stateless JWT authentication. The `master_key` from `eerp-config.json` is the HMAC signing key. No external identity provider is required for basic deployments.

```mermaid
sequenceDiagram
    participant Client
    participant AuthHandler
    participant DB as PostgreSQL
    participant JWT as JWT Library

    Client->>AuthHandler: POST /api/v{api_version}/auth/login {email, password}
    AuthHandler->>DB: SELECT user WHERE email=$1
    DB-->>AuthHandler: User row
    AuthHandler->>AuthHandler: bcrypt.CompareHashAndPassword
    AuthHandler->>JWT: Sign({sub: user_id, tenant: tenant_id, roles: [...], exp: now+1h})
    JWT-->>AuthHandler: access_token (signed with master_key)
    AuthHandler->>JWT: Sign({sub: user_id, exp: now+7d})
    JWT-->>AuthHandler: refresh_token
    AuthHandler-->>Client: {access_token, refresh_token}
```

### Token Payload

```json
{
    "sub": "01J...",
    "tenant": "01J...",
    "roles": ["admin", "crm:write"],
    "iat": 1705312200,
    "exp": 1705315800
}
```

| Claim | Description |
|---|---|
| `sub` | User ID (UUID) |
| `tenant` | Tenant/organisation ID |
| `roles` | Effective roles for permission checks |
| `iat` | Issued at |
| `exp` | Expiry (access: 1h, refresh: 7d) |

---

## Validation Middleware

On every protected request:

```mermaid
flowchart TD
    A["Extract Authorization header"] --> B{Bearer token present?}
    B -- No --> C["401 Unauthorized"]
    B -- Yes --> D["jwt.Parse(token, masterKey)"]
    D --> E{Valid signature?}
    E -- No --> F["401 Unauthorized"]
    E --> G{Expired?}
    G -- Yes --> H["401 Unauthorized\n(hint: use refresh endpoint)"]
    G -- No --> I["Inject Identity into context"]
    I --> J["Next middleware / handler"]
```

---

## Identity in Context

Downstream handlers and services retrieve the identity from context:

```go
type Identity struct {
    UserID   uuid.UUID
    TenantID uuid.UUID
    Roles    []string
}

func IdentityFromContext(ctx context.Context) (Identity, bool) {
    id, ok := ctx.Value(identityKey{}).(Identity)
    return id, ok
}
```

Services use `IdentityFromContext` when they need to filter by tenant or check roles:

```go
func (s *Service) ListContacts(ctx context.Context) ([]Contact, error) {
    identity, _ := auth.IdentityFromContext(ctx)
    return s.contacts.Query().
        Where(orm.Cond("tenant_id = $1", identity.TenantID)).
        All(ctx, s.db)
}
```

---

## Multi-Tenancy

Every entity that belongs to a tenant has a `tenant_id` column. The authentication middleware injects the tenant ID from the token; services filter by it. The ORM provides no automatic tenant filter — services are responsible for applying the `WHERE tenant_id = $1` condition.

---

## Token Rotation

```mermaid
sequenceDiagram
    participant Client
    participant Server

    Client->>Server: POST /api/v{api_version}/auth/refresh {refresh_token}
    Server->>Server: Validate refresh_token (signature + expiry)
    Server->>Server: Issue new access_token (1h) + new refresh_token (7d)
    Server-->>Client: {access_token, refresh_token}
    note over Server: Old refresh_token is now invalid (rotation)
```

Refresh tokens are single-use. Presenting a used refresh token invalidates the entire session (theft detection).

---

## Interactions

```mermaid
graph LR
    Config["eerp-config.json\n(master_key)"] -->|signs with| JWT["JWT Library"]
    AuthMiddleware -->|validates with| JWT
    AuthMiddleware -->|injects| Context["request context\n(Identity)"]
    LoginHandler -->|issues| JWT
    Services -->|reads from| Context
    Permissions -->|reads roles from| Context
```

---

## Extension Points

| Extension | How |
|---|---|
| External IdP (OAuth2/OIDC) | Replace `LoginHandler` with OIDC callback; map claims to `Identity` |
| Session-based auth | Replace JWT with server-side session store; keep the `Identity` context contract |
| API keys | Issue long-lived tokens with restricted roles; validate via same middleware |
| MFA | Add a second factor check between password validation and token issuance |
