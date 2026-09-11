# Report View

Not a routable `ViewType` — a `ReportDescriptor` registered on a `FrontModule` and rendered to PDF
by the standalone `pdf-service`. Uses the same "descriptors only" contract as an on-screen form: a
`layout` tree of typed nodes (section/table/field) bound to the same entity field data, with real
CSS classes for styling. See [Reports & PDF Generation](../../core/reports.md) for the backend
half and [ADR-011](../../adrs/011-pdf-report-generation.md) for why Chromium.

---

## Descriptor

```ts
// core/modules/sale/reports/invoice_report.ts
export const invoiceReport: ReportDescriptor = {
  name: 'sale.invoice',
  entity: 'invoice',
  layout: {
    kind: 'section',
    className: 'p-8',
    children: [
      { kind: 'field', name: 'invoice_number', className: 'text-2xl font-bold' },
      { kind: 'table', rows: 'lines', columns: ['description', 'quantity', 'unit_price', 'total'] },
    ],
  },
}
```

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
