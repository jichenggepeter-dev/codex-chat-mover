import Foundation

public struct LiveCodexStoreScanner: CodexStoreScanning {
    private let paths: CodexPaths
    private let threadRecordReader: ThreadRecordReading

    public init(
        paths: CodexPaths = .live(),
        threadRecordReader: ThreadRecordReading = SQLiteThreadRecordReader()
    ) {
        self.paths = paths
        self.threadRecordReader = threadRecordReader
    }

    public func scan() throws -> CodexStoreSnapshot {
        let index = try SessionIndexReader(fileURL: paths.sessionIndex).readEntriesByID()
        let records = try threadRecordReader.readThreadRecords(from: paths)
            .filter { !$0.archived }
            .filter(\.isUserVisible)

        let threads = records.map { record in
            let indexEntry = index[record.id]
            return CodexThread(
                id: record.id,
                title: bestTitle(record: record, indexEntry: indexEntry),
                currentPath: URL(fileURLWithPath: record.cwd).standardizedFileURL,
                sessionFile: record.rolloutPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                createdAt: record.createdAt,
                updatedAt: record.updatedAt ?? indexEntry?.updatedAt,
                preview: bestPreview(record: record),
                assignment: .outsideKnownProjects
            )
        }

        let projectPaths = discoverProjectPaths(from: threads)
        let projectIDsByPath = Dictionary(uniqueKeysWithValues: projectPaths.map { path in
            (path.path, projectID(for: path))
        })

        var projectsByPath = Dictionary(uniqueKeysWithValues: projectPaths.map { path in
            (
                path.path,
                CodexProject(
                    id: projectID(for: path),
                    name: projectName(for: path),
                    path: path,
                    source: .discovered,
                    chats: []
                )
            )
        })
        var unassigned: [CodexThread] = []

        for var thread in threads.sorted(by: sortThreadsByUpdatedAtDescending) {
            guard let path = thread.currentPath?.standardizedFileURL,
                  let projectID = projectIDsByPath[path.path],
                  projectsByPath[path.path] != nil else {
                thread.assignment = .outsideKnownProjects
                unassigned.append(thread)
                continue
            }

            thread.assignment = .project(projectID)
            projectsByPath[path.path]?.chats.append(thread)
        }

        let projects = projectsByPath.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return CodexStoreSnapshot(projects: projects, unassignedThreads: unassigned)
    }

    private func discoverProjectPaths(from threads: [CodexThread]) -> [URL] {
        let codexHomePath = paths.codexHome.standardizedFileURL.path
        let projectlessPath = paths.projectlessThreadsDirectory.standardizedFileURL.path
        let paths = threads.compactMap { thread -> URL? in
            guard let path = thread.currentPath?.standardizedFileURL else {
                return nil
            }
            if path.path == projectlessPath || path.path.hasPrefix(codexHomePath + "/") {
                return nil
            }
            if isGeneratedCodexWorkspace(path) {
                return nil
            }
            return path
        }

        return Array(Set(paths)).sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private func bestTitle(record: ThreadRecord, indexEntry: SessionIndexEntry?) -> String {
        let candidates = [record.title, indexEntry?.threadName, record.firstUserMessage]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return String(trimmed.prefix(120))
            }
        }
        return "Untitled Chat"
    }

    private func bestPreview(record: ThreadRecord) -> String? {
        let candidates = [record.preview, record.firstUserMessage]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return String(trimmed.prefix(220))
            }
        }
        return nil
    }

    private func projectID(for path: URL) -> String {
        let stablePath = path.standardizedFileURL.path
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path.lastPathComponent
        return "project-\(stablePath)"
    }

    private func projectName(for path: URL) -> String {
        let last = path.lastPathComponent
        return last.isEmpty ? path.path : last
    }

    private func isGeneratedCodexWorkspace(_ path: URL) -> Bool {
        let components = path.standardizedFileURL.pathComponents
        guard let codexIndex = components.lastIndex(of: "Codex"),
              components.indices.contains(codexIndex + 1) else {
            return false
        }

        let dateComponent = components[codexIndex + 1]
        guard dateComponent.range(
            of: #"^\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }

        if components.indices.contains(codexIndex + 2),
           components[codexIndex + 2] == "projects" {
            if components.count == codexIndex + 3 {
                return true
            }
            return false
        }

        return true
    }

    private func sortThreadsByUpdatedAtDescending(_ lhs: CodexThread, _ rhs: CodexThread) -> Bool {
        (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
    }
}

public struct ThreadRecord: Decodable, Hashable, Sendable {
    public let id: String
    public let cwd: String
    public let title: String?
    public let firstUserMessage: String?
    public let preview: String?
    public let rolloutPath: String?
    public let source: String?
    public let threadSource: String?
    public let agentPath: String?
    public let archived: Bool
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case cwd
        case title
        case firstUserMessage = "first_user_message"
        case preview
        case rolloutPath = "rollout_path"
        case source
        case threadSource = "thread_source"
        case agentPath = "agent_path"
        case archived
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    public init(
        id: String,
        cwd: String,
        title: String? = nil,
        firstUserMessage: String? = nil,
        preview: String? = nil,
        rolloutPath: String? = nil,
        source: String? = nil,
        threadSource: String? = nil,
        agentPath: String? = nil,
        archived: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.cwd = cwd
        self.title = title
        self.firstUserMessage = firstUserMessage
        self.preview = preview
        self.rolloutPath = rolloutPath
        self.source = source
        self.threadSource = threadSource
        self.agentPath = agentPath
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        cwd = try container.decode(String.self, forKey: .cwd)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        firstUserMessage = try container.decodeIfPresent(String.self, forKey: .firstUserMessage)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        rolloutPath = try container.decodeIfPresent(String.self, forKey: .rolloutPath)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        threadSource = try container.decodeIfPresent(String.self, forKey: .threadSource)
        agentPath = try container.decodeIfPresent(String.self, forKey: .agentPath)

        if let bool = try? container.decode(Bool.self, forKey: .archived) {
            archived = bool
        } else {
            let integer = try container.decodeIfPresent(Int.self, forKey: .archived) ?? 0
            archived = integer != 0
        }

        createdAt = Self.dateFromMilliseconds(try container.decodeIfPresent(Int64.self, forKey: .createdAtMs))
        updatedAt = Self.dateFromMilliseconds(try container.decodeIfPresent(Int64.self, forKey: .updatedAtMs))
    }

    private static func dateFromMilliseconds(_ value: Int64?) -> Date? {
        guard let value else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(value) / 1000)
    }

    var isUserVisible: Bool {
        if threadSource?.localizedCaseInsensitiveContains("subagent") == true {
            return false
        }
        if source?.localizedCaseInsensitiveContains("subagent") == true {
            return false
        }
        if agentPath?.isEmpty == false {
            return false
        }
        if title?.localizedCaseInsensitiveContains("<codex_delegation>") == true {
            return false
        }
        if firstUserMessage?.localizedCaseInsensitiveContains("<codex_delegation>") == true {
            return false
        }
        return true
    }
}

