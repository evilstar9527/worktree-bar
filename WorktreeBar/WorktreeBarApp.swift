import SwiftUI

@main
struct WorktreeBarApp: App {
    @StateObject private var model = WorktreeViewModel.shared
    @StateObject private var router = WindowRouter.shared

    var body: some Scene {
        MenuBarExtra("Worktrees", systemImage: "tree") {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.window)

        // New worktree flow — opened from the menu via openWindow(id:).
        Window("New Worktree", id: "new-worktree") {
            NewWorktreeWindow(model: model, router: router)
        }
        .windowResizability(.contentSize)

        // Delete confirmation flow.
        Window("Delete Worktree", id: "delete-worktree") {
            DeleteWorktreeView(model: model, router: router)
        }
        .windowResizability(.contentSize)

        // Settings.
        Window("Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

/// Hosts `NewWorktreeSheet` content in a standalone window, pulling the target
/// project from the router. Shows a fallback if launched without context.
private struct NewWorktreeWindow: View {
    @ObservedObject var model: WorktreeViewModel
    @ObservedObject var router: WindowRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let project = router.newWorktreeProject {
                NewWorktreeSheet(project: project, model: model)
            } else {
                VStack(spacing: 8) {
                    Text("No project selected.")
                    Button("Close") { dismiss() }
                }
                .padding(24)
            }
        }
    }
}
