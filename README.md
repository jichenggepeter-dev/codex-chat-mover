# Codex Chat Mover

A lightweight macOS app for moving Codex chats into the right Codex projects.

This project starts with a safe SwiftUI scaffold and sample data. The real Codex
metadata scanner and move transaction will be added behind explicit backups and
Codex Desktop process checks.

## MVP

- macOS SwiftUI app
- Project sidebar with assigned chats
- Unassigned chats list
- Drag a chat onto a project
- Confirm move and show a progress flow
- Later: update Codex local metadata, write Markdown/JSON copies, keep backups
- Current: includes a guarded move transaction that requires Codex Desktop to be
  closed before real metadata writes.

## Run

```bash
swift run CodexChatMover
```

## Verify

```bash
swift run ScannerSmokeTests
swift build
```

## Docs

- [PRD](docs/PRD.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Next Steps](docs/NEXT_STEPS.md)
