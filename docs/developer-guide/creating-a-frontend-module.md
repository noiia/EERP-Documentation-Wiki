# Creating a Frontend Module

This guide adds a user-facing view to a module. The goal of the frontend engine is that **a real entity needs only a folder and a descriptor** — no controllers, no renderers, no host edits. If you find yourself writing a custom component, stop: that is an [engine gap](../frontend/view-engine.md) to fix in `@eerp/core-front`, not a per-module feature.

Read [Frontend Overview](../frontend/index.md) and [Module Discovery](../frontend/module-discovery.md) first. This guide uses the existing CRM module as the worked example.

---

## Prerequisites

- A module folder under a `module_root` path from the repo-root `eerp-config.json` (e.g. `core/modules/crm`).
- A Go service exposing the entity's routes — `/{entity}/` and `/{entity}/{id}`. The frontend `entity` string maps straight to this route prefix. See [Creating a Go Module](creating-a-go-module.md).

---

## 1. Declare the views in `module.json`

List each view file under `static_files.views`. The discovery codegen resolves these to `<module>/views/<file>` at build time.

```json
{
  "active": true,
  "type": "go",
  "name": "crm",
  "display_name": "CRM",
  "version": "0.0.1",
  "static_files": { "views": ["CrmViews.ts"] },
  "is_service": true,
  "auto_install": true
}
```

---

## 2. Add `@eerp/core-front` as a dependency

The module's `package.json` depends on the engine (link it for local dev). The engine *is* the frontend ABI — descriptors, the `FrontModule` type, and (transitively) the renderers all come from it.

```jsonc
{
  "name": "@eerp-modules/crm",
  "dependencies": { "@eerp/core-front": "workspace:*" }
}
```

---

## 3. Write the views — descriptors only

Create `views/<File>.ts` that **default-exports a `FrontModule`**. Describe the entity's fields once and reuse them across view types. The engine derives the server loader, the Zustand store, and the renderer from each descriptor.

```ts
import type { FrontModule, ViewDescriptor } from '@eerp/core-front'

/** The record as served by Go's /crm endpoints (BaseModel + business fields). */
export interface Crm {
  id: string
  name: string
  email: string
  company?: string
  status?: string
}

const fields: ViewDescriptor['fields'] = [
  { name: 'name', label: 'Name', type: 'text', required: true },
  { name: 'email', label: 'Email', type: 'text', required: true },
  { name: 'company', label: 'Company', type: 'text' },
  { name: 'status', label: 'Status', type: 'text' },
]

// entity 'crm' maps to Go's /api/v1/crm routes (route prefix = table name).
const listView: ViewDescriptor = {
  entity: 'crm',
  viewType: 'tree',   // flat data (no parent_id) → the engine renders a DataGrid
  fields,
  permissions: ['crm:contacts:read'],
}

const formView: ViewDescriptor = {
  entity: 'crm',
  viewType: 'form',
  fields,
  permissions: ['crm:contacts:read'],
}

const crm: FrontModule = {
  name: 'crm',
  routes: [
    { path: '/crm/contacts',     descriptor: listView, permission: 'crm:contacts:read' },
    { path: '/crm/contacts/:id', descriptor: formView, permission: 'crm:contacts:read' },
  ],
}

export default crm
```

What you did **not** write: no data fetching (the server loader does it, cached with `tags:['crm']`), no Zustand store (seeded from server `initialData`), no form/grid components (the renderers dispatch on `viewType`), no Go calls (Server Actions handle writes and `revalidateTag('crm')`).

---

## 4. Pick a view type

| `viewType` | Renders | Use for |
|---|---|---|
| `form` | MUI inputs bound to a draft; Save (disabled until dirty) commits via Server Action | single-record create/edit |
| `tree` | MUI X `RichTreeView` from `parent_id`, with a flat DataGrid fallback for flat data | hierarchies *or* flat lists |
| `dashboard` | responsive grid of widget cards | summaries |

Need a view type that doesn't exist yet? That is one store factory + one renderer + one server loader path in `@eerp/core-front` — added once, available to every entity.

---

## 5. Guard with permissions

Set `permission` per route (the **server** enforces it) and optionally `permissions` on the descriptor (the **client** `<Can>` gates UI off the session mirror). The DSL is `module:resource:action` with segment wildcards — `crm:*:read`, `*:*:read`. The server check is the real one; the client mirror only paints UI. See [Permission gate](../frontend/view-engine.md#permission-gate).

---

## 6. Rebuild — discovery picks it up

Ensure the module's root is in the repo-root `eerp-config.json` `module_root` (CRM's already is), then rebuild. The codegen scans the roots, statically imports each view file, and registers its `FrontModule`. The catch-all route `app/[...module]/page.tsx` resolves the new paths, runs the guard, server-fetches, and renders.

```bash
make run-front      # dev: regenerates the manifest on start and on module.json changes
```

The generated `apps/shell/src/generated/generated-modules.ts` is **gitignored** — never commit it; it is regenerated on every build.

---

## 7. Test

Every file ships with tests (the non-negotiable rule). For a module, a unit test asserts the `FrontModule` wires the right descriptors and permissions per path:

```ts
import crm from './CrmViews'

it('guards every CRM route with crm:contacts:read', () => {
  expect(crm.routes.map(r => r.permission)).toEqual([
    'crm:contacts:read', 'crm:contacts:read',
  ])
})
```

End-to-end CRUD belongs in a `*.integration.test.ts` that is skipped unless `TEST_API_BASE` is set, with an MSW-mocked twin for CI. See [Testing](testing.md).

---

## Checklist

- [ ] View files listed in `module.json` → `static_files.views`
- [ ] `@eerp/core-front` is a dependency
- [ ] `views/*.ts` default-exports a `FrontModule` with **descriptors only**
- [ ] Each route has a `permission`; the Go routes for `entity` exist
- [ ] Module root is in `eerp-config.json` `module_root`
- [ ] Tests cover the descriptor/permission wiring
- [ ] No custom components (if you needed one, fix the engine instead)

---

## Related

- [Frontend Overview](../frontend/index.md) · [View Engine](../frontend/view-engine.md) · [Module Discovery](../frontend/module-discovery.md)
- [Creating a Go Module](creating-a-go-module.md) — the backend half of a module.
- [Creating an Entity](creating-an-entity.md) — the data model behind the views.
