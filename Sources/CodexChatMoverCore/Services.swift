import AppKit
import Foundation

public protocol CodexStoreScanning: Sendable {
    func scan() throws -> CodexStoreSnapshot
}

public struct SampleCodexStoreScanner: CodexStoreScanning {
    public init() {}

    public func scan() throws -> CodexStoreSnapshot {
        let now = Date()
        let formatter = ISO8601DateFormatter()

        let projectA = CodexProject(
            id: "project-codex-tools",
            name: "Codex Tools",
            path: URL(fileURLWithPath: "/Users/example/Projects/codex-tools"),
            source: .discovered,
            chats: [
                CodexThread(
                    id: "thread-001",
                    title: "Fix project scanner edge case",
                    currentPath: URL(fileURLWithPath: "/Users/example/Projects/codex-tools"),
                    sessionFile: nil,
                    createdAt: now.addingTimeInterval(-86_400 * 4),
                    updatedAt: now.addingTimeInterval(-3_600),
                    preview: "Investigated project discovery and path normalization.",
                    assignment: .project("project-codex-tools")
                )
            ]
        )

        let projectB = CodexProject(
            id: "project-llm-wiki",
            name: "LLM Wiki",
            path: URL(fileURLWithPath: "/Users/example/Projects/llm-wiki"),
            source: .userAdded,
            chats: []
        )

        let unassigned = [
            CodexThread(
                id: "thread-101",
                title: "Plan Codex chat moving app",
                currentPath: URL(fileURLWithPath: "\(NSHomeDirectory())/.codex/threads"),
                sessionFile: nil,
                createdAt: formatter.date(from: "2026-06-01T12:00:00Z"),
                updatedAt: now.addingTimeInterval(-600),
                preview: "Discussed lightweight macOS app for moving projectless Codex chats into projects.",
                assignment: .outsideKnownProjects
            ),
            CodexThread(
                id: "thread-102",
                title: "Research Codex app-server",
                currentPath: URL(fileURLWithPath: "\(NSHomeDirectory())/.codex/threads"),
                sessionFile: nil,
                createdAt: now.addingTimeInterval(-86_400 * 2),
                updatedAt: now.addingTimeInterval(-7_200),
                preview: "Looked into thread metadata, app-server APIs, and local session files.",
                assignment: .outsideKnownProjects
            )
        ]

        return CodexStoreSnapshot(projects: [projectA, projectB], unassignedThreads: unassigned)
    }
}

public struct FallbackCodexStoreScanner: CodexStoreScanning {
    public let primary: CodexStoreScanning
    public let fallback: CodexStoreScanning

    public init(primary: CodexStoreScanning, fallback: CodexStoreScanning) {
        self.primary = primary
        self.fallback = fallback
    }

    public func scan() throws -> CodexStoreSnapshot {
        let snapshot = try primary.scan()
        if snapshot.projects.isEmpty && snapshot.unassignedThreads.isEmpty {
            return try fallback.scan()
        }
        return snapshot
    }
}

@MainActor
public final class ProjectRegistry {
    public init() {}

    public func addExistingProject() -> CodexProject? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to add as a Codex project."

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return CodexProject(
            id: "user-\(UUID().uuidString)",
            name: url.lastPathComponent,
            path: url,
            source: .userAdded,
            chats: []
        )
    }

    public func createNewProject() -> CodexProject? {
        let baseDirectory = defaultCodexProjectsDirectory()
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = baseDirectory
        panel.nameFieldStringValue = "New Project"
        panel.message = "Create a new project folder inside your Codex projects directory."
        panel.prompt = "Create Project"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        return CodexProject(
            id: "created-\(UUID().uuidString)",
            name: url.lastPathComponent,
            path: url,
            source: .userCreated,
            chats: []
        )
    }

    private func defaultCodexProjectsDirectory(date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents")
            .appendingPathComponent("Codex")
            .appendingPathComponent(formatter.string(from: date))
            .appendingPathComponent("projects")
    }
}

@MainActor
public protocol ThreadMoving {
    func move(thread: CodexThread, to project: CodexProject) async throws -> MoveRecord
    func moveToChats(thread: CodexThread) async throws -> MoveRecord
}

@MainActor
public protocol MoveRestoring {
    func restore(moveRecord: MoveRecord) throws
}

@MainActor
public struct PreviewThreadMover: ThreadMoving {
    public init() {}

    public func move(thread: CodexThread, to project: CodexProject) async throws -> MoveRecord {
        try await Task.sleep(for: .milliseconds(700))
        return MoveRecord(
            id: UUID().uuidString,
            threadId: thread.id,
            fromPath: thread.currentPath,
            toProjectPath: project.path,
            movedAt: Date(),
            backupPath: nil,
            markdownCopyPath: nil,
            jsonCopyPath: nil
        )
    }

    public func moveToChats(thread: CodexThread) async throws -> MoveRecord {
        try await Task.sleep(for: .milliseconds(700))
        return MoveRecord(
            id: UUID().uuidString,
            threadId: thread.id,
            fromPath: thread.currentPath,
            toProjectPath: URL(fileURLWithPath: "\(NSHomeDirectory())/.codex/threads"),
            movedAt: Date(),
            backupPath: nil,
            markdownCopyPath: nil,
            jsonCopyPath: nil
        )
    }
}

public struct CodexLauncher {
    public init() {}

    public func openCodex() {
        if let url = URL(string: "codex://threads/") {
            NSWorkspace.shared.open(url)
        }
    }
}

public struct CodexDesktopController {
    public init() {}

    @discardableResult
    public func quitCodexDesktop() -> Bool {
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier == "com.openai.codex" || app.localizedName == "Codex"
        }

        guard !apps.isEmpty else {
            return true
        }

        return apps.reduce(true) { success, app in
            app.terminate() && success
        }
    }
}
