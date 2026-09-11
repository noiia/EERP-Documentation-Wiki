# ADR-014: Field-Level Group Gating + Role "Belongs" Inheritance

**Status**: Accepted
**Date**: 2026-08

---

## Context

Field visibility was either static (`FieldDescriptor.readOnly`/`invisible`) or data-conditional
(`states.visible`). Neither could hide a field from *some users but not others* — the only
identity-aware gate was the whole-route permission DSL. The ask: an Odoo-style security-groups
model where a field declares `groups: string[]` and a user only receives it if one of their
resolved roles' technical name — or a role they transitively "belong to" — matches.

Two gaps had to close first: roles had no stable, mutation-safe identifier separate from their
display `Name` (reused for the JWT `roles` claim), and no role-to-role relationship existed at all.

## Decision

1. **`Roles.TechnicalName`** is a new, nullable column — the slug a field's `groups` list matches
   against. `Name` is untouched. Nullable because the ORM's struct-tag auto-migration has no
   `unique` modifier, so per-tenant uniqueness is a hand-written partial index
   (`idx_roles_tenant_technical_name`) — the first unique constraint in the codebase.
2. **`role_belongs` rides the generic CRUD surface**, unlike every other auth table — deliberately,
   so the frontend's existing many-to-many tags widget drives the Roles form's "Belongs" tab with
   zero new endpoint or widget code.
3. **Group resolution is a recursive CTE**, resolved once at token-issue time. `UserRepository.
   FindGroups` walks direct roles plus every transitively-`belongs_to` role via `WITH RECURSIVE ...
   UNION` (plain `UNION`, not `UNION ALL`, so Postgres's own dedup makes cycles self-terminating —
   no application-level cycle detection needed). Baked into a new JWT `groups` claim.
4. **Groups travel through a request via `core/orm/access`**, not an import of `core/internal/auth`
   — `access.WithGroups`/`GroupsFromContext` mirrors the existing tenant-context pattern, keeping
   `core/orm` auth-agnostic.
5. **Gating is a Go `Option` at registration time**: `WithFieldGroups(map[string][]string)` (column
   → groups), read by `crud.BuildResponse`, which **omits** a gated field's key entirely — never
   nulls it — when the caller's groups don't intersect. A field with no `Groups` declared is
   completely unaffected.
6. **`FieldDescriptor.groups` on the frontend is a UX mirror, not the security boundary** — the
   server omission already makes a gated field absent from the fetched draft; the client-side check
   just avoids rendering an empty slot for a field the caller was never sent.

## Consequences

- `filter[col]=`/`search[col]=` were **not** group-aware at first — a caller without a field's
  group could filter on it and infer values from which rows matched, without the column ever
  appearing in a response. This was later closed by [ADR-015](015-search-filter-bar.md)'s
  `Repository.checkColumn`.
- `role_belongs` is the one deliberate exception to "auth tables are excluded from generic CRUD" —
  judged acceptable because the edge itself (which role implies which group) is lower-stakes than
  the identity/credential data the other auth tables guard.
- Groups are resolved at token-issue time, not per-request — a `role_belongs` edge added mid-session
  doesn't affect an already-issued token until the next refresh, the same staleness window
  `permissions` already has.

## Reference Implementation

`core/internal/auth/models.go` (`Roles.TechnicalName`, `RoleBelongs`), `core/orm/access/groups.go`,
`core/internal/auth/user_repository.go` (`FindGroups`), `core/orm/internal/registry`
(`WithFieldGroups`, `FieldMeta.Groups`), `core/orm/internal/crud/dto.go` (`BuildResponse`),
`core-front/packages/core-front/src/views/descriptor.ts` (`FieldDescriptor.groups`).
