import CodexChatMoverCore
import Foundation

try testSessionIndexReaderParsesJSONLines()
try testSessionFileLocatorExtractsThreadIDFromRolloutFilename()
try testScannerClassifiesCodexThreadsOutsideKnownProjects()
try testScannerKeepsPinnedDelegationThreadsVisible()
try testSessionJSONLPatcherUpdatesNestedCWD()
try testGlobalStateProjectRegistrarRegistersProjectThread()
try testGlobalStateProjectRegistrarRegistersProjectlessThread()
try testProjectCopyWriterCreatesMarkdownAndJSON()
try testBackupManagerCanRestoreManifestBackup()
try await testSafeThreadMoverStopsWhenCodexIsRunning()
print("ScannerSmokeTests passed")

func testSessionIndexReaderParsesJSONLines() throws {
    let fixture = try fixtureURL("session_index", extension: "jsonl")
    let entries = try SessionIndexReader(fileURL: fixture).readEntriesByID()

    expect(entries["thread-project"]?.threadName == "Project thread from index", "session index title did not parse")
    expect(entries["thread-projectless"]?.updatedAt != nil, "session index date did not parse")
}

func testSessionFileLocatorExtractsThreadIDFromRolloutFilename() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-chat-mover-tests-\(UUID().uuidString)")
    let nested = root.appendingPathComponent("2026/06/01", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let file = nested.appendingPathComponent("rollout-2026-06-01T11-22-33-019e8545-5680-7f73-abd2-8b84044b353f.jsonl")
    try "{}\n".write(to: file, atomically: true, encoding: .utf8)

    let located = SessionFileLocator(sessionsDirectory: root).locateByThreadID()

    expect(
        located["019e8545-5680-7f73-abd2-8b84044b353f"] == file.standardizedFileURL,
        "session file locator did not extract thread id"
    )
}

func testScannerClassifiesCodexThreadsOutsideKnownProjects() throws {
    let codexHome = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-chat-mover-scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    try """
    {"id":"thread-project","thread_name":"Project thread from index","updated_at":"2026-06-01T12:00:00.000000Z"}
    {"id":"thread-projectless","thread_name":"Projectless planning chat","updated_at":"2026-06-01T13:00:00Z"}
    """.write(to: codexHome.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)

    let paths = CodexPaths(codexHome: codexHome)
    let reader = FixtureThreadRecordReader(records: [
        ThreadRecord(
            id: "thread-project",
            cwd: "/Users/example/Code/app",
            title: "Project title",
            firstUserMessage: nil,
            preview: "A project thread",
            archived: false,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
            ),
            ThreadRecord(
                id: "thread-projectless",
                cwd: paths.projectlessThreadsDirectory.path,
                title: "",
            firstUserMessage: "Plan a tool",
            preview: nil,
            archived: false,
                createdAt: Date(timeIntervalSince1970: 30),
                updatedAt: Date(timeIntervalSince1970: 40)
            ),
            ThreadRecord(
                id: "thread-generated-workspace",
                cwd: "/Users/example/Documents/Codex/2026-06-01/generated-skill",
                title: "Generated workspace",
                firstUserMessage: nil,
                preview: nil,
                archived: false,
                createdAt: Date(timeIntervalSince1970: 40),
                updatedAt: Date(timeIntervalSince1970: 50)
            ),
            ThreadRecord(
                id: "thread-subagent",
                cwd: "/Users/example/Code/app",
                title: "Internal worker",
                firstUserMessage: nil,
                preview: nil,
                source: #"{"subagent":{"other":"guardian"}}"#,
                threadSource: "subagent",
                archived: false,
                createdAt: Date(timeIntervalSince1970: 50),
                updatedAt: Date(timeIntervalSince1970: 60)
            )
        ])

    let scanner = LiveCodexStoreScanner(paths: paths, threadRecordReader: reader)
    let snapshot = try scanner.scan()

        expect(snapshot.projects.count == 1, "scanner should discover one project")
        expect(snapshot.projects.first?.path.path == "/Users/example/Code/app", "scanner discovered wrong project path")
        expect(snapshot.projects.first?.chats.first?.id == "thread-project", "scanner did not assign project thread")
        expect(snapshot.projects.first?.chats.first?.title == "Project thread from index", "scanner should prefer session index title")
        expect(snapshot.unassignedThreads.map(\.id) == ["thread-generated-workspace", "thread-projectless"], "scanner did not keep non-project threads unassigned")
        expect(snapshot.unassignedThreads.last?.title == "Projectless planning chat", "scanner did not use session index title for projectless chat")
        expect(!snapshot.projects.flatMap(\.chats).contains { $0.id == "thread-subagent" }, "scanner should hide subagent threads")
    }

