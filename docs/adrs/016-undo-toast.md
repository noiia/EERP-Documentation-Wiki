# ADR-016: A Generic Undo Toast as the Default Hard-Delete Affordance

**Status**: Accepted
**Date**: 2026-08

---

## Context

Two unrelated features each needed to let a user recover from a destructive action without a
blocking confirmation dialog: the search bar's saved-filter delete (a real, owner-only hard
delete), and the Calendar view's drag-a-record-off-the-grid flow (which used to block on a
confirmation dialog, inconsistent with every other drag in the engine, all of which act
immediately and revert-on-error). Building a one-off mechanism for each would repeat the same
"bespoke, non-reusable UI" problem [ADR-012](012-form-actions-menu.md)'s form actions menu solved
for custom actions.

## Decision

1. **One plain Zustand store, one pending slot, no queue.** `useUndoToastStore` holds at most one
   `{ id, message, onRecover, onExpire? }`. A second `show()` while one is pending immediately
   fires the first's `onExpire` and replaces it — sized to the two adopters that exist today, not
   to a hypothetical stacked-notifications future.
2. **`onRecover` required, `onExpire` optional** — covering both commit timings a delete can have:
   *deferred-commit* (saved-filter delete: the chip disappears immediately, the actual backend
   delete only happens in `onExpire` once the window elapses — recovering costs zero backend
   calls), and *eager-commit-with-reversal* (Calendar's drag-off: the field PATCH already fired
   immediately; `onRecover` just PATCHes the prior value back).
3. **Dismiss hides the banner; it does not cancel the undo window** — the `onExpire` timer keeps
   running. `recover()` is the only path that stops it.
4. **Mounted once, globally, no provider** — `<UndoToastHost />` mounts once in the root layout;
   any component reaches it via `useUndoToastStore.getState().show(...)`, no context threading.
5. **A triggering component must route `onRecover` through a ref, not a bare closure** —
   `onRecover` fires long after the render that created it is gone. Calendar's first attempt
   captured stale state directly in the closure, so its own "no-op if already this value" guard
   silently swallowed the recovery. The fix: a ref updated every render so the callback always
   calls into current state.

## Consequences

- Only one hard delete can be "pending undo" at a time app-wide — a real queue is the documented
  upgrade path if that changes.
- `onExpire`/`onRecover` correctness is the caller's responsibility; a future adopter forgetting
  the ref-indirection pattern reintroduces the same stale-closure bug.
- No keyboard shortcut for undo exists yet.

## Reference Implementation

`core-front/packages/core-front/src/views/undo-toast.tsx` (`useUndoToastStore`, `UndoToastHost`),
`apps/shell/app/layout.tsx` (mount point), `views/search-bar.tsx` (deferred-commit adopter),
`views/calendar-renderer.tsx` (eager-commit-with-reversal adopter, `moveFieldRef`).
