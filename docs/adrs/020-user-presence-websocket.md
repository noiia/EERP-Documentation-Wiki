# ADR-020: User presence over a direct-to-Go WebSocket

**Status**: Accepted
**Date**: 2026-09-14

---

## Context

The request was live user presence — online/absent/offline/busy/do_not_disturb — visible as a
small colored bubble on a user's avatar wherever one appears (the top-right account avatar for
the signed-in user, chatter message authors, the Settings → Users list), with the bubble tracking
in real time, not on a page-reload cadence. A user picks their own status by clicking their
avatar; disconnecting flips them to absent immediately, and to offline after 30 minutes still
disconnected.

Nothing in the stack does anything like this today. Two established architectural rules had to be
reconciled against a requirement that doesn't fit either cleanly:

- **The BFF boundary** (`core-front/CLAUDE.md`'s State model / Conventions table): the browser
  talks only to the Next service; Next holds the session (an httpOnly cookie) and calls Go with a
  Bearer token the browser never sees. Every existing feature — including other "live-ish" ones
  like the entity-refresh bump store — fits this because it's all still request/response.
- **Every route requires a real `Authorization: Bearer` header** (`internal/middleware.JWTMiddleware`).
  A native browser `WebSocket` cannot attach a custom header to its handshake request — the
  `WebSocket` constructor takes a URL and an optional subprotocol list, nothing else.

A live socket genuinely needs a persistent connection the request/response BFF model doesn't
have. Terminating it at Next (a custom server, or an edge/route-handler hack to keep a socket
alive across Next's own process model) would have meant either abandoning `next start`'s standard
deployment (`core-front/Dockerfile`) or proxying every frame through an extra hop for no real
benefit — Next would just be relaying bytes between the browser and Go, not doing session/caching
work the way it does for every other route.

## Decision

### 1. The browser connects to Go directly — one deliberate, narrow BFF exception

The gateway (`infra/nginx/nginx.conf`) already proxies `/api/v1/*` straight to `core-back:8080`
for other reasons (external API consumers with their own Bearer token); this feature is the first
time a **browser** actually uses that path. A new `location = /api/v1/presence` block adds the
`Upgrade`/`Connection` headers and a long `proxy_read_timeout` (3600s) a persistent socket needs,
scoped to exactly this one path — every other route's proxying is untouched.

### 2. Auth reuses the existing JWT via a narrowly-scoped cookie fallback, not a new ticket flow

The Next BFF's `eerp_access` cookie (`core-front/packages/core-front/src/api/session-cookies.ts`,
`ACCESS_COOKIE`) is httpOnly but **is** the raw Go-issued access-token JWT, set with `path: '/'`.
Since the browser and the gateway share one origin, that cookie rides along on same-origin
requests automatically — including a native WebSocket handshake, cookies included, even though no
custom header can be set. So `core/internal/middleware/jwt.go` gained
`JWTOrCookieMiddleware(tokens, cookieName)`: identical to `JWTMiddleware` (both now share one
`authenticate()` helper — extracted, not duplicated), except when there's no `Authorization`
header it falls back to reading `cookieName` instead of failing closed.

This is mounted **only** on the presence route group in `core/cmd/app/main.go`
(`presenceAuthMw`) — every other route in the API keeps requiring a real Bearer header
unchanged. No new token type, no ticket-exchange endpoint, no expiry/rotation logic to get
wrong: the fallback validates through the exact same `TokenService.ParseAccess` every other
authenticated request already goes through, it just also accepts finding that token in a cookie
when the browser is the direct caller.

### 3. One route, not two, so both a live and a resting client resolve the same permission

The plain snapshot read (`GET /api/v1/presence` → JSON array) and the WebSocket upgrade (`GET
/api/v1/presence` with `Upgrade: websocket`) share the exact same path, dispatched inside
`presence.Handler.Get` on `websocket.IsWebSocketUpgrade(request)`. `derivePermissionFromRoute`
(`internal/middleware/permission.go`) names a resource from the route's static segments before
the first parameter — a second literal segment (`/presence/ws`, `/presence/me`) would have
derived a second, separate permission (`presence:ws:read`, `presence:me:write`) that an admin
would need to grant on top of `presence:presence:read`. Collapsing both onto one path keeps this
feature behind exactly the two permissions every other dedicated-handler feature in this codebase
resolves to (`presence:presence:read`/`write`), no extra grant surface for the Roles UI.

### 4. In-memory hub, single Go instance — documented, not solved for multi-instance yet

`core/internal/presence/hub.go`'s `Hub` is a `sync.Mutex`-guarded map of live connections, held in
the process's own memory. `compose.yml` runs exactly one `core-back` replica today (unlike
`pdf-service`, which explicitly scales via a NATS competing-consumer queue group —
`internal/reports/`, `docs/adr/ADR-011-pdf-report-generation.md`). An in-memory hub is therefore
lazy-correct: it's the whole set of connections that exist. If `core-back` is ever scaled to more
than one replica, presence updates from a connection on replica A would never reach a browser
connected to replica B — the fix at that point is the same pattern `pdf-service` already proves
(publish updates onto a NATS subject every replica subscribes to), not something this feature
needs to build pre-emptively for a topology that doesn't exist yet.

