import AppKit
import Foundation

public struct SafeThreadMover: ThreadMoving, MoveRestoring {
    private let paths: CodexPaths
    private let scanner: CodexStoreScanning
    private let backupManager: BackupManaging
    private let processMonitor: CodexProcessMonitoring
    private let sqliteUpdater: SQLiteThreadUpdating
    private let jsonlPatcher: SessionJSONLPatching
    private let projectRegistrar: CodexProjectRegistering
    private let projectCopyWriter: ProjectCopyWriting

    public init(
        paths: CodexPaths = .live(),
        scanner: CodexStoreScanning? = nil,
        backupManager: BackupManaging? = nil,
        processMonitor: CodexProcessMonitoring = MacCodexProcessMonitor(),
        sqliteUpdater: SQLiteThreadUpdating = SQLiteThreadUpdater(),
        jsonlPatcher: SessionJSONLPatching = SessionJSONLPatcher(),
        projectRegistrar: CodexProjectRegistering = GlobalStateProjectRegistrar(),
        projectCopyWriter: ProjectCopyWriting = ProjectCopyWriter()
    ) {
        self.paths = paths
        self.scanner = scanner ?? LiveCodexStoreScanner(paths: paths)
        self.backupManager = backupManager ?? BackupManager()
        self.processMonitor = processMonitor
        self.sqliteUpdater = sqliteUpdater
        self.jsonlPatcher = jsonlPatcher
        self.projectRegistrar = projectRegistrar
        self.projectCopyWriter = projectCopyWriter
    }

    public func move(thread: CodexThread, to project: CodexProject) async throws -> MoveRecord {
        guard !processMonitor.isCodexDesktopRunning() else {
            throw MoveError.codexDesktopIsRunning
        }

        guard let sessionFile = thread.sessionFile else {
            throw MoveError.missingSessionFile(thread.id)
        }

        let backup = try backupManager.createBackup(
            paths: paths,
            threadID: thread.id,
            sessionFile: sessionFile
        )

        do {
            let targetPath = project.path.standardizedFileURL
            try sqliteUpdater.updateThread(threadID: thread.id, cwd: targetPath.path, database: paths.stateDatabase)
            try jsonlPatcher.patchSessionFile(sessionFile, cwd: targetPath.path)
            try projectRegistrar.registerProjectAndThread(
                projectPath: targetPath,
                threadID: thread.id,
                paths: paths
            )
            let copies = try projectCopyWriter.writeCopies(thread: thread, project: project, movedAt: backup.createdAt)

            guard try verify(threadID: thread.id, targetProjectPath: targetPath) else {
                throw MoveError.verificationFailed
            }

            return MoveRecord(
                id: backup.id,
                threadId: thread.id,
                fromPath: thread.currentPath,
                toProjectPath: targetPath,
                movedAt: backup.createdAt,
                backupPath: backup.directory,
                markdownCopyPath: copies.markdown,
                jsonCopyPath: copies.json
            )
        } catch {
            try? backupManager.restore(backup)
            throw error
        }
    }

    public func restore(moveRecord: MoveRecord) throws {
        guard let backupPath = moveRecord.backupPath else {
            throw MoveError.missingBackup
        }
        try backupManager.restoreBackup(at: backupPath)
    }

    private func verify(threadID: String, targetProjectPath: URL) throws -> Bool {
        try scanner.scan().projects
            .first { $0.path.standardizedFileURL.path == targetProjectPath.path }?
            .chats
            .contains { $0.id == threadID } == true
    }
}

public enum MoveError: LocalizedError {
    case codexDesktopIsRunning
    case missingSessionFile(String)
    case missingBackup
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .codexDesktopIsRunning:
            return "Close Codex Desktop before moving chats."
        case let .missingSessionFile(threadID):
            return "Could not find the session file for thread \(threadID)."
        case .missingBackup:
            return "Could not find the backup for this move."
        case .verificationFailed:
            return "The move could not be verified after updating Codex metadata."
        }
    }
}

public protocol CodexProcessMonitoring {
    func isCodexDesktopRunning() -> Bool
}

public struct MacCodexProcessMonitor: CodexProcessMonitoring {
    public init() {}

    public func isCodexDesktopRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.openai.codex" || app.localizedName == "Codex"
        }
    }
}

public struct BackupRecord: Hashable {
    public let id: String
    public let createdAt: Date
    public let directory: URL
    public let originalFiles: [URL: URL]

