# Codex Chat Mover PRD

## Product Intent

Codex Chat Mover is a lightweight macOS app that helps a Codex user move chats
that are not in known projects into the correct project. The user experience
should feel like a small native utility: inspect chats, drag one onto a project,
confirm, move, then reopen Codex.

## Target User

Power users of Codex Desktop who often start projectless chats, later realize a
chat belongs in a project, and want a direct way to reorganize it.

## MVP Scope

- Native macOS SwiftUI app.
- Automatically discover Codex projects.
- Allow users to add an existing folder or create a new project folder.
- Show projects on the left with their assigned chats.
- Show chats outside known projects on the right.
- Support title/date search.
- Drag a chat to a project to move it.
- Require Codex Desktop to be closed before real metadata writes.
- Create a backup before moving.
- Keep the latest 10 backups.
- Support undo for the most recent move.
- Write Markdown and cleaned JSON copies into the target project.
- Reopen Codex Desktop after a successful move.

## Non-Goals

- No Windows support in v0.1.
- No cloud thread migration.
- No Codex Desktop sidebar UI injection.
- No account system.
- No full-text search in v0.1.
- No broad sidebar repair tool in v0.1.

## User Flow

1. Open Codex Chat Mover.
2. On first launch, show a short safety note.
3. Scan local Codex data.
4. Review projects and unassigned chats.
5. Drag a chat onto a project.
6. Confirm the move.
7. If Codex Desktop is open, require it to be closed.
8. Create backup.
9. Update Codex metadata.
10. Write Markdown and JSON copies to the target project.
11. Verify the moved chat now resolves to the project.
12. Show completion with Open Codex, Reveal Backup, and Undo Last Move actions.

## Completion Copy

Success:

```text
Moved and verified

Your chat was moved to "{Project Name}". Open Codex Desktop to refresh the
sidebar and continue working.
```

Codex still open:

```text
Close Codex Desktop to continue

Codex Chat Mover updates local Codex metadata. Codex Desktop must be closed
first to prevent conflicts while your chat history is being moved.
```
