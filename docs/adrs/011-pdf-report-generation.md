# ADR-011: PDF Report Generation — External Chromium-Backed Service

**Status**: Accepted
**Date**: 2026-08

---

## Context

EERP needs server-generated PDF reports (statements, invoices, list exports) authored the same
way developers already author on-screen views — declarative descriptors, not a bespoke templating
language — with real CSS (Tailwind/MUI) styling freedom and reuse of the exact component/data
model forms already use.

Three architectures were benchmarked generating the same 250-row / ~7-page statement report:

| | Go-native (`go-pdf/fpdf`) | Typst (Rust CLI) | Headless Chromium (`chromedp`) |
|---|---|---|---|
| Cold single call | 11.4ms | 267.5ms | 493ms |
| Warm/pooled call | n/a (stateless) | n/a | 173ms |
| Throughput | 873 reports/s @ 200 goroutines | 19.9 reports/s @ 8 procs | ~19-22 reports/s @ 8-20 tabs (~3.2/vCPU) |
| Memory | ~11MB/call | ~53MB/call | ~150-190MB/browser instance |

`wkhtmltopdf` was excluded outright: archived since 2023, an unpatched CVSS 9.8 SSRF
(CVE-2022-35583), and a ~2012-era CSS engine with no Flexbox/Grid.

Go-native wins raw throughput by orders of magnitude but has no CSS box model — "use a Tailwind
class" has no meaning to a cell/grid PDF library, and reaching for it means designing and owning a
custom layout engine. Typst has excellent typography but is authored in its own markup language,
not TypeScript, and would introduce Rust into a Go-only backend that has none today (the WASM
build path is itself Go cross-compiled to WASI — see [ADR-002](002-wasm-modules.md)).

## Decision

**Render engine: headless Chromium (`chromedp`)**, chosen for CSS/Tailwind/MUI fidelity and direct
reuse of existing React components — accepting the throughput/memory cost as bounded: a 4-vCPU
replica sustains ~13 reports/s, and scaling is linear via replica count since each Chrome instance
is independent. Chromium's attack-surface objection is blunted by the threat model: the renderer
only ever navigates to URLs it (or the trusted core) constructs itself, pointing at an internal,
network-isolated `core-front` route — never attacker-supplied URLs or untrusted HTML.

**Deployment shape: standalone `pdf-service`**, not embedded in the core API process — isolates
Chromium's resource and fault domain (own container, own health check, own restart policy; the
~300-400MB Chromium footprint never lands in the core image).

**Transport v1: synchronous HTTP** (`POST /render` returns PDF bytes). The renderer sits behind a
`Renderer` interface so a NATS `QueueSubscribe` front door can be added later purely as a second
transport calling the same interface, forming a competing-consumer group with zero change to
render logic. Not built until multiple workers are actually needed.

**Report authoring: declarative `ReportDescriptor`**, mirroring the existing `ViewDescriptor`
contract — a `layout` tree of typed nodes bound to the same entity field data forms already use.

**Delivery**: the core-side handler uploads the rendered PDF to Garage (S3-compatible), mirroring
`internal/pictures`'s metadata-row/bytes-in-S3 split, and hands the client a download URL.

**Pagination**: Chromium's `Page.printToPDF` header/footer templates (`@page` margin boxes,
`counter(page)`/`counter(pages)`) cover page numbers and static titles. CSS `running()` (dynamic
per-page content) is not supported by Chromium and is a known limitation, not a bug to chase.

## Amendment: NATS Promoted to Default (2026-09)

**Status of this amendment**: Accepted

The synchronous-HTTP-first framing above described the initial rollout. The deployment has
since flipped: `eerp-config.docker.json` now sets `nats_url` (`nats://nats:4222`) instead of
`pdf_service_url`, and `core/cmd/app/main.go` picks `NewNATSPDFRenderer` whenever `nats_url` is
present — NATS wins over HTTP when both are set. `tools/pdf-service` was already starting its
NATS worker unconditionally (its own `NATS_URL` env var was always set in `compose.yml`); only
the *caller's* choice of transport was still defaulting to HTTP. That is now the flipped default:
a fresh `docker compose up` routes every render through NATS request-reply, with N `pdf-service`
replicas as competing consumers on the same queue group — true horizontal scaling with no code
change per replica, exactly what Decision 3 pre-wired for.

The direct-HTTP path (`httpPDFRenderer`, `pdf_service_url`) is untouched in code and still works —
clearing `nats_url` from the config reverts a deployment to it — but it is no longer what ships by
default. `core-back` now also declares a `depends_on: nats` (`service_healthy`) in `compose.yml`,
matching `pdf-service`'s own dependency on the same broker.

## Consequences

- `compose.yml` gains a `pdf-service` entry; Chromium version/security patching is an explicit,
  narrow-blast-radius operational responsibility.
- Report authors write `ReportDescriptor`s with real CSS classes — the same skillset as writing a
  view.
- Throughput scales via replica count past ~2× a single instance's vCPU count in concurrent tabs,
  not by raising per-instance concurrency further.
- NATS integration is deferred but pre-wired via the `Renderer` interface.

## Reference Implementation

`tools/pdf-service` (Go, `chromedp`), `core/internal/reports/` (`PDFRenderer` interface: an
`httpPDFRenderer` calling `pdf-service` directly, and a `natsPDFRenderer` for horizontal scaling).
See [Reports & PDF Generation](../core/reports.md).