func testScannerKeepsPinnedDelegationThreadsVisible() throws {
    let codexHome = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-chat-mover-pinned-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    try """
    {"pinned-thread-ids":["thread-pinned"]}
    """.write(to: codexHome.appendingPathComponent(".codex-global-state.json"), atomically: true, encoding: .utf8)
    try """
    {"id":"thread-pinned","thread_name":"Pinned Delegation Thread","updated_at":"2026-06-01T13:00:00Z"}
    """.write(to: codexHome.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)

    let reader = FixtureThreadRecordReader(records: [
        ThreadRecord(
            id: "thread-pinned",
            cwd: "/Users/example/Code/pinned",
            title: "<codex_delegation> internal title",
            firstUserMessage: "<codex_delegation> internal message",
            preview: "Pinned preview",
            archived: false,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
    ])

    let scanner = LiveCodexStoreScanner(paths: CodexPaths(codexHome: codexHome), threadRecordReader: reader)
    let snapshot = try scanner.scan()

    expect(snapshot.projects.count == 1, "pinned delegation thread should remain visible")
    expect(snapshot.projects.first?.chats.first?.title == "Pinned Delegation Thread", "pinned delegation thread should use session index title")
}

func testSessionJSONLPatcherUpdatesNestedCWD() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-chat-mover-jsonl-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("session.jsonl")
    try """
    {"type":"session_meta","payload":{"cwd":"/old/path","nested":{"cwd":"/old/path"}}}
    {"type":"message","payload":{"text":"keep me"}}
    """.write(to: file, atomically: true, encoding: .utf8)

    try SessionJSONLPatcher().patchSessionFile(file, cwd: "/new/path")

    let patched = try String(contentsOf: file, encoding: .utf8)
    let firstLine = try String(patched.split(separator: "\n")[0])
        .data(using: .utf8)
        .map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? nil
    let payload = firstLine?["payload"] as? [String: Any]
    let nested = payload?["nested"] as? [String: Any]
    expect(payload?["cwd"] as? String == "/new/path", "jsonl patcher did not update payload cwd")
    expect(nested?["cwd"] as? String == "/new/path", "jsonl patcher did not update nested cwd")
}

func testGlobalStateProjectRegistrarRegistersProjectThread() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-chat-mover-global-state-\(UUID().uuidString)")
    let codexHome = root.appendingPathComponent("codex")
    let project = root.appendingPathComponent("projects/test")
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

    let globalState = codexHome.appendingPathComponent(".codex-global-state.json")
    try """
    {
      "electron-saved-workspace-roots": ["/existing/project"],
      "project-order": ["/existing/project"],
      "projectless-thread-ids": ["thread-a", "thread-move"],
      "thread-workspace-root-hints": {"thread-move": "/Users/example/Documents/Codex"},
      "thread-projectless-output-directories": {"thread-move": "/tmp/old-output"}
    }
    """.write(to: globalState, atomically: true, encoding: .utf8)

    try GlobalStateProjectRegistrar().registerProjectAndThread(
        projectPath: project,
        threadID: "thread-move",
        paths: CodexPaths(codexHome: codexHome)
    )

    let data = try Data(contentsOf: globalState)
    let state = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let savedRoots = state?["electron-saved-workspace-roots"] as? [String]
    let projectOrder = state?["project-order"] as? [String]
    let projectless = state?["projectless-thread-ids"] as? [String]
    let hints = state?["thread-workspace-root-hints"] as? [String: String]
    let outputs = state?["thread-projectless-output-directories"] as? [String: Any]

    expect(savedRoots?.contains(project.path) == true, "registrar did not add saved workspace root")
    expect(projectOrder?.contains(project.path) == true, "registrar did not add project order")
    expect(projectless == ["thread-a"], "registrar did not remove projectless thread id")
    expect(hints?["thread-move"] == project.path, "registrar did not update workspace root hint")
    expect(outputs?["thread-move"] == nil, "registrar did not remove projectless output directory")
}

func testGlobalStateProjectRegistrarRegistersProjectlessThread() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-chat-mover-projectless-\(UUID().uuidString)")
    let codexHome = root.appendingPathComponent("codex")
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)

    let globalState = codexHome.appendingPathComponent(".codex-global-state.json")
    try """
    {
      "projectless-thread-ids": ["thread-a"],
      "thread-workspace-root-hints": {"thread-move": "/Users/example/Documents/Project"}
    }
    """.write(to: globalState, atomically: true, encoding: .utf8)

    try GlobalStateProjectRegistrar().registerProjectlessThread(
        threadID: "thread-move",
        paths: CodexPaths(codexHome: codexHome)
    )

    let data = try Data(contentsOf: globalState)
    let state = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let projectless = state?["projectless-thread-ids"] as? [String]
    let hints = state?["thread-workspace-root-hints"] as? [String: String]

    expect(projectless?.contains("thread-move") == true, "registrar did not add projectless thread id")
    expect(hints?["thread-move"] == nil, "registrar did not remove workspace root hint")
}

