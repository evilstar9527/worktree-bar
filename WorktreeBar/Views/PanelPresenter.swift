import AppKit

/// Helpers for presenting modal panels and windows from a `LSUIElement`
/// (menu bar accessory) app. Two problems this works around:
///
///  1. An accessory app is not a "regular" app, so `NSOpenPanel`/windows can't
///     become key or come to the front until the activation policy is bumped to
///     `.regular`. We restore `.accessory` once nothing is on screen.
///  2. The `MenuBarExtra(.window)` popover closes as soon as focus leaves it,
///     which tears down a panel opened synchronously from inside it. Deferring
///     to the next runloop lets the popover finish closing first.
@MainActor
enum PanelPresenter {
    /// Run a directory-picker and return the chosen path, handling activation
    /// policy and popover dismissal. Calls back on the main actor.
    static func chooseDirectory(
        prompt: String,
        message: String,
        completion: @escaping (String?) -> Void
    ) {
        bringToFront()
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = prompt
            panel.message = message
            panel.level = .modalPanel
            let result = panel.runModal()
            let path = (result == .OK) ? panel.url?.path : nil
            restoreIfPossible()
            completion(path)
        }
    }

    /// Bring the app to the foreground so panels/windows can take focus.
    static func bringToFront() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Drop back to accessory (menu-bar-only) once no real app windows remain.
    /// Call this when a presented window is dismissed.
    static func restoreIfPossible() {
        // Defer so a window that is mid-dismiss is no longer counted.
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { win in
                win.isVisible && win.canBecomeKey
            }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
