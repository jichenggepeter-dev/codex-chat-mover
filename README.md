# Codex Chat Mover

Move Codex chats into the right Codex projects.

Codex Chat Mover is a lightweight macOS app for organizing local Codex Desktop
threads. It reads your local Codex metadata, shows real projects and movable
chats, and lets you drag a chat into a project with backup and undo support.

> Experimental local utility. Codex's local metadata format is not a public API,
> so always keep backups and close Codex Desktop before moving chats.

## Why

Codex Desktop has two useful modes:

- **Chats** for projectless planning, research, and quick exploration.
- **Projects** for work tied to a local folder, Git diff, terminal, and sandbox.

Sometimes a chat starts as research and later clearly belongs inside a project.
Codex Desktop does not currently provide a native drag-to-project flow. This app
adds that workflow as a small companion utility.

## Features

- Native SwiftUI macOS app.
- Reads local Codex state from `~/.codex`.
- Filters out subagent, guardian, and internal delegation threads.
- Hides generated one-off Codex workspaces from the project sidebar.
- Shows real user projects and movable chats.
- Creates new project folders in `~/Documents/Codex/<date>/projects` by default.
- Drag a chat onto a project or a visible drop area.
- Requires Codex Desktop to be closed before metadata writes.
- Creates backups before moving.
- Keeps backup manifests for `Undo Last Move`.
- Writes Markdown and JSON copies into the target project.
- Includes smoke tests and a scanner diagnostics command.

## Safety Model

Codex Chat Mover follows a conservative move transaction:

1. Confirm Codex Desktop is not running.
2. Backup local Codex state files.
3. Update the thread's project path in sqlite metadata.
4. Patch the session JSONL `cwd` fields.
5. Write imported chat copies into the target project.
6. Rescan and verify the moved chat appears under the target project.
7. Restore from backup if verification fails.

Backups are stored under:

```text
~/Library/Application Support/Codex Chat Mover/Backups
```

Imported copies are written under the target project:

```text
.codex/imported-chats/
```

## Install From Source

Requirements:

- macOS 14 or newer
- Swift 6 toolchain
- Codex Desktop with local threads

Clone and run:

```bash
git clone https://github.com/jichenggepeter-dev/codex-chat-mover.git
cd codex-chat-mover
swift run CodexChatMover
```

Build a local `.app` bundle:

```bash
sh scripts/package-app.sh
open "outputs/Codex Chat Mover.app"
```

## Usage

1. Quit Codex Desktop.
2. Open Codex Chat Mover.
3. Select the target project in the left sidebar.
4. Drag a chat from the middle list into the right-side drop area.
5. Confirm the move.
6. Reopen Codex Desktop to refresh the sidebar.

Use `Undo Last Move` if the moved chat does not appear where expected.

## Commands

Run the app:

```bash
swift run CodexChatMover
```

Run smoke tests:

```bash
swift run ScannerSmokeTests
```

Inspect what the scanner sees:

```bash
swift run ScannerDiagnostics
```

Build:

```bash
swift build
```

## Project Structure

```text
Sources/
  CodexChatMoverApp/       SwiftUI app and interaction state
  CodexChatMoverCore/      scanner, models, backup, and move transaction
Tests/
  ScannerSmokeTests/       lightweight executable test runner
  ScannerDiagnostics/      read-only live metadata diagnostics
docs/
  PRD.md
  ARCHITECTURE.md
  NEXT_STEPS.md
scripts/
  package-app.sh
```

## Roadmap

- Add a dedicated onboarding screen.
- Add a visible scanner status panel.
- Add safer manual project allow/block lists.
- Add a dry-run move preview.
- Add signed release builds.
- Add a GitHub Actions build check.

## Limitations

- macOS only.
- Local Codex Desktop only.
- No cloud thread migration.
- No official Codex Desktop UI extension.
- Depends on Codex's current local metadata layout.

## Development

The app deliberately keeps write-capable code isolated in
`SafeThreadMover`. Scanner logic lives in `LiveCodexStoreScanner`; SwiftUI views
should not parse or mutate Codex metadata directly.

Before changing move behavior, run:

```bash
swift run ScannerSmokeTests
swift build
```

## License

MIT
