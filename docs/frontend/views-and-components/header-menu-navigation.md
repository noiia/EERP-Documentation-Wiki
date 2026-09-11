# Header Menu & Navigation

The per-app top-bar menu system that replaced the older `ModuleNav` component — a per-app dropdown
listing that app's routes, auto-populated from descriptors, plus the landing-page tiles that open
each app.

---

## Auto-populated top-bar menus

Every `tree`, `catalog`, and `dashboard` route contributes an entry to its app's top-bar menu
automatically, labeled from `navLabel` (falling back to a derived label from the route path) unless
`hideFromTopBar: true`:

```ts
{ path: '/crm/contacts', descriptor: { ...listView, navLabel: 'Contacts' }, permission: 'crm:contacts:read' }
{ path: '/crm/internal-report', descriptor: { ...reportView, hideFromTopBar: true }, permission: 'crm:contacts:read' }
```

## Hand-placed menu entries

A module can also register a menu entry that isn't tied to a single route, via
`registerHeaderMenu` — used for cross-cutting entries that don't map to one descriptor.

## Landing-page tiles

The shell's landing menu (`Menu.tsx`) shows one tile per app the caller has permission to open,
using each module's `display_name` (never its internal `name` — a module renamed internally
doesn't change what users see) and an icon resolved from the Font Awesome registry
(`icons.ts`'s `byPrefixAndName`, a local shim over the free icon set requiring no paid Kit
subscription). A tile opens the app's `routes[0].path` — see [Dashboard View → the assembler's
route order](dashboard-view.md) for why a module's route array order matters for this.

```json
// module.json
{ "app_mode": true, "menu_icon": "building" }
```

`app_mode` decides whether a module gets a tile at all; a module without one (or without a
`module.json`) is never offered as an app to open — see [Module System → module.json
fields](../../core/module-system.md#modulejson).

## Related

- [Catalog View](catalog-view.md) — shares the same icon registry
- [Module System](../../core/module-system.md) — `app_mode` and `display_name`
