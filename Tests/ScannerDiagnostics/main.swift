import CodexChatMoverCore
import Foundation

let paths = CodexPaths.live()
print("Codex home: \(paths.codexHome.path)")
print("State database exists: \(FileManager.default.fileExists(atPath: paths.stateDatabase.path))")
print("Session index exists: \(FileManager.default.fileExists(atPath: paths.sessionIndex.path))")
print("Sessions directory exists: \(FileManager.default.fileExists(atPath: paths.sessionsDirectory.path))")

do {
    let snapshot = try LiveCodexStoreScanner(paths: paths).scan()
    print("Projects: \(snapshot.projects.count)")
    print("Unassigned chats: \(snapshot.unassignedThreads.count)")
    print("")

    for project in snapshot.projects.prefix(10) {
        print("Project: \(project.name) | chats: \(project.chats.count)")
        print("  \(project.path.path)")
    }

    if !snapshot.unassignedThreads.isEmpty {
        print("")
        print("Unassigned sample:")
        for thread in snapshot.unassignedThreads.prefix(10) {
            print("- \(thread.title) | \(thread.currentPath?.path ?? "no path")")
        }
    }
} catch {
    print("Scanner error: \(error.localizedDescription)")
    exit(1)
}
