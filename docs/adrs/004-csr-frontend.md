# ADR-004: React Frontend on a Next.js Server with Zustand State

**Status**: Accepted  
**Date**: 2024 (revised 2026-06-07, revised 2026-06-16)

> **Note on the filename**: this record is still stored as `004-csr-frontend.md` for link stability, but the decision it documents has evolved away from a pure CSR strategy. See the [Revision History](#revision-history) for the full lineage.

---

## Context

EERP's frontend has gone through two prior framework decisions: SvelteKit (v1) and then React + Vite as a pure client-side-rendered (CSR) Single-Page Application (v2). The React framework choice itself is settled and is **not** reopened here — React's ecosystem depth and talent pool remain the right foundation (see the [v2 rationale](#why-the-revision-was-necessary) below).

What is revisited in this revision (v3) are two things the CSR-only SPA model left unsolved:

1. **The frontend has no server of its own.** In the v2 model the browser talks directly to the Go API. That means the browser is responsible for holding access tokens, the Go API surface is exposed directly to the public internet, and there is no place to run per-user server-side logic (request aggregation, server-side rendering, edge auth gating). For an application that already relies on `HttpOnly` refresh-token cookies (see [ADR-005](005-jwt-auth.md)), the absence of a server tier on the frontend side forces awkward compromises.
2. **Client state management was never decided.** The v2 ADR settled the framework but said nothing about how shared client state (current user, permissions, open tenant, UI state, cached lookups) is stored and propagated. Reaching for React Context for everything causes re-render cascades that hurt a data-dense ERP UI.

This revision answers both:

- **Run the frontend on a dedicated Next.js front server**, rather than shipping a static bundle with no runtime.
- **Adopt Zustand** as the client-side state store.

---

## Decision

Adopt **Next.js (App Router) running as a dedicated front server**, with **Zustand** for client-side state.

### A full Next.js front server

The frontend is no longer a static bundle. It runs as a long-lived **Node.js process** (the Next.js server) that sits between the browser and the Go backend, acting as a **Backend-for-Frontend (BFF)**:

```
Browser  ──HTTP──▶  Next.js front server (Node)  ──HTTP/JSON──▶  Go core API
```

The front server is responsible for:

- **Owning the session.** The `HttpOnly; Secure; SameSite=Strict` refresh-token cookie from [ADR-005](005-jwt-auth.md) is read and refreshed **server-side**. Access tokens are attached to outbound calls to the Go API by the front server and are never handed to browser JavaScript. This closes the gap where a CSR SPA had to hold tokens in a context reachable by any script on the page.
- **Proxying the API.** The browser talks only to the Next.js server; the Go API is not exposed directly to the public internet. The front server forwards authenticated requests to the core.
- **Server-side rendering and React Server Components.** Pages that need data render it on the server with the data already resolved, reducing the amount of client JavaScript and the number of client-side waterfalls.
- **Edge/server auth gating.** Next.js middleware rejects unauthenticated requests before any page code runs, replacing the client-side route guard the SPA relied on.
- **Unified file-system routing** and the built-in optimizations Next.js ships (automatic code splitting, image optimization, streaming).

```tsx
// core-front/middleware.ts — auth gating at the server edge
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(req: NextRequest) {
  const hasSession = req.cookies.has("refresh_token");
  if (!hasSession && !req.nextUrl.pathname.startsWith("/login")) {
    return NextResponse.redirect(new URL("/login", req.url));
  }
  return NextResponse.next();
}

export const config = { matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"] };
```

### Zustand for client state

Client-side shared state (current user, resolved permissions, active tenant, UI flags, cached reference data) lives in **Zustand stores** rather than React Context or a heavier library.

```tsx
// core-front/src/stores/session.ts
import { create } from "zustand";

interface SessionState {
  user: User | null;
  permissions: Set<string>;
  setSession: (user: User, permissions: string[]) => void;
  clear: () => void;
}

export const useSessionStore = create<SessionState>((set) => ({
  user: null,
  permissions: new Set(),
  setSession: (user, permissions) => set({ user, permissions: new Set(permissions) }),
  clear: () => set({ user: null, permissions: new Set() }),
}));

// A component re-renders ONLY when the slice it selects changes:
const canEdit = useSessionStore((s) => s.permissions.has("crm:write"));
```

Because Next.js renders on the server, each store is created **per request** on the server side (via a provider that instantiates a fresh store) to prevent one user's state from leaking into another's response.

---

## Revision History

| Version | Date | Framework | Rendering / Runtime | State | Status |
|---------|------|-----------|---------------------|-------|--------|
| v1 | 2024 | SvelteKit 5 | CSR-only (`ssr = false`), static files | Svelte stores | Superseded |
| v2 | 2026-06-07 | React + Vite | CSR-only static SPA, **no server runtime** | (undecided) | Superseded |
| v3 | 2026-06-16 | React + **Next.js (App Router)** | **SSR/RSC on a dedicated Node front server** | **Zustand** | **Current** |

### Why the revision was necessary

The v2 → v3 change is a deliberate **reversal of the "no front-end server" stance** that v1 and v2 shared. That stance was correct for what it optimized — operational simplicity (drop static files on a CDN) — but it left the frontend with no place to do server-side work. Two forces made a front server worth its operational cost:

- **Token handling.** [ADR-005](005-jwt-auth.md) deliberately keeps the refresh token in an `HttpOnly` cookie so JavaScript cannot read it. In a pure CSR SPA, the refresh/exchange flow and the access token still had to live in browser-reachable code. A Next.js front server lets the cookie be read and refreshed server-side and keeps the access token out of the browser entirely.
- **API exposure.** A static SPA must call the Go API directly from the browser, which means the API is publicly reachable and CORS must be opened up. Routing all browser traffic through the front server keeps the Go core behind the BFF.

The earlier v1 → v2 reasoning (why React over SvelteKit) still stands and is preserved here:

- **Ecosystem coverage**: enterprise-grade data grids, BI charts, PDF generators, and scheduling components ship as React packages first.
- **Available talent and onboarding**: React is the most widely known frontend framework; Svelte is a niche skill.
- **Community knowledge base**: React's volume of answered questions dwarfs Svelte's.
- **Tooling maturity**: React DevTools, Testing Library, Storybook, Playwright support.

---

## Consequences

**Positive:**

- **Tokens never reach the browser.** The front server holds the session, refreshes the `HttpOnly` cookie, and injects access tokens into server-to-core calls. This materially improves the security posture established by [ADR-005](005-jwt-auth.md).
- **The Go API is not publicly exposed.** Only the Next.js server talks to the core; the browser talks only to Next.js. CORS surface shrinks to nothing.
- **Server-side rendering and RSC.** Data-heavy pages can render server-side with data pre-resolved, cutting client-side request waterfalls and shipping less JavaScript.
- **Server-side auth gating.** Next.js middleware blocks unauthenticated requests before page code runs — no flash of protected UI while a client guard resolves.
- **Zustand keeps a data-dense UI fast.** Selector-based subscriptions mean a component re-renders only when the specific slice it reads changes, avoiding the whole-subtree re-render cascade that React Context triggers when any context value changes. See the [Rationale](#rationale) for detail.
- **Rich React ecosystem retained.** Everything the v2 decision bought (AG Grid, Recharts, TanStack Query, React Hook Form, shadcn/ui) still applies.

**Negative:**

- **There is now a server runtime in production.** This is the direct reversal of v1/v2's biggest operational advantage. A Node.js process must be deployed, scaled, monitored, and patched — the frontend is no longer "static files on a CDN." This is the main cost of the decision.
- **SSR/RSC complexity.** The server/client component boundary, hydration, and "use client" discipline add a learning curve and new classes of bugs (hydration mismatches, accidental server-only imports in client code).
- **Per-request store discipline.** Because the server renders, Zustand stores must be instantiated per request on the server to avoid cross-user state leakage. Module-level singleton stores are a server-side correctness bug, not just a style issue.
- **Two runtimes to operate.** Production now runs both the Go core and the Node front server, each with its own deploy lifecycle.
- **Migration cost.** The v2 Vite SPA must be moved to the Next.js App Router (routing, data fetching, auth flow). This is a bounded one-time cost.

---

## Rationale

### Why an entire front server for Next.js

The driving motivation is to give the frontend tier **a server of its own** rather than treating it as inert static files. Once there is a Node process between the browser and the Go core, several things that were awkward or impossible in a CSR SPA become natural:

- **It becomes the session boundary.** The whole point of the `HttpOnly` refresh cookie in [ADR-005](005-jwt-auth.md) is that browser JavaScript cannot touch it. A front server is the only place that can honor that intent end-to-end: it reads the cookie, performs the refresh against the core, and forwards short-lived access tokens on the user's behalf. The browser never holds a token.
- **It becomes a BFF.** The browser talks to one origin (the Next.js server), which aggregates and proxies calls to the Go core and, in future, to the IA and Analytics microservices on the architecture roadmap. The internal services never face the public internet.
- **It renders.** Server Components and SSR let list-heavy ERP screens arrive with data already in place, instead of mounting an empty shell and firing client requests. For an internal app on corporate networks first-paint was never the priority — but eliminating client-side request waterfalls and shrinking the client bundle is a real, ongoing win as modules accumulate.
- **It gates.** Middleware enforces authentication at the server before any route renders, which is strictly stronger than a client-side guard.

The cost — running and operating a Node process — is the same cost v1 and v2 explicitly avoided. The judgment in v3 is that the security and architecture benefits of owning the session and proxying the API now outweigh the operational simplicity of static hosting.

### Why Zustand (the performance argument)

Zustand was chosen over React Context and over heavier libraries (Redux Toolkit) primarily on **render performance** for a data-dense UI:

- **Selector subscriptions, not context propagation.** Zustand is built on `useSyncExternalStore`. A component subscribes to a *selector* (`(s) => s.permissions`), and re-renders only when that selected slice changes. React Context, by contrast, re-renders **every** consumer whenever the context value changes, regardless of which part they actually use. In an ERP screen with dozens of permission-aware widgets reading from one store, this is the difference between re-rendering one widget and re-rendering the whole page.
- **No provider tree cost.** Zustand stores are plain hooks; there is no nesting of providers and no value-identity juggling (`useMemo` on context values) to avoid spurious re-renders.
- **Transient updates for high-frequency state.** For values that change rapidly (drag positions, live counters) Zustand can update the store and notify subscribers *without* triggering a React render at all (`subscribe` / `getState`), which Context cannot do.
- **Tiny footprint.** Zustand is roughly ~1 KB. It adds negligible weight to a client bundle we are already trying to keep small now that some rendering moves to the server.
- **Lower ceremony than Redux.** No actions, reducers, or middleware boilerplate; the DX is closer to `useState` while keeping the centralized, testable store and the selective-subscription performance.

The net effect: shared client state stays centralized and testable, while components only pay for the state they actually read.

---

## Alternatives Considered

### Keep the v2 React + Vite static SPA

Continue shipping a static bundle with no front server.

**Rejected because:**
- No server tier to own the `HttpOnly` session cookie — the access-token/refresh flow stays in browser-reachable code.
- The Go API must be exposed directly to the browser, widening the public attack surface and forcing permissive CORS.
- No server-side rendering or server-side auth gating.

### Remix (full-stack React)

Use Remix instead of Next.js as the React front server.

**Considered but not selected because:**
- Next.js has the larger ecosystem, the larger talent pool, and broader community coverage — the same considerations that drove the React choice in v2.
- The team's reference material and component examples skew Next.js/App Router.

### Next.js with static export (`output: export`)

Use Next.js but export to static files, keeping the "no server" model.

**Rejected because:**
- A static export disables exactly the features this revision is adopting Next.js for: middleware, server components, server-side session handling, and the BFF proxy. It would be Next.js in name only.

### React Context for state

Use React Context/`useReducer` for shared client state instead of a store library.

**Rejected because:**
- Context re-renders every consumer on any value change, causing re-render cascades in a permission- and data-dense UI. Splitting into many contexts to mitigate this trades one problem (re-renders) for another (provider-tree sprawl).

### Redux Toolkit for state

Use Redux Toolkit as the client store.

**Considered but not selected because:**
- It carries more boilerplate (slices, actions, the store provider) and a larger bundle than Zustand for no performance advantage at this app's scale. Zustand's selector model already delivers the targeted re-render behavior we need.

### SvelteKit SSR with Node adapter

Deploy SvelteKit as a Node server (the SSR option from v1).

**Rejected (unchanged):**
- The React framework decision (v2) supersedes SvelteKit on ecosystem and talent grounds. A Svelte-based server tier reopens a decision that is already settled.

---

## Related

- [ADR-005: JWT Authentication](005-jwt-auth.md) — the `HttpOnly` refresh-token model that the front server now owns end-to-end.
- [Authentication](../core/authentication.md) — token and cookie implementation details.
- [Architecture Overview](../architecture/index.md) — where the front server sits in the layered architecture.
- [Deployment](../developer-guide/deployment.md) — operating the Node front server in production.
