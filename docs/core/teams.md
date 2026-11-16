# Teams

The Teams app (`core/modules/teams`, `type: go`, `app_mode: true`) gives staff chat and shared files
inside the ERP. Design: [ADR-038](../adrs/038-teams.md).

## What it offers

- **Teams** with channels (each starts with `general`) and one-to-one **direct** conversations.
- Messages with attachments, @mentions (a personal notification in the `teams` category), unread
  counts, emoji reactions and soft delete (no edit).
- **Private conversations**: a channel's `restricted` flag plus its access list (users and per-team
  **groups**). Only an access PUT changes the flag, so deleting a group never reopens a channel.
- **Folders and files** per team, shareable with specific users; a channel may link one folder, and
  files sent in it are stored there. Requires object storage (`s3_*`); without it chat still works and
  uploads answer 503.

## Access

Every table is off the generic CRUD surface. Routes under `/api/v1/teams` take a JWT only (no
permission middleware) plus an active-module gate (404 while inactive). Per-team roles decide the
rest: `guest` reads, `member` also posts, reacts, uploads and shares (editing only what they
created), `owner` everything; the last owner can't leave or be demoted (409). Non-members get
**404, never 403**.

## Live frames

`chat_message`, `chat_reaction` and `chat_message_deleted` frames go through the
[live channel](live-channel.md) to the channel's audience only, built per viewer (hidden files
redacted). The hub is single-instance: with several `core-back` replicas, frames reach only users on
the replica that handled the write.

## Pitfalls

- Never `Hub.Broadcast` a chat frame.
- A new handler must do its own role check.
- A new upload route must match a `BodyLimitExempt` entry (see [HTTP Pipeline](http-pipeline.md)).
- Teams files (`chat_attachment`, `team_file`) are included in database extractions
  ([Database Management](database-management.md)).
