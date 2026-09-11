# ADR-018: HTTP/2 at the Gateway Edge, and Batching Over Adopting GraphQL

**Status**: Accepted
**Date**: 2026-08

---

## Context

Two pieces of work landed together and both bear on the same question: EERP's forms fire a lot of
small relation-fetch requests (tags, contacts, any many2many), and every entity list is a REST
resource under `GET /api/v1/{table}`. Does that call shape need a different transport (HTTP/2
multiplexing) or a different API paradigm (GraphQL, so a form could ask for a record plus its
relations in one round trip) — or can the existing REST + generic-CRUD surface absorb the cost with
a smaller, local fix?

**The N+1 side**: the many-to-many tags widget and the relation-summary widget's nested resolver
each fetched their junction rows' related records with one call **per row** — a form with a handful
of linked tags fired that many extra sequential round trips on mount.

**The transport side**: Node's `undici` fetch does not speak cleartext h2c — HTTP/2 only works over
TLS in practice. Since the browser is the only real client in this BFF architecture (it never talks
to Go directly), that's also the only hop worth paying TLS complexity for.

## Decision

1. **Fix the N+1 by batching the existing REST list endpoint, not by adding GraphQL.**
   `resolveManyToManyLinks` replaces the per-row fan-out with junction list + **one** batched
   `ops.list(relatedEntity, { in: { id: [...] } })` call regardless of row count, reusing the
   generic list endpoint's existing `in[column]` filter — no backend change needed. This is
   deliberately the REST answer to a problem GraphQL is usually reached for: one query parameter
   collapses N requests to 1.
2. **HTTP/2 lands at the gateway edge only, TLS-gated, no app code changes.** `infra/nginx/
   nginx.conf`'s HTTPS server block is enabled with a self-signed dev cert, provisioned by a
   one-shot `gateway-certs` compose service before nginx starts. Plain `http://` now 301-redirects
   everything except `/healthz` to `https://` — serving the app over plain HTTP would silently
   break login once Secure cookies are the default. Next↔Go stays plain HTTP/1.1 internally,
   untouched — only the browser↔gateway hop has many small parallel requests worth multiplexing.
3. **REST + HTTP/2 multiplexing over REST + GraphQL, for this codebase's shape.** The two real
   motivations for GraphQL — collapsing N+1 fan-out, and avoiding head-of-line blocking on many
   small parallel requests — are each already covered by a smaller, local fix. GraphQL would
   additionally cost a schema/resolver layer duplicating what the generic CRUD surface + descriptor
   engine already derive automatically (List/Kanban/Calendar/Graph, field-level group gating,
   structured filters) — none of which has a GraphQL equivalent here today.

## Consequences

- Every future many2many/relation resolver should reuse `resolveManyToManyLinks` rather than
  reintroducing a per-row fan-out.
- The carousel widget's picture-metadata N+1 is still open — fixing it needs a batch endpoint on
  `internal/pictures` that doesn't exist yet.
- HTTP/2 is real only at the browser↔gateway hop; internal BFF↔Go latency sees no change.
- The REST-over-GraphQL call is scoped to the query shapes this codebase has needed so far, not a
  permanent rule — a future genuinely graph-shaped fetch requirement should reopen this ADR.

## Reference Implementation

`core-front/packages/core-front/src/views/relation-widgets.tsx` (`resolveManyToManyLinks`),
`infra/nginx/nginx.conf`, `infra/nginx/gen-certs.sh`, `compose.yml` (`gateway-certs` service). See
[HTTP Pipeline → TLS/HTTP2 Gateway](../core/http-pipeline.md#tlshttp2-edge-gateway).
