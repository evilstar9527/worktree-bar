import SwiftUI

/// Bridges context from the menu popover to the standalone windows opened via
/// `openWindow(id:)`. `MenuBarExtra(.window)` popovers can't reliably host
/// SwiftUI sheets, so destructive/creation flows live in their own windows.
@MainActor
final class WindowRouter: ObservableObject {
    static let shared = WindowRouter()

    struct DeleteTarget: Equatable {
        var worktree: GitWorktree
        var project: SidebarProject
    }

    @Published var newWorktreeProject: SidebarProject?
    @Published var deleteTarget: DeleteTarget?
    @Published var openWorktreesRequest = UUID()

    func requestOpenWorktrees() {
        openWorktreesRequest = UUID()
    }
}
