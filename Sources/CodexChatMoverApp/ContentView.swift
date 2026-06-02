import CodexChatMoverCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            ProjectSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            ChatWorkspace()
        }
        .frame(minWidth: 960, minHeight: 620)
        .alert("Codex Chat Mover", isPresented: $viewModel.showingFirstRunNotice) {
            Button("Continue") {}
        } message: {
            Text("This app moves local Codex chat metadata. Before real moves, it will require Codex Desktop to be closed and create a backup first.")
        }
        .sheet(item: $viewModel.pendingMove) { move in
            MoveConfirmationView(move: move)
                .environmentObject(viewModel)
        }
        .overlay(alignment: .bottomTrailing) {
            MoveStatusOverlay()
                .environmentObject(viewModel)
                .padding()
        }
    }
}

private struct ProjectSidebar: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Projects") {
                    ForEach(viewModel.projects) { project in
                        DisclosureGroup(isExpanded: Binding(
                            get: { viewModel.isProjectExpanded(project.id) },
                            set: { viewModel.setProjectExpanded(project.id, expanded: $0) }
                        )) {
                            ForEach(viewModel.filteredProjectChats(project)) { chat in
                                ChatRow(thread: chat, compact: true)
                                    .padding(.leading, 6)
                            }
                        } label: {
                            ProjectRow(project: project, isSelected: viewModel.selectedProjectID == project.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectProject(project.id)
                                }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            items.forEach { threadID in
                                viewModel.requestMove(threadID: threadID, to: project.id)
                            }
                            return true
                        }
                    }
                }
            }

            Divider()

            HStack {
                Menu {
                    Button("Add Existing Folder...") {
                        viewModel.addExistingProject()
                    }
                    Button("Create in Codex Projects...") {
                        viewModel.createNewProject()
                    }
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .menuStyle(.button)

                Spacer()

                Button {
                    if viewModel.lastMove != nil {
                        viewModel.undoLastMove()
                    } else {
                        viewModel.reloadPreferredData()
                    }
                } label: {
                    Image(systemName: viewModel.lastMove == nil ? "arrow.clockwise" : "arrow.uturn.backward")
                }
                .help(viewModel.lastMove == nil ? "Rescan" : "Undo Last Move")
            }
            .padding(10)
        }
    }
}

private struct ProjectRow: View {
    let project: CodexProject
    let isSelected: Bool

    var body: some View {
        Label(project.name, systemImage: isSelected ? "folder.fill" : "folder")
            .font(.body.weight(isSelected ? .semibold : .regular))
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.selection.opacity(0.22))
                }
            }
    }
}

private struct ChatWorkspace: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var selectedProject: CodexProject? {
        viewModel.projects.first { $0.id == viewModel.selectedProjectID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Movable Chats")
                        .font(.title2.weight(.semibold))
                    Text("\(viewModel.dataStatus). Drag any chat onto the selected project to move it.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TextField("Search title", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                List {
                    ForEach(viewModel.filteredMovableThreads) { thread in
                        ChatRow(thread: thread)
                            .draggable(thread.id)
                    }
                }
                .frame(minWidth: 420)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    if let selectedProject {
                        SelectedProjectDropPanel(project: selectedProject)
                            .environmentObject(viewModel)
                    } else {
                        ContentUnavailableView(
                            "No Project Selected",
                            systemImage: "folder",
                            description: Text("Choose or add a project to start organizing chats.")
                        )
                    }
                }
                .padding()
                .frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SelectedProjectDropPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let project: CodexProject

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(project.name, systemImage: "folder.fill")
                .font(.title3.weight(.semibold))

            Text(project.path.path)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            DropTarget(project: project)
                .environmentObject(viewModel)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("How to use")
                    .font(.headline)
                Text("1. Quit Codex Desktop.")
                Text("2. Choose the target project on the left.")
                Text("3. Drag a chat from the middle list into the drop area above.")
                Text("4. Confirm the move, then reopen Codex.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DropTarget: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let project: CodexProject

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Drop chat here")
                .font(.headline)
            Text("Move the dragged chat into \(project.name)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        }
        .dropDestination(for: String.self) { items, _ in
            items.forEach { threadID in
                viewModel.requestMove(threadID: threadID, to: project.id)
            }
            return true
        }
    }
}

private struct ChatRow: View {
    let thread: CodexThread
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            Text(thread.title)
                .font(compact ? .callout : .headline)
                .lineLimit(1)

            if !compact, let preview = thread.preview {
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let updatedAt = thread.updatedAt {
                Text(updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, compact ? 2 : 6)
    }
}

private struct MoveConfirmationView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let move: PendingMove

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Move chat to \"\(move.project.name)\"?", systemImage: "arrow.right.folder")
                .font(.title3.weight(.semibold))

            Text("A backup will be created first. The chat should appear under this project after Codex Desktop restarts.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(move.thread.title)
                    .font(.headline)
                Text(move.project.path.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding()
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.cancelPendingMove()
                }
                Button("Move") {
                    viewModel.confirmPendingMove()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct MoveStatusOverlay: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        switch viewModel.moveState {
        case .idle:
            EmptyView()
        case let .running(step, completed):
            StatusCard {
                Text("Moving chat...")
                    .font(.headline)
                ProgressView(value: completed)
                Text(step.rawValue)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .succeeded:
            StatusCard(onClose: viewModel.dismissMoveStatus) {
                Text("Moved and verified")
                    .font(.headline)
                Text("Open Codex Desktop to refresh the sidebar and continue working.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Undo Last Move") {
                        viewModel.undoLastMove()
                    }
                    Button("Open Codex") {
                        viewModel.openCodex()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        case let .failed(message):
            StatusCard(onClose: viewModel.dismissMoveStatus) {
                Text("Move failed")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusCard<Content: View>: View {
    var onClose: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let onClose {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        content
                    }

                    Spacer(minLength: 12)

                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
                }
            } else {
                content
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 12, y: 4)
    }
}
