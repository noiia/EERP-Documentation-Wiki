# Undo Toast

The generic recovery affordance for destructive (hard-delete-shaped) actions — a single global
toast, not a per-feature confirmation dialog. See [ADR-016](../../adrs/016-undo-toast.md) for the
full design.

---

## Using it

```ts
import { useUndoToastStore } from '@eerp/core-front'

useUndoToastStore.getState().show({
  message: 'Filter deleted',
  onRecover: () => { /* undo whatever just happened */ },
  onExpire: () => { /* only if the delete was deferred — actually commit it now */ },
})
```

No provider or context is needed — any component reaches the store directly. `<UndoToastHost />`
is mounted once, globally, in the root layout.

## Two commit timings, one API

- **Deferred-commit** — the UI updates immediately, but the actual backend delete only fires in
  `onExpire`, once the undo window has genuinely elapsed. Recovering costs zero backend calls; it
  never happened. This is how saved-filter deletion works.
- **Eager-commit-with-reversal** — the mutation already fired (matching how every other drag in
  the engine behaves). `onRecover` just reverses it — e.g. Calendar's drag-off-the-grid flow
  PATCHes the cleared date field back.

Pick whichever matches how the rest of your feature already commits — don't introduce a third
timing model.

## The one gotcha: stale closures

`onRecover` fires long after the render that created it is gone. A callback that closes directly
over that render's state can silently no-op if it has its own "already this value" guard. Route it
through a ref updated every render instead:

```ts
const latestRef = useRef(doTheThing)
latestRef.current = doTheThing

useUndoToastStore.getState().show({
  message: 'Unscheduled',
  onRecover: () => latestRef.current(previousValue), // always calls into current state
})
```

Calendar's first implementation hit exactly this bug — see [ADR-016 → Decision
5](../../adrs/016-undo-toast.md) for the postmortem.

## Limits

- Only **one** pending undo at a time, app-wide. A second `show()` immediately finalizes the first
  (firing its `onExpire`) and replaces it — there is no queue.
- Dismissing the toast (`×`) hides the banner but does **not** cancel the undo window — the
  `onExpire` timer keeps running. Only `recover()` stops it.
- No keyboard shortcut for undo exists yet.

## Related

- [Search & Filter Bar](search-filter-bar.md) — the deferred-commit adopter
- [Calendar View](calendar-view.md) — the eager-commit-with-reversal adopter
- [ADR-016: Generic Undo Toast](../../adrs/016-undo-toast.md)