    public init(id: String, createdAt: Date, directory: URL, originalFiles: [URL: URL]) {
        self.id = id
        self.createdAt = createdAt
        self.directory = directory
        self.originalFiles = originalFiles
    }
}

public protocol BackupManaging {
    func createBackup(paths: CodexPaths, threadID: String, sessionFile: URL) throws -> BackupRecord
    func restore(_ backup: BackupRecord) throws
    func restoreBackup(at directory: URL) throws
}

public struct BackupManager: BackupManaging {
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let maxBackups: Int

    public init(
        rootDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codex Chat Mover")
            .appendingPathComponent("Backups"),
        fileManager: FileManager = .default,
        maxBackups: Int = 10
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.maxBackups = maxBackups
    }

    public func createBackup(paths: CodexPaths, threadID: String, sessionFile: URL) throws -> BackupRecord {
        let id = "\(Int(Date().timeIntervalSince1970))-\(threadID)"
        let directory = rootDirectory.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let candidates = [
            paths.stateDatabase,
            URL(fileURLWithPath: paths.stateDatabase.path + "-wal"),
            URL(fileURLWithPath: paths.stateDatabase.path + "-shm"),
            paths.globalState,
            URL(fileURLWithPath: paths.globalState.path + ".bak"),
            paths.sessionIndex,
            sessionFile.standardizedFileURL
        ]

        var originalFiles: [URL: URL] = [:]
        for source in candidates where fileManager.fileExists(atPath: source.path) {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            originalFiles[source.standardizedFileURL] = destination.standardizedFileURL
        }

        let record = BackupRecord(
            id: id,
            createdAt: Date(),
            directory: directory.standardizedFileURL,
            originalFiles: originalFiles
        )
        try writeManifest(for: record)
        try pruneOldBackups()
        return record
    }

    public func restore(_ backup: BackupRecord) throws {
        for (original, copy) in backup.originalFiles {
            if fileManager.fileExists(atPath: original.path) {
                try fileManager.removeItem(at: original)
            }
            try fileManager.copyItem(at: copy, to: original)
        }
    }

    public func restoreBackup(at directory: URL) throws {
        let manifest = directory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifest)
        let backup = try JSONDecoder().decode(BackupManifest.self, from: data).toRecord(directory: directory)
        try restore(backup)
    }

    private func writeManifest(for record: BackupRecord) throws {
        let manifest = BackupManifest(record: record)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: record.directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func pruneOldBackups() throws {
        guard maxBackups > 0,
              let entries = try? fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        let sorted = entries.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return leftDate > rightDate
        }

        for extra in sorted.dropFirst(maxBackups) {
            try? fileManager.removeItem(at: extra)
        }
    }
}

private struct BackupManifest: Codable {
    let id: String
    let createdAt: Date
    let files: [BackupManifestFile]

    init(record: BackupRecord) {
        id = record.id
        createdAt = record.createdAt
        files = record.originalFiles.map { original, copy in
            BackupManifestFile(original: original.path, copy: copy.path)
        }
    }

    func toRecord(directory: URL) -> BackupRecord {
        BackupRecord(
            id: id,
            createdAt: createdAt,
            directory: directory,
            originalFiles: Dictionary(uniqueKeysWithValues: files.map { file in
                (
                    URL(fileURLWithPath: file.original).standardizedFileURL,
                    URL(fileURLWithPath: file.copy).standardizedFileURL
                )
            })
        )
    }
}

private struct BackupManifestFile: Codable {
    let original: String
    let copy: String
}

public protocol SQLiteThreadUpdating {
    func updateThread(threadID: String, cwd: String, database: URL) throws
}

public struct SQLiteThreadUpdater: SQLiteThreadUpdating {
    public init() {}

