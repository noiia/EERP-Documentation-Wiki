# ADR-017: Background Cron Scheduler Over the Generic CRUD Surface

**Status**: Accepted
**Date**: 2026-08

---

## Context

The ask: scheduled background actions, user-creatable from Settings, listable/kanban/calendar/graph
like any other entity, running arbitrary Go code as a chosen user with a permission check, keeping
a downloadable execution history, and pruning that history after a sliding retention window — a
one-shot execution date, not a recurring cron-expression field.

## Decision

1. **`Cron`/`CronHistory` ride the generic CRUD surface**, unlike `chatter`/`notebook`/
   `savedfilter` — neither table needs a visibility rule the generic filter chain can't express, so
   plain `orm.Register[cron.Cron]()` (no `WithExcluded()`) gives List **and** Kanban **and**
   Calendar **and** Graph for free through the existing frontend engine. Two small hand-mounted
   additions sit on top: `POST`/`PUT /api/v1/cron` are overridden to resolve `action_code` from the
   registry, and `GET /api/v1/cron_history/:id/log` streams a run's log file (its permission still
   derives automatically from the route).
2. **Cron is one-shot (`ExecutionDate`)**, cleared to `nil` right after a run so it never re-fires.
   An action wanting to reschedule itself just sets a new `ExecutionDate` as a side effect of its
   own `Run` — no separate recurrence mechanism.
3. **Actions are Go code registered from a module's own `cron.go` file** — `internal/cron.Register(
   Action{...})` called from `init()`, mirroring `module.RegisterGoModule`'s exact shape.
   `Action.Source` is populated via `//go:embed cron.go` so the form's read-only "Code" page always
   shows the real source that runs.
4. **`ActionID` is not validated against the registry at write time** — an unknown id fails exactly
   like any other run-time problem: a failed `CronHistory` row, visible in the calendar (red) and
   the run's log.
5. **Run-as-user permission failures surface via the record's own chatter feed** — a background
   scheduler has no live HTTP caller to return an error to, so a missing-permission run posts a
   `kind: "log"` chatter message naming the run-as user, the action, and the missing permission.
6. **Local disk for log files, not S3** — a cron log is small, workspace-internal text;
   `Config.CronLogDir` keeps the feature available with zero extra infra.
7. **One poll loop does both scheduling and retention** — `Scheduler.Run` ticks every minute,
   running due crons and calling `SweepHistory` (a hard delete, since "prune history" means
   actually gone, not soft-deleted).
8. **`calendarColorField`** is a small, generic engine addition (a boolean field can tint a
   Calendar card, e.g. red for a failed run) — not a cron-only hack.

**Deliberate cuts**: no recurring schedule/cron-expression field, no manual "run now" trigger, no
Kanban archived-column auto-hide (the engine has no per-column visibility toggle), `ActionID` is a
plain text field rather than a live dropdown (descriptors are static TypeScript with no route to
ask Go what actions exist), and `HistoryRetentionYears` lives per-row on `Cron` rather than as a
workspace-wide setting (a background job has no "current company").

## Consequences

- Adding a genuinely recurring schedule later means adding an interval field and teaching the
  scheduler to compute the next `ExecutionDate` instead of clearing it — additive, no migration.
- `action_id` typos are only caught by the first scheduled run failing, not at creation time.
- Cron log files live on local disk, so a multi-instance deployment needs a shared volume for
  downloads to work from every instance — not a concern for this codebase's current single-instance
  target.

## Reference Implementation

`core/internal/cron/` (`models.go`, `registry.go`, `scheduler.go`, `retention.go`, `logstore.go`),
`core/modules/cron/` (`module.go`, `handler.go`, `cron.go`), `core/cmd/app/main.go` (`go
cronScheduler.Run(ctx)`). See [Background Cron Scheduler](../core/cron.md).