func testProjectCopyWriterCreatesMarkdownAndJSON() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-chat-mover-copy-\(UUID().uuidString)")
    let project = CodexProject(id: "project", name: "Project", path: root, source: .userCreated, chats: [])
    let thread = CodexThread(
        id: "thread-copy",
        title: "Copied Chat",
        currentPath: URL(fileURLWithPath: "/old/path"),
        sessionFile: nil,
        createdAt: nil,
        updatedAt: nil,
        preview: "A useful preview",
        assignment: .outsideKnownProjects
    )

    let copies = try ProjectCopyWriter().writeCopies(thread: thread, project: project, movedAt: Date(timeIntervalSince1970: 0))

    expect(FileManager.default.fileExists(atPath: copies.markdown.path), "markdown copy was not written")
    expect(FileManager.default.fileExists(atPath: copies.json.path), "json copy was not written")
}

func testBackupManagerCanRestoreManifestBackup() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-chat-mover-backup-\(UUID().uuidString)")
    let codexHome = root.appendingPathComponent("codex")
    let backupRoot = root.appendingPathComponent("backups")
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)

    let state = codexHome.appendingPathComponent("state_5.sqlite")
    let index = codexHome.appendingPathComponent("session_index.jsonl")
    let session = codexHome.appendingPathComponent("session.jsonl")
    try "state-old".write(to: state, atomically: true, encoding: .utf8)
    try "index-old".write(to: index, atomically: true, encoding: .utf8)
    try "session-old".write(to: session, atomically: true, encoding: .utf8)

    let manager = BackupManager(rootDirectory: backupRoot, maxBackups: 10)
    let record = try manager.createBackup(
        paths: CodexPaths(codexHome: codexHome),
        threadID: "thread",
        sessionFile: session
    )
    try "state-new".write(to: state, atomically: true, encoding: .utf8)
    try "session-new".write(to: session, atomically: true, encoding: .utf8)

    try manager.restoreBackup(at: record.directory)

    let restoredState = try String(contentsOf: state, encoding: .utf8)
    let restoredSession = try String(contentsOf: session, encoding: .utf8)
    expect(restoredState == "state-old", "backup restore did not restore state")
    expect(restoredSession == "session-old", "backup restore did not restore session")
}

@MainActor
func testSafeThreadMoverStopsWhenCodexIsRunning() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-chat-mover-guard-\(UUID().uuidString)")
    let paths = CodexPaths(codexHome: root)
    let sessionFile = root.appendingPathComponent("session.jsonl")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "{}\n".write(to: sessionFile, atomically: true, encoding: .utf8)

    let mover = SafeThreadMover(
        paths: paths,
        scanner: StaticScanner(snapshot: CodexStoreSnapshot(projects: [], unassignedThreads: [])),
        backupManager: InMemoryBackupManager(),
        processMonitor: StaticProcessMonitor(isRunning: true),
        sqliteUpdater: NoopSQLiteUpdater(),
        jsonlPatcher: SessionJSONLPatcher(),
        projectCopyWriter: ProjectCopyWriter()
    )

    let thread = CodexThread(
        id: "thread",
        title: "Thread",
        currentPath: URL(fileURLWithPath: "/old"),
        sessionFile: sessionFile,
        createdAt: nil,
        updatedAt: nil,
        preview: nil,
        assignment: .outsideKnownProjects
    )
    let project = CodexProject(id: "project", name: "Project", path: root, source: .userCreated, chats: [])

    do {
        _ = try await mover.move(thread: thread, to: project)
        fatalError("move should fail while Codex is running")
    } catch MoveError.codexDesktopIsRunning {
        return
    }
}

func fixtureURL(_ name: String, extension ext: String) throws -> URL {
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
        throw SmokeTestError.missingFixture(name)
    }
    return url
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Expectation failed") {
    guard condition() else {
        fatalError(message)
    }
}

private struct FixtureThreadRecordReader: ThreadRecordReading {
    let records: [ThreadRecord]

    func readThreadRecords(from paths: CodexPaths) throws -> [ThreadRecord] {
        records
    }
}

private struct StaticScanner: CodexStoreScanning {
    let snapshot: CodexStoreSnapshot

    func scan() throws -> CodexStoreSnapshot {
        snapshot
    }
}

private struct StaticProcessMonitor: CodexProcessMonitoring {
    let isRunning: Bool

    func isCodexDesktopRunning() -> Bool {
        isRunning
    }
}

private struct NoopSQLiteUpdater: SQLiteThreadUpdating {
    func updateThread(threadID: String, cwd: String, database: URL) throws {}
}

private struct InMemoryBackupManager: BackupManaging {
    func createBackup(paths: CodexPaths, threadID: String, sessionFile: URL) throws -> BackupRecord {
        BackupRecord(
            id: "backup",
            createdAt: Date(timeIntervalSince1970: 0),
            directory: paths.codexHome,
            originalFiles: [:]
        )
    }

    func restore(_ backup: BackupRecord) throws {}

    func restoreBackup(at directory: URL) throws {}
}

private enum SmokeTestError: Error {
    case missingFixture(String)
}
