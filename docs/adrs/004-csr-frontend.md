# ADR-004: CSR-Only Frontend (No SSR)

**Status**: Accepted
**Date**: 2024

---

## Context

EERP's frontend is built with SvelteKit, which supports both Client-Side Rendering (CSR) and Server-Side Rendering (SSR). The choice between them has implications for deployment architecture, performance characteristics, and developer experience.

Key considerations:

1. **Deployment topology**: Where does the SvelteKit server run?
2. **SEO**: Does EERP need search engine indexing?
3. **Time-to-first-byte**: Does the initial page load need to be fast for unauthenticated users?
4. **Separation of concerns**: Should the frontend have its own server, or should it be purely static files?

---

## Decision

Configure SvelteKit as **CSR-only** (no SSR) by exporting `ssr = false` from `+layout.ts`:

```typescript
// core-front/src/routes/+layout.ts
export const ssr = false;
```

The built output is a static SPA (HTML + JS + CSS) with no Node.js server. It communicates with the Go backend exclusively over HTTP/JSON.

---

## Consequences

**Positive:**
- **Simple deployment**: The frontend is just files. It can be served from a CDN, an S3 bucket, nginx, or any static file server. No Node.js process to manage.
- **Decoupled infrastructure**: The frontend and backend can be deployed, scaled, and updated independently. The Go backend can serve a different region from the frontend CDN.
- **No server-side secrets in frontend**: All sensitive logic and credentials stay in the Go backend.
- **Simpler backend**: The Go backend only serves a JSON API; it does not need to know about frontend routing or HTML generation.

**Negative:**
- **SEO limitations**: Client-rendered HTML is not optimal for search engines. For an internal ERP application this is irrelevant — the app is behind authentication and not indexed.
- **Slower first paint**: The browser downloads JS, executes it, then makes API calls. SSR can show content faster on first load.
- **All data fetching in the browser**: There is no server-side data pre-fetching. Every page must load its data after the JS executes.

---

## Rationale

EERP is an internal business application. It is:

- **Not indexed by search engines**: All pages are behind authentication.
- **Used by logged-in employees**: First-paint performance is less critical than for public-facing apps; the login screen is the only public page.
- **Deployed in enterprise environments**: Simple deployment (static files on a CDN or behind nginx) reduces operational complexity.

The trade-offs of SSR (faster first paint, better SEO) do not apply to EERP's use case. The benefits of CSR (simpler deployment, decoupled infrastructure) do.

---

## Alternatives Considered

### SvelteKit SSR with Node.js adapter

Deploy SvelteKit as a Node.js server alongside the Go backend.

**Rejected because:**
- Adds a third runtime (Node.js) to the production environment.
- Requires managing the Node.js process lifecycle, memory, and crashes.
- No SEO or first-paint benefit that justifies the added complexity for an internal app.

### SvelteKit SSR rendered by the Go backend

Embed SvelteKit's server inside the Go process.

**Rejected because:**
- Not feasible: the Go process and the Node.js server are different runtimes.
- Would require a sidecar process anyway, defeating the purpose.

### Separate React / Vue app

Use a different frontend framework.

**Rejected because:**
- SvelteKit 5 provides excellent DX with Svelte's compile-time reactivity model.
- The bundle size advantage of Svelte (no virtual DOM) is meaningful for enterprise apps used on corporate laptops that may have slow networks.
