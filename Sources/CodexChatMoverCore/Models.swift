import Foundation

public struct CodexProject: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var path: URL
    public var source: ProjectSource
    public var chats: [CodexThread]

    public init(id: String, name: String, path: URL, source: ProjectSource, chats: [CodexThread]) {
        self.id = id
        self.name = name
        self.path = path
        self.source = source
        self.chats = chats
    }
}

public enum ProjectSource: String, Codable, Hashable, Sendable {
    case discovered
    case userAdded
    case userCreated
}

public struct CodexThread: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var currentPath: URL?
    public var sessionFile: URL?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var preview: String?
    public var assignment: ThreadAssignment

    public init(
        id: String,
        title: String,
        currentPath: URL?,
        sessionFile: URL?,
        createdAt: Date?,
        updatedAt: Date?,
        preview: String?,
        assignment: ThreadAssignment
    ) {
        self.id = id
        self.title = title
        self.currentPath = currentPath
        self.sessionFile = sessionFile
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.preview = preview
        self.assignment = assignment
    }
}

public enum ThreadAssignment: Hashable, Sendable {
    case project(String)
    case outsideKnownProjects
}

public struct MoveRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let threadId: String
    public let fromPath: URL?
    public let toProjectPath: URL
    public let movedAt: Date
    public let backupPath: URL?
    public let markdownCopyPath: URL?
    public let jsonCopyPath: URL?

    public init(
        id: String,
        threadId: String,
        fromPath: URL?,
        toProjectPath: URL,
        movedAt: Date,
        backupPath: URL?,
        markdownCopyPath: URL?,
        jsonCopyPath: URL?
    ) {
        self.id = id
        self.threadId = threadId
        self.fromPath = fromPath
        self.toProjectPath = toProjectPath
        self.movedAt = movedAt
        self.backupPath = backupPath
        self.markdownCopyPath = markdownCopyPath
        self.jsonCopyPath = jsonCopyPath
    }
}

public struct CodexStoreSnapshot: Sendable {
    public var projects: [CodexProject]
    public var unassignedThreads: [CodexThread]

    public init(projects: [CodexProject], unassignedThreads: [CodexThread]) {
        self.projects = projects
        self.unassignedThreads = unassignedThreads
    }
}

public enum MoveProgressStep: String, CaseIterable, Identifiable, Sendable {
    case checkingCodex = "Checking Codex Desktop"
    case creatingBackup = "Creating backup"
    case updatingMetadata = "Updating thread metadata"
    case writingCopies = "Writing Markdown and JSON copies"
    case verifying = "Verifying result"

    public var id: String { rawValue }
}
