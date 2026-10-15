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

Only the **current app's** menus show in the top bar. Each app gets one menu per listed route, any
menu it registers, and always a trailing **Configuration** menu with a *Settings* line to
`/settings/apps/<module>`. A module adds lines — or a whole menu — with `registerHeaderMenu`:

```ts
registerHeaderMenu('event', 'configuration', {
  entries: [{ kind: 'line', label: 'Availability', path: '/event/availability', permission: 'event_availability:event_availability:read' }],
})
```

Calls are additive (same `(module, name)` appends; a `group` merges into a same-labeled group);
nodes are one level deep (`line`, or `group` of lines). A menu whose permitted content is a single
line navigates directly instead of opening a one-item dropdown. When the row doesn't fit, it
collapses into one icon opening a two-level drill-down menu.

## Top bar layout

From left to right: the active company's **logo** (also the upload button for holders of
`company:company:write`), the breadcrumb, the app's menus, then the
[notification bell](../../core/notifications.md#frontend), the **company switcher** and the account
menu (with presence status, see [Live Channel](../../core/live-channel.md)).

Below 768 px (`layout.topBarCompactWidth`) the bar compacts: the breadcrumb becomes a single
`angles-right` icon listing every visited crumb (its first line is home), and the company switcher
shows only its building icon. Icons grow slightly on phones for finger taps.

## ERP paths

Module paths stay relative (`/crm/:id`); the ERP lives under `/app`, added by `erpPath()` wherever
a link is emitted (`router.push`, `<Link href>`, redirects). Old bare paths 307 to `/app/…`. See
[Website → Routing](../../core/website.md#routing-path-or-host-mode).

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
