---
name: move-chat-to-project
description: Use when the user wants to move, classify, summarize, or prepare a Codex chat/thread so it can belong to a Codex project. This skill supports the Codex Chat Mover app workflow and should not directly edit ~/.codex unless the app or user explicitly asks for an implementation step with backups.
---

# Move Chat To Project

Help the user move a Codex chat into a project safely.

## Core Behavior

When triggered, first identify which mode the user needs:

1. **Planning mode**: choose the best target project and explain the move.
2. **Summary mode**: produce a compact migration summary for a target project.
3. **Implementation mode**: modify Codex Chat Mover app code, tests, or docs.

Do not directly mutate `~/.codex` from this skill by default. Real metadata
writes must go through the app's move transaction: check Codex is closed, create
a backup, update metadata, write Markdown/JSON copies, rescan, verify, and keep
undo information.

## Migration Summary Format

When asked to summarize a chat for migration, produce:

```markdown
# Migrated Codex Chat

## Original Goal
[What the chat was trying to accomplish.]

## Important Decisions
- ...

## Current State
[What has been decided or built so far.]

## Target Project Fit
[Why this belongs in the selected project.]

## Next Prompt For Codex
[A concise prompt the user can paste into a project thread.]
```

## App Implementation Guardrails

When working on Codex Chat Mover:

- Keep the app lightweight and macOS-native.
- Prefer SwiftUI and small service boundaries.
- Keep Phase 1 using sample data until scanner tests exist.
- Never write to `~/.codex` without backup and explicit move-transaction code.
- Keep real Codex metadata writes isolated in `ThreadMover`.
- Keep parsing in scanner services, not SwiftUI views.
- Run `swift build` after code changes when the Swift toolchain is available.