    public func updateThread(threadID: String, cwd: String, database: URL) throws {
        let nowSeconds = Int(Date().timeIntervalSince1970)
        let nowMilliseconds = nowSeconds * 1000
        let sql = """
        update threads
        set cwd = \(sqlQuote(cwd)),
            updated_at = \(nowSeconds),
            updated_at_ms = \(nowMilliseconds)
        where id = \(sqlQuote(threadID));
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, sql]

        let errorOutput = Pipe()
        process.standardError = errorOutput

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorOutput.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "sqlite3 update failed"
            throw CodexScannerError.sqliteReadFailed(message)
        }
    }

    private func sqlQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

public protocol SessionJSONLPatching {
    func patchSessionFile(_ file: URL, cwd: String) throws
}

public struct SessionJSONLPatcher: SessionJSONLPatching {
    public init() {}

    public func patchSessionFile(_ file: URL, cwd: String) throws {
        let contents = try String(contentsOf: file, encoding: .utf8)
        var patchedLines: [String] = []

        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            guard !line.isEmpty, let data = String(line).data(using: .utf8) else {
                patchedLines.append(String(line))
                continue
            }

            let json = try JSONSerialization.jsonObject(with: data)
            let patched = patchCWD(in: json, cwd: cwd)
            let patchedData = try JSONSerialization.data(withJSONObject: patched, options: [.sortedKeys])
            patchedLines.append(String(data: patchedData, encoding: .utf8) ?? String(line))
        }

        try patchedLines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private func patchCWD(in value: Any, cwd: String) -> Any {
        if var dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if key == "cwd", child is String {
                    dictionary[key] = cwd
                } else {
                    dictionary[key] = patchCWD(in: child, cwd: cwd)
                }
            }
            return dictionary
        }

        if let array = value as? [Any] {
            return array.map { patchCWD(in: $0, cwd: cwd) }
        }

        return value
    }
}

public protocol CodexProjectRegistering {
    func registerProjectAndThread(projectPath: URL, threadID: String, paths: CodexPaths) throws
}

public struct GlobalStateProjectRegistrar: CodexProjectRegistering {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func registerProjectAndThread(projectPath: URL, threadID: String, paths: CodexPaths) throws {
        let file = paths.globalState
        guard fileManager.fileExists(atPath: file.path) else {
            return
        }

        let data = try Data(contentsOf: file)
        var state = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let path = projectPath.standardizedFileURL.path

        appendUnique(path, toArrayAt: "electron-saved-workspace-roots", in: &state)
        appendUnique(path, toArrayAt: "project-order", in: &state)
        remove(threadID, fromArrayAt: "projectless-thread-ids", in: &state)
        upsertStringMapValue(path, for: threadID, at: "thread-workspace-root-hints", in: &state)
        removeMapValue(for: threadID, at: "thread-projectless-output-directories", in: &state)

        let output = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        try output.write(to: file, options: .atomic)
    }

    private func appendUnique(_ value: String, toArrayAt key: String, in state: inout [String: Any]) {
        var array = state[key] as? [String] ?? []
        if !array.contains(value) {
            array.append(value)
        }
        state[key] = array
    }

    private func remove(_ value: String, fromArrayAt key: String, in state: inout [String: Any]) {
        guard var array = state[key] as? [String] else {
            return
        }
        array.removeAll { $0 == value }
        state[key] = array
    }

    private func upsertStringMapValue(_ value: String, for mapKey: String, at key: String, in state: inout [String: Any]) {
        var map = state[key] as? [String: String] ?? [:]
        map[mapKey] = value
        state[key] = map
    }

    private func removeMapValue(for mapKey: String, at key: String, in state: inout [String: Any]) {
        guard var map = state[key] as? [String: Any] else {
            return
        }
        map.removeValue(forKey: mapKey)
        state[key] = map
    }
}

public struct ProjectCopies: Hashable {
    public let markdown: URL
    public let json: URL
}

public protocol ProjectCopyWriting {
    func writeCopies(thread: CodexThread, project: CodexProject, movedAt: Date) throws -> ProjectCopies
}

public struct ProjectCopyWriter: ProjectCopyWriting {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func writeCopies(thread: CodexThread, project: CodexProject, movedAt: Date) throws -> ProjectCopies {
        let directory = project.path
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("imported-chats", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let markdown = directory.appendingPathComponent("\(thread.id).md")
        let json = directory.appendingPathComponent("\(thread.id).json")
        let iso = ISO8601DateFormatter().string(from: movedAt)

        let markdownBody = """
        # \(thread.title)

        ## Migration

        - Thread ID: \(thread.id)
        - Moved At: \(iso)
        - Previous Path: \(thread.currentPath?.path ?? "Unknown")
        - New Project: \(project.path.path)

        ## Preview

        \(thread.preview ?? "No preview available.")
        """

        let jsonObject: [String: Any] = [
            "thread_id": thread.id,
            "title": thread.title,
            "moved_at": iso,
            "previous_path": thread.currentPath?.path ?? NSNull(),
            "new_project_path": project.path.path,
            "preview": thread.preview ?? NSNull()
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        try markdownBody.write(to: markdown, atomically: true, encoding: .utf8)
        try jsonData.write(to: json, options: .atomic)

        return ProjectCopies(markdown: markdown.standardizedFileURL, json: json.standardizedFileURL)
    }
}
