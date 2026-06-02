import CodexChatMoverCore
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var projects: [CodexProject] = []
    @Published var unassignedThreads: [CodexThread] = []
    @Published var searchText = ""
    @Published var selectedProjectID: String?
    @Published var pendingMove: PendingMove?
    @Published var moveState: MoveState = .idle
    @Published var lastMove: MoveRecord?
    @Published var showingFirstRunNotice = true
    @Published var dataStatus = "Loading sample data"
    @Published var expandedProjectIDs: Set<String> = []

    private let scanner: CodexStoreScanning
    private let liveScanner: CodexStoreScanning?
    private let projectRegistry: ProjectRegistry
    private let threadMover: ThreadMoving
    private let moveRestorer: MoveRestoring?
    private let codexLauncher: CodexLauncher

    init(
        scanner: CodexStoreScanning,
        liveScanner: CodexStoreScanning? = nil,
        projectRegistry: ProjectRegistry,
        threadMover: ThreadMoving,
        codexLauncher: CodexLauncher
    ) {
        self.scanner = scanner
        self.liveScanner = liveScanner
        self.projectRegistry = projectRegistry
        self.threadMover = threadMover
        self.moveRestorer = threadMover as? MoveRestoring
        self.codexLauncher = codexLauncher
        reload()
        reloadLiveData()
    }

    var movableThreads: [CodexThread] {
        let byID = Dictionary(grouping: projects.flatMap(\.chats) + unassignedThreads, by: \.id)
        let unique = byID.compactMap { $0.value.first }
        return unique.sorted { lhs, rhs in
            (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
    }

    var filteredMovableThreads: [CodexThread] {
        filter(movableThreads)
    }

    func filteredProjectChats(_ project: CodexProject) -> [CodexThread] {
        filter(project.chats)
    }

    func reload() {
        do {
            let snapshot = try scanner.scan()
            projects = snapshot.projects
            unassignedThreads = snapshot.unassignedThreads
            dataStatus = "Sample data"
            selectedProjectID = selectedProjectID ?? projects.first?.id
            expandedProjectIDs = Set(projects.prefix(3).map(\.id))
        } catch {
            moveState = .failed("Could not scan Codex data: \(error.localizedDescription)")
        }
    }

    func reloadLiveData() {
        guard let liveScanner else {
            return
        }

        Task.detached(priority: .userInitiated) {
            do {
                let snapshot = try liveScanner.scan()
                await MainActor.run {
                    if !snapshot.projects.isEmpty || !snapshot.unassignedThreads.isEmpty {
                        self.projects = snapshot.projects
                        self.unassignedThreads = snapshot.unassignedThreads
                        self.selectedProjectID = snapshot.projects.first?.id
                        self.expandedProjectIDs = Set(snapshot.projects.prefix(3).map(\.id))
                        let chatCount = snapshot.projects.reduce(snapshot.unassignedThreads.count) { $0 + $1.chats.count }
                        self.dataStatus = "Live Codex data: \(snapshot.projects.count) projects, \(chatCount) chats"
                    }
                }
            } catch {
                await MainActor.run {
                    self.moveState = .failed("Could not scan Codex data: \(error.localizedDescription)")
                }
            }
        }
    }

    func addExistingProject() {
        guard let project = projectRegistry.addExistingProject() else {
            return
        }
        projects.append(project)
        selectedProjectID = project.id
        expandedProjectIDs.insert(project.id)
    }

    func createNewProject() {
        guard let project = projectRegistry.createNewProject() else {
            return
        }
        projects.append(project)
        selectedProjectID = project.id
        expandedProjectIDs.insert(project.id)
    }

    func selectProject(_ projectID: String) {
        selectedProjectID = projectID
    }

    func isProjectExpanded(_ projectID: String) -> Bool {
        expandedProjectIDs.contains(projectID)
    }

    func setProjectExpanded(_ projectID: String, expanded: Bool) {
        if expanded {
            expandedProjectIDs.insert(projectID)
        } else {
            expandedProjectIDs.remove(projectID)
        }
    }

    func requestMove(threadID: String, to projectID: String) {
        guard let thread = findThread(threadID),
              let project = projects.first(where: { $0.id == projectID }) else {
            return
        }
        pendingMove = PendingMove(thread: thread, project: project)
    }

    func confirmPendingMove() {
        guard let move = pendingMove else {
            return
        }

        pendingMove = nil
        moveState = .running(step: .checkingCodex, completed: 0)

        Task {
            await performPreviewMove(move)
        }
    }

    func cancelPendingMove() {
        pendingMove = nil
    }

    func openCodex() {
        codexLauncher.openCodex()
    }

    func undoLastMove() {
        guard let move = lastMove else {
            return
        }

        if let moveRestorer {
            do {
                try moveRestorer.restore(moveRecord: move)
                lastMove = nil
                moveState = .idle
                reload()
            } catch {
                moveState = .failed("Could not undo move: \(error.localizedDescription)")
            }
            return
        }

        undoPreviewMove(move)
    }

    private func undoPreviewMove(_ move: MoveRecord) {
        if let projectIndex = projects.firstIndex(where: { $0.path == move.toProjectPath }),
           let chatIndex = projects[projectIndex].chats.firstIndex(where: { $0.id == move.threadId }) {
            var chat = projects[projectIndex].chats.remove(at: chatIndex)
            chat.currentPath = move.fromPath
            chat.assignment = .outsideKnownProjects
            unassignedThreads.insert(chat, at: 0)
        }
        lastMove = nil
        moveState = .idle
    }

    private func performPreviewMove(_ move: PendingMove) async {
        let steps = MoveProgressStep.allCases

        for (index, step) in steps.enumerated() {
            moveState = .running(step: step, completed: Double(index) / Double(steps.count))
            try? await Task.sleep(for: .milliseconds(250))
        }

        do {
            let record = try await threadMover.move(thread: move.thread, to: move.project)
            applyMove(thread: move.thread, to: move.project)
            lastMove = record
            moveState = .succeeded(record)
        } catch {
            moveState = .failed(error.localizedDescription)
        }
    }

    private func applyMove(thread: CodexThread, to project: CodexProject) {
        unassignedThreads.removeAll { $0.id == thread.id }

        guard let projectIndex = projects.firstIndex(where: { $0.id == project.id }) else {
            return
        }

        var movedThread = thread
        movedThread.currentPath = project.path
        movedThread.assignment = .project(project.id)
        movedThread.updatedAt = Date()

        for index in projects.indices {
            projects[index].chats.removeAll { $0.id == thread.id }
        }
        projects[projectIndex].chats.insert(movedThread, at: 0)
        selectedProjectID = project.id
        expandedProjectIDs.insert(project.id)
    }

    private func findThread(_ id: String) -> CodexThread? {
        if let thread = unassignedThreads.first(where: { $0.id == id }) {
            return thread
        }

        return projects.flatMap(\.chats).first { $0.id == id }
    }

    private func filter(_ threads: [CodexThread]) -> [CodexThread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return threads
        }

        return threads.filter { thread in
            thread.title.localizedCaseInsensitiveContains(query)
        }
    }
}

struct PendingMove: Identifiable {
    let id = UUID()
    let thread: CodexThread
    let project: CodexProject
}

enum MoveState {
    case idle
    case running(step: MoveProgressStep, completed: Double)
    case succeeded(MoveRecord)
    case failed(String)
}
