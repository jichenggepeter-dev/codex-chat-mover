# Next Steps

## Phase 1 Status

Done:

- SwiftUI app scaffold.
- Project sidebar with assigned chats.
- Unassigned chat list.
- Drag-to-project confirmation.
- Simulated move progress.
- Undo of the simulated last move.
- PRD and architecture notes.
- Repo-scoped `move-chat-to-project` skill.

Verified:

```bash
swift build
```

## Phase 2: Real Read-Only Scanner

Status: completed.

Goal: read real Codex state without writing anything.

Done:

- Add `CodexPaths` for resolving `CODEX_HOME` and default `~/.codex`.
- Add read-only scanner for `state_5.sqlite`.
- Add parser for `session_index.jsonl`.
- Add locator for `sessions/**/*.jsonl`.
- Normalize projects and threads into the existing models.
- Add fixture-based smoke tests without requiring XCTest.
- Split scanner/domain code into `CodexChatMoverCore`.
- Wire the app to use live read-only scanning with sample-data fallback.

Verification:

```bash
swift run ScannerSmokeTests
swift build
```

Non-goals:

- No writes to `~/.codex`.
- No move transaction yet.
- No sidebar repair.

## Phase 3: Safe Move Transaction

Status: implemented, pending manual validation against a real closed Codex
Desktop session.

Goal: implement one real move with backup and undo.

Done:

- Detect whether Codex Desktop is running.
- Require Codex to be closed before moving.
- Create backups in `~/Library/Application Support/Codex Chat Mover/Backups`.
- Keep the latest 10 backups.
- Update sqlite thread `cwd` and session JSONL `cwd` fields.
- Write Markdown and cleaned JSON copies into the target project.
- Rescan and verify the new project assignment.
- Support undo of the most recent move.
- Store backup manifests so Undo can restore original files.

Non-goals:

- No batch moves.
- No repair mode.
- No cloud thread handling.

Validation still needed:

- Run the app with Codex Desktop closed.
- Move one low-risk thread into a test project.
- Reopen Codex and confirm the sidebar refreshes as expected.
- Use Undo Last Move and confirm original metadata is restored.