public protocol ThreadRecordReading: Sendable {
    func readThreadRecords(from paths: CodexPaths) throws -> [ThreadRecord]
}

public struct SQLiteThreadRecordReader: ThreadRecordReading {
    public init() {}

    public func readThreadRecords(from paths: CodexPaths) throws -> [ThreadRecord] {
        guard FileManager.default.fileExists(atPath: paths.stateDatabase.path) else {
            return []
        }

        let query = """
        select
            id,
            cwd,
            substr(title, 1, 200) as title,
            substr(first_user_message, 1, 500) as first_user_message,
            substr(preview, 1, 500) as preview,
            rollout_path,
            source,
            thread_source,
            agent_path,
            archived,
            created_at_ms,
            updated_at_ms
        from threads
        order by updated_at_ms desc
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-cmd", ".timeout 5000", "-json", paths.stateDatabase.path, query]

        let errorOutput = Pipe()
        process.standardError = errorOutput

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-chat-mover-sqlite-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        process.standardOutput = outputHandle

        try process.run()
        process.waitUntilExit()
        try outputHandle.close()

        let data = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)
        if process.terminationStatus != 0 {
            let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "sqlite3 failed"
            throw CodexScannerError.sqliteReadFailed(message)
        }

        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder().decode([ThreadRecord].self, from: data)
    }
}

public struct SessionIndexEntry: Decodable, Hashable, Sendable {
    public let id: String
    public let threadName: String?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }

    public init(id: String, threadName: String?, updatedAt: Date?) {
        self.id = id
        self.threadName = threadName
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        threadName = try container.decodeIfPresent(String.self, forKey: .threadName)

        if let rawDate = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = DateParsers.parseCodexDate(rawDate)
        } else {
            updatedAt = nil
        }
    }
}

public struct SessionIndexReader: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func readEntriesByID() throws -> [String: SessionIndexEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        var entries: [String: SessionIndexEntry] = [:]
        let decoder = JSONDecoder()

        for line in contents.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8) else {
                continue
            }
            let entry = try decoder.decode(SessionIndexEntry.self, from: data)
            entries[entry.id] = entry
        }

        return entries
    }
}

public struct SessionFileLocator: Sendable {
    public let sessionsDirectory: URL

    public init(sessionsDirectory: URL) {
        self.sessionsDirectory = sessionsDirectory
    }

    public func locateByThreadID() -> [String: URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [String: URL] = [:]

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let id = extractThreadID(from: fileURL.lastPathComponent) else {
                continue
            }
            result[id] = fileURL.standardizedFileURL
        }

        return result
    }

    private func extractThreadID(from filename: String) -> String? {
        guard filename.hasPrefix("rollout-"), filename.hasSuffix(".jsonl") else {
            return nil
        }

        let basename = String(filename.dropLast(".jsonl".count))
        let parts = basename.split(separator: "-")
        guard parts.count >= 8 else {
            return nil
        }

        return parts.suffix(5).joined(separator: "-")
    }
}

public enum DateParsers {
    public static func parseCodexDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }

        return ISO8601DateFormatter().date(from: raw)
    }
}

public enum CodexScannerError: LocalizedError {
    case sqliteReadFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .sqliteReadFailed(message):
            return "Could not read Codex sqlite state: \(message)"
        }
    }
}
