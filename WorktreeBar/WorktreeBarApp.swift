import SwiftUI
import AppKit

@main
struct WorktreeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = WorktreeViewModel.shared
    @StateObject private var router = WindowRouter.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model, presentation: .menu)
        } label: {
            Label("Worktrees", systemImage: "tree")
                .background(OpenWorktreesRequestHandler(router: router))
        }
        .menuBarExtraStyle(.window)

        Window("Worktrees", id: "worktrees") {
            MenuContentView(model: model, presentation: .window)
                .onDisappear { PanelPresenter.restoreIfPossible() }
        }
        .windowResizability(.contentSize)

        // New worktree flow — opened from the menu via openWindow(id:).
        Window("New Worktree", id: "new-worktree") {
            NewWorktreeWindow(model: model, router: router)
                .onDisappear { PanelPresenter.restoreIfPossible() }
        }
        .windowResizability(.contentSize)

        // Delete confirmation flow.
        Window("Delete Worktree", id: "delete-worktree") {
            DeleteWorktreeView(model: model, router: router)
                .onDisappear { PanelPresenter.restoreIfPossible() }
        }
        .windowResizability(.contentSize)

        // Settings.
        Window("Settings", id: "settings") {
            SettingsView(model: model)
                .onDisappear { PanelPresenter.restoreIfPossible() }
        }
        .windowResizability(.contentSize)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        requestOpenWorktrees()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        requestOpenWorktrees()
        return true
    }

    private func requestOpenWorktrees() {
        DispatchQueue.main.async {
            WindowRouter.shared.requestOpenWorktrees()
        }
    }
}

private struct OpenWorktreesRequestHandler: View {
    @ObservedObject var router: WindowRouter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                openWorktreesWindow()
            }
            .onChange(of: router.openWorktreesRequest) { _ in
                openWorktreesWindow()
            }
    }

    private func openWorktreesWindow() {
        PanelPresenter.bringToFront()
        openWindow(id: "worktrees")
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