### 5. Effective status is a pure function, computed server-side once, pushed as-is

`core/internal/presence/status.go`'s `Effective(manualStatus *string, connected bool, lastSeen
time.Time) string` is the single place the five colors (online/absent/offline/busy/do_not_disturb)
get decided — used for the REST snapshot, the WS `"snapshot"` message on connect, every
`"update"` broadcast, and the sweep (below). `ManualStatus` only ever stores `"busy"` or
`"do_not_disturb"` (or is unset): **absent/offline are never manually selectable** — the feature
request itself frames absent/offline as purely connection-derived ("absent appears once the user
gets disconnected... until it goes offline"), so the top-bar avatar's status menu offers exactly
three choices — Online (clears the override), Busy, Do Not Disturb. A manual busy/DND override
wins even while disconnected (mirrors Teams: a flaky connection doesn't silently clear a
deliberately-set Busy). With no override, status follows the connection: online while connected,
absent for up to 30 minutes disconnected, then offline. The frontend (`presence-store.ts`) never
re-derives status from raw connection data — it only ever renders the string the server already
resolved.

### 6. The absent → offline sweep is a plain ticker, not a new scheduler type

Nothing else triggers the 30-minute transition — no request happens at the exact instant the
window elapses. `core/internal/presence/sweeper.go`'s `SweepAbsentToOffline` is a plain function
run from a `time.NewTicker(time.Minute)` loop in `main.go`, the same inline shape
`sale.ExpireOverdueQuotes`'s own hourly sweep already uses right next to it — not a new `Sweeper`
struct mirroring `internal/cron`'s heavier `Scheduler` (which exists to run many different
user-defined rows; presence has exactly one fixed job). Re-broadcasting a row still under a
busy/DND override is harmless — `Effective` reports the override unchanged, so the frontend
receives an identical, idempotent update — so no extra "already announced offline" bookkeeping is
needed either.

### 7. Presence is off the generic CRUD surface, mirroring chatter/notebook

`core/modules/presence/module.go` registers `presence.UserPresence` via
`orm.Register[...](https://github.com/noiia/EERP/blob/dev/docs/adr/orm.WithExcluded())` purely for schema migration (plus a hand-written unique
index on `(tenant_id, user_id)` — struct tags can't express uniqueness, same reasoning as
`roles(tenant_id, technical_name)`). All real traffic goes through `core/internal/presence`'s
dedicated handler, which resolves the caller's own row from the JWT identity rather than an `:id`
path parameter — there is no "read/write someone else's presence row directly" surface to gate.

## Consequences

- Presence is the one feature where the browser talks to Go without going through Next — a
  deliberate, narrow exception, not a precedent for routing other features the same way. Anything
  else needing this shape (another live channel) should get its own ADR entry, not silently reuse
  this cookie fallback on a new route.
- Single-instance-only until `core-back` scales out; see Decision 4's NATS upgrade path.
- `JWTOrCookieMiddleware` widens auth options only for the routes that explicitly opt into it —
  auditable at the `main.go` call site, not a global behavior change to `JWTMiddleware`.
- No idle-detection (browser-tab-inactive) heuristic exists — "connected" means "has an open
  WebSocket," not "the user is actively looking at the tab." A user who leaves a tab open but
  walks away still shows online until they close it or 30 minutes of true disconnection elapses.

## Reference implementation

Backend: `core/internal/presence/` (`models.go`, `status.go`, `repository.go`, `hub.go`,
`handler.go`, `sweeper.go`), `core/modules/presence/module.go`, `core/internal/middleware/jwt.go`
(`JWTOrCookieMiddleware`), `core/cmd/app/main.go` ("── Presence ──" section + the sweep ticker),
`infra/nginx/nginx.conf` (`location = /api/v1/presence`).

Frontend: `packages/core-front/src/views/presence-store.ts` (`usePresenceStore`,
`connectPresenceSocket`, `setPresenceStatus`), `presence-bubble.tsx` (`PresenceDot`,
`AvatarWithPresence`), `apps/shell/src/components/PresenceInit.tsx` (mount point),
`AppTopBar.tsx`'s `UserMenu` (self status + the status menu), `chatter-panel.tsx`'s `ChatterEntry`
(author bubble), `apps/shell/app/settings/users/descriptors.ts` + `renderers.tsx`'s tree column
builder (`widget: 'user-presence'`).
