# Report View

Not a routable `ViewType` — a `ReportDescriptor` registered on a `FrontModule` and rendered to PDF
by the standalone `pdf-service`. Uses the same "descriptors only" contract as an on-screen form: a
`layout` tree of typed nodes (section/table/field) bound to the same entity field data, with real
CSS classes for styling. See [Reports & PDF Generation](../../core/reports.md) for the backend
half and [ADR-011](../../adrs/011-pdf-report-generation.md) for why Chromium.

---

## Descriptor

```ts
// core/modules/sale/reports/invoice_report.ts (abridged)
export const invoiceReport: ReportDescriptor = {
  name: 'sale.invoice',
  extends: DEFAULT_REPORT_NAME,          // 'core.default': the letterhead header + footer
  entity: 'invoice',
  permissions: ['invoice:invoice:read'],
  layout: [
    { kind: 'field', name: 'subject', className: 'eerp-report-title' },
    {
      kind: 'table',
      source: 'lines',
      className: 'eerp-report-table',
      relation: { entity: 'sale_line', inverseField: 'invoice_id' },
      columns: [
        { name: 'variant_name', label: 'Product' },
        { name: 'quantity', label: 'Quantity' },
      ],
    },
  ],
}
```

`layout` is an array of nodes: `section`, `field`, `text`, `image`, `table`, `pageBreak` and `slot`.
Class names hook into `apps/shell/app/print/report/report.css`. A table column may carry a
`display` condition (the same `Condition` DSL as form fields) evaluated against the record, e.g. the
rent receipt's Tax column shown only when `display_taxes` is true.

## Inheritance: the letterhead is inherited, not imposed

A report may `extends` another by name and declare `chrome: { header?, footer? }`. The engine ships
one abstract base, `defaultReport` (`core.default`: `chrome: { header: true, footer: true }`, layout
`[{ kind: 'slot' }]`). `resolveReports` flattens a chain: the child's layout goes in the parent's
`slot` (appended without one), chrome merges key by key, `pageFormat` is inherited unless overridden,
and `abstract` is never inherited. The print route draws the letterhead (company logo + configured
address, footer) **only** when the resolved chrome asks for it.

Every shipped report extends `core.default`; a module can also ship its own abstract base for its
documents. A new report that forgets `extends` prints without the letterhead.

Register it on the module's `FrontModule.reports` array (see [ADR-019](../../adrs/019-per-model-view-files.md)
for the one-file-per-report convention) — `sale`'s assembler is the reference shape.

## Triggering a print

A report isn't auto-wired to a button — a module registers a [form actions menu](form-chrome.md)
entry whose handler calls the engine's `exportReportPDF(reportName, recordId)`:

```ts
registerMenuAction({
  entity: 'invoice',
  name: 'print',
  handler: (recordId) => exportReportPDF('sale.invoice', recordId),
})
```

See [ADR-012: Form Actions Menu](../../adrs/012-form-actions-menu.md) for why printing is "just the
first handler that happened to get registered," not a first-class concept the menu knows about.

## Company-fallback fields

`ReportFieldNode.companyFallback?: 'name' | 'address' | 'phone' | 'email'` fills a leaf from the
workspace's active-company profile **only when the record's own value is empty**, resolved at
print time (never at form-load time, since `compute`/`on_change` are synchronous-only and can't
fetch). See [ADR-013 → Decision 7](../../adrs/013-multi-company.md).

## Related

- [Reports & PDF Generation](../../core/reports.md) — the backend rendering pipeline
- [Form Chrome](form-chrome.md) — how a print trigger actually reaches a form
- [ADR-011: PDF Report Generation](../../adrs/011-pdf-report-generation.md)
