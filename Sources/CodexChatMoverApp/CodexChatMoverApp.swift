import CodexChatMoverCore
import SwiftUI

@main
struct CodexChatMoverApp: App {
    @StateObject private var viewModel = AppViewModel(
        scanner: SampleCodexStoreScanner(),
        liveScanner: LiveCodexStoreScanner(),
        projectRegistry: ProjectRegistry(),
        threadMover: SafeThreadMover(),
        codexLauncher: CodexLauncher()
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Existing Folder...") {
                    viewModel.addExistingProject()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Create New Project...") {
                    viewModel.createNewProject()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
