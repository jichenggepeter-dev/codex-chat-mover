# Architecture

## Phase 1

Phase 1 creates a safe runnable app shell with sample data and clear service
boundaries. It must not read or write real Codex data yet.

## Phase 2

Phase 2 adds read-only live scanning. The app may read Codex metadata from the
user's Codex home, but it must not write to Codex state.

Targets:

- `CodexChatMoverCore`: domain models, scanners, parsers, and service protocols.
- `CodexChatMover`: SwiftUI app shell.
- `ScannerSmokeTests`: lightweight executable test runner for parser/scanner
  behavior in environments where XCTest is unavailable.

## Modules

### CodexStoreScanner

Reads Codex local state and returns normalized projects and threads.

Planned inputs:

- `~/.codex/state_5.sqlite`
- `~/.codex/session_index.jsonl`
- `~/.codex/sessions/**/*.jsonl`

### ProjectRegistry

Manages discovered, user-added, and user-created projects.

### ThreadMover

Owns the move transaction:

```text
assert Codex Desktop is closed
create backup
update sqlite metadata
update session_index.jsonl
patch session JSONL cwd/workspace payloads
write Markdown copy
write cleaned JSON copy
rescan and verify
record undo information
```

### BackupManager

Stores backups in:

```text
~/Library/Application Support/Codex Chat Mover/Backups
```

Keeps the latest 10 backups and supports undoing the most recent move.

### CodexLauncher

Reopens Codex Desktop after a successful move.

## Edit Scope

Allowed in v0.1 scaffold:

- `Package.swift`
- `Sources/CodexChatMover/**`
- `docs/**`
- `README.md`

Forbidden until the real data phase:

- Any direct writes to `~/.codex`
- Any destructive backup cleanup
- Any process termination of Codex Desktop

## Verification

Phase 1:

```bash
swift build
```

Phase 2:

```bash
swift run ScannerSmokeTests
swift build
```

Later phases should add focused tests for the move transaction before real
writes are enabled.

Phase 3:

```bash
swift run ScannerSmokeTests
swift build
```

The Phase 3 smoke runner verifies JSONL patching, project copy writing, backup
manifest restore, and the Codex-running guard. Real live-data validation should
only be done with Codex Desktop closed.
