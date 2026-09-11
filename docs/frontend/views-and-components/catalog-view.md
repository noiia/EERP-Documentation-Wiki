# Catalog View

`viewType: 'catalog'` — icon/title/subtitle rows, an app-picker-style list rather than a data grid.
The App Store's own module listing is the reference example (see [Module System → Live
Activation](../../core/module-system.md#live-activation-no-restart)).

---

## Descriptor

```ts
const catalogView: ViewDescriptor = {
  entity: 'modules',
  viewType: 'catalog',
  fields, // still used for permission/relation plumbing, not directly rendered as columns
  catalog: {
    titleField: 'display_name',
    subtitleField: 'description',
    iconField: 'icon', // a Font Awesome icon name — see Header Menu & Navigation
  },
  permissions: ['modules:modules:read'],
}
```

## When to reach for it

Use `catalog` instead of `tree`/List when the entity is fundamentally a **pickable list of
things**, not tabular data a user filters/sorts — an app directory, a template gallery, a preset
list. If users need to filter, sort, or bulk-act on rows, [List View](list-view.md) is the better
fit; catalog intentionally has none of the [search/filter bar](search-filter-bar.md)'s machinery.

## Related

- [List View](list-view.md) — the tabular sibling
- [Header Menu & Navigation](header-menu-navigation.md) — the same Font Awesome icon registry backing landing-menu tiles
