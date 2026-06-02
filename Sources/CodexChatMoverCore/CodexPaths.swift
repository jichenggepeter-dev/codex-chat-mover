import Foundation

public struct CodexPaths: Hashable, Sendable {
    public let codexHome: URL

    public init(codexHome: URL) {
        self.codexHome = codexHome
    }

    public var stateDatabase: URL {
        codexHome.appendingPathComponent("state_5.sqlite")
    }

    public var sessionIndex: URL {
        codexHome.appendingPathComponent("session_index.jsonl")
    }

    public var sessionsDirectory: URL {
        codexHome.appendingPathComponent("sessions")
    }

    public var projectlessThreadsDirectory: URL {
        codexHome.appendingPathComponent("threads")
    }

    public static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> CodexPaths {
        if let override = environment["CODEX_HOME"], !override.isEmpty {
            return CodexPaths(codexHome: URL(fileURLWithPath: override).standardizedFileURL)
        }

        return CodexPaths(
            codexHome: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".codex")
                .standardizedFileURL
        )
    }
}
