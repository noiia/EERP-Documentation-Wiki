# Totals Widget

`type: 'totals', widget: 'recap'` — a live, computed recap block over a set of sibling relation
lines, e.g. a sale quote's tax-rate breakdown. Always `store: false`: it is computed client-side
from the currently-drafted lines and never part of the record's own commit payload.

---

## Descriptor

```ts
{ name: 'tax_recap', label: 'Totals', type: 'totals', widget: 'recap', store: false }
```

`TaxTotalsWidget` (the concrete renderer) sums each line's own computed total, grouped by tax rate,
recomputing whenever the draft's line items change — the same reactive posture `compute` fields
take (see [View Engine → Computed & Reactive Fields](../view-engine.md#computed-reactive-fields)),
but specialized for a relation-lines-to-recap shape rather than a single derived scalar.

## Tax pricing mode

The recap's numbers depend on the workspace's tax pricing mode
(`tax_excluded` vs. `tax_included`) — see [Settings → Tax pricing
mode](../../core/settings.md#tax-pricing-mode). Each line persists its own tax-excluded `Subtotal`
alongside `Total` at write time, so the recap sums a stable, already-computed figure rather than
re-deriving it from `UnitPrice`, which no longer safely stands in for the tax-excluded amount once
prices can be tax-inclusive.

## Related

- [Address Widget](address-widget.md) — the other composite-field primitive
- [Relation Widgets](relation-widgets.md) — the line items a totals widget typically recaps
- [Settings → Tax pricing mode](../../core/settings.md#tax-pricing-mode)
