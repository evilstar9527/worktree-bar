import Foundation

/// Launches an external terminal in a given worktree directory, optionally
/// running a command. This is the one piece that an in-terminal build (like
/// Ghostty++) gets for free but a standalone app must do itself.
///
/// The rendered template is executed via `/bin/sh -c`. Templates use these
/// placeholders:
///   {path}    — worktree directory, shell-quoted
///   {path_q}  — worktree directory, escaped for embedding inside an
///               AppleScript double-quoted string
///   {cmd}     — the command to run (may be empty), escaped for AppleScript
///   {cmd_e}   — expands to `-e <cmd>` when a command is present, else empty
///               (used by argv-style launchers like Ghostty)
enum TerminalLauncher {
    enum LaunchMode {
        case selectExisting
        case newTab
        case splitRight
        case splitDown
    }

    struct LaunchContext {
        var projectID: UUID
        var projectName: String
        var workspacePath: String
        var workspaceName: String
        var commandTitle: String
        var command: String
        var mode: LaunchMode = .selectExisting
    }

    enum LaunchError: LocalizedError {
        case shellFailed(exitCode: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case let .shellFailed(code, msg):
                return "terminal launch failed (\(code)): \(msg)"
            }
        }
    }

    private struct TabKey: Hashable {
        var projectID: UUID
        var path: String
        var command: String
    }

    private static var ghosttyProjectWindows: [UUID: String] = [:]
    private static var ghosttyTabs: [TabKey: String] = [:]
    private static var terminalProjectWindows: [UUID: Int] = [:]
    private static var terminalTabs: Set<TabKey> = []

    /// Render `config.template` for the given worktree path and command, then
    /// run it. `command` empty means "just open a shell".
    static func launch(config: TerminalConfig, path: String, command: String) throws {
        let context = LaunchContext(
            projectID: UUID(),
            projectName: "",
            workspacePath: path,
            workspaceName: (path as NSString).lastPathComponent,
            commandTitle: "",
            command: command
        )
        let rendered = render(template: config.template, context: context)
        try runShell(rendered)
    }

    /// Launch a worktree with project/workspace context. Built-in terminals use
    /// richer app-specific automation; custom templates keep the old behavior.
    static func launch(config: TerminalConfig, context: LaunchContext) throws {
        switch config.presetID {
        case "ghostty":
            try launchGhostty(context)
        case "terminal":
            try launchTerminalApp(context)
        default:
            let rendered = render(template: config.template, context: context)
            try runShell(rendered)
        }
    }

    /// Substitute placeholders. Exposed for testing/preview.
    static func render(template: String, path: String, command: String) -> String {
        let context = LaunchContext(
            projectID: UUID(),
            projectName: "",
            workspacePath: path,
            workspaceName: (path as NSString).lastPathComponent,
            commandTitle: "",
            command: command
        )
        return render(template: template, context: context)
    }

    /// Substitute placeholders. Exposed for testing/preview.
    static func render(template: String, context: LaunchContext) -> String {
        let trimmedCmd = context.command.trimmingCharacters(in: .whitespacesAndNewlines)

        // {path}: POSIX-quoted for use as a bare shell argument.
        let pathQuoted = shellQuote(context.workspacePath)
        // {path_q} / {cmd}: escaped for embedding inside an AppleScript
        // double-quoted string literal.
        let pathForAppleScript = appleScriptEscape(context.workspacePath)
        let cmdForAppleScript = appleScriptEscape(trimmedCmd)
        let projectForAppleScript = appleScriptEscape(context.projectName)
        let workspaceForAppleScript = appleScriptEscape(context.workspaceName)
        let titleForAppleScript = appleScriptEscape(tabTitle(for: context))
        // {cmd_e}: Ghostty-style `-e <command tokens…>`. Ghostty treats every
        // argument after `-e` as the command + its args (NOT one quoted blob),
        // and consumes the rest of argv — so it must come last in the template.
        // We append the command verbatim; the outer `/bin/sh -c` then splits it
        // into tokens for `open`. Fine for fixed agent commands.
        let cmdE = trimmedCmd.isEmpty ? "" : "-e \(trimmedCmd)"

        return template
            .replacingOccurrences(of: "{path_q}", with: pathForAppleScript)
            .replacingOccurrences(of: "{path}", with: pathQuoted)
            .replacingOccurrences(of: "{cmd_e}", with: cmdE)
            .replacingOccurrences(of: "{cmd}", with: cmdForAppleScript)
            .replacingOccurrences(of: "{project}", with: projectForAppleScript)
            .replacingOccurrences(of: "{workspace}", with: workspaceForAppleScript)
            .replacingOccurrences(of: "{title}", with: titleForAppleScript)
    }

    // MARK: - Internal

    private static func launchGhostty(_ context: LaunchContext) throws {
        let key = tabKey(for: context)

        switch context.mode {
        case .selectExisting:
            if let windowID = ghosttyProjectWindows[context.projectID],
               let tabID = ghosttyTabs[key],
               try selectGhosttyTab(windowID: windowID, tabID: tabID, title: tabTitle(for: context)) {
                return
            }

            let ids = try createGhosttyTab(context: context, existingWindowID: ghosttyProjectWindows[context.projectID])
            ghosttyProjectWindows[context.projectID] = ids.windowID
            ghosttyTabs[key] = ids.tabID

        case .newTab:
            let ids = try createGhosttyTab(context: context, existingWindowID: ghosttyProjectWindows[context.projectID])
            ghosttyProjectWindows[context.projectID] = ids.windowID
            ghosttyTabs[key] = ids.tabID

        case .splitRight, .splitDown:
            var windowID = ghosttyProjectWindows[context.projectID]
            var tabID = ghosttyTabs[key]

            let hasExistingTab: Bool
            if let existingWindowID = windowID, let existingTabID = tabID {
                hasExistingTab = try selectGhosttyTab(
                    windowID: existingWindowID,
                    tabID: existingTabID,
                    title: tabTitle(for: context)
                )
            } else {
                hasExistingTab = false
            }

            if !hasExistingTab {
                var baseContext = context
                baseContext.command = ""
                baseContext.commandTitle = ""
                baseContext.mode = .selectExisting
                let ids = try createGhosttyTab(context: baseContext, existingWindowID: ghosttyProjectWindows[context.projectID])
                windowID = ids.windowID
                tabID = ids.tabID
                ghosttyProjectWindows[context.projectID] = ids.windowID
                ghosttyTabs[key] = ids.tabID
            }

            guard let windowID, let tabID else { return }
            try splitGhosttyTab(context: context, windowID: windowID, tabID: tabID)
        }
    }

    private static func createGhosttyTab(
        context: LaunchContext,
        existingWindowID: String?
    ) throws -> (windowID: String, tabID: String) {
        let output = try runAppleScript(ghosttyCreateScript(
            context: context,
            existingWindowID: existingWindowID
        ))
        let lines = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else {
            return ("", "")
        }
        return (lines[0], lines[1])
    }

    private static func selectGhosttyTab(windowID: String, tabID: String, title: String) throws -> Bool {
        guard !windowID.isEmpty, !tabID.isEmpty else { return false }
        let script = """
        tell application "Ghostty"
            try
                set projectWindow to first window whose id is \(appleScriptString(windowID))
                set targetTab to first tab of projectWindow whose id is \(appleScriptString(tabID))
                select tab targetTab
                perform action \(appleScriptString(tabTitleAction(title))) on focused terminal of targetTab
                activate window projectWindow
                activate
                return "selected"
            on error
                return "missing"
            end try
        end tell
        """
        return try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines) == "selected"
    }

    private static func ghosttyCreateScript(
        context: LaunchContext,
        existingWindowID: String?
    ) -> String {
        let input = startupInput(for: context, includeCD: false)
        let config = """
        new surface configuration from {initial working directory:\(appleScriptString(context.workspacePath)), initial input:\(appleScriptString(input)), wait after command:true}
        """

        let existing = existingWindowID.map(appleScriptString) ?? "\"\""
        return """
        tell application "Ghostty"
            activate
            set surfaceConfig to \(config)
            set projectWindow to missing value
            if \(existing) is not "" then
                try
                    set projectWindow to first window whose id is \(existing)
                end try
            end if
            if projectWindow is missing value then
                set projectWindow to new window with configuration surfaceConfig
                set createdTab to selected tab of projectWindow
            else
                set createdTab to new tab in projectWindow with configuration surfaceConfig
                select tab createdTab
                activate window projectWindow
            end if
            perform action \(appleScriptString(tabTitleAction(tabTitle(for: context)))) on focused terminal of createdTab
            return (id of projectWindow) & linefeed & (id of createdTab)
        end tell
        """
    }

    private static func splitGhosttyTab(context: LaunchContext, windowID: String, tabID: String) throws {
        let direction = context.mode == .splitDown ? "down" : "right"
        let input = startupInput(for: context, includeCD: false)
        let script = """
        tell application "Ghostty"
            set projectWindow to first window whose id is \(appleScriptString(windowID))
            set targetTab to first tab of projectWindow whose id is \(appleScriptString(tabID))
            select tab targetTab
            activate window projectWindow
            set surfaceConfig to new surface configuration from {initial working directory:\(appleScriptString(context.workspacePath)), initial input:\(appleScriptString(input)), wait after command:true}
            set createdTerminal to split (focused terminal of targetTab) direction \(direction) with configuration surfaceConfig
            focus createdTerminal
            perform action \(appleScriptString(tabTitleAction(tabTitle(for: context)))) on createdTerminal
            activate
        end tell
        """
        _ = try runAppleScript(script)
    }

    private static func launchTerminalApp(_ context: LaunchContext) throws {
        let key = tabKey(for: context)
        let title = tabTitle(for: context)

        if context.mode == .selectExisting {
            if terminalTabs.contains(key),
               let windowID = terminalProjectWindows[context.projectID],
               try selectTerminalTab(windowID: windowID, title: title) {
                return
            }
        }

        let output = try runAppleScript(terminalCreateScript(
            context: context,
            existingWindowID: terminalProjectWindows[context.projectID]
        ))
        let lines = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let windowIDText = lines.first,
              let windowID = Int(windowIDText) else {
            return
        }
        terminalProjectWindows[context.projectID] = windowID
        terminalTabs.insert(key)
    }

    private static func selectTerminalTab(windowID: Int, title: String) throws -> Bool {
        let script = """
        tell application "Terminal"
            try
                set projectWindow to first window whose id is \(windowID)
                set index of projectWindow to 1
                repeat with candidateTab in tabs of projectWindow
                    if custom title of candidateTab is \(appleScriptString(title)) then
                        set selected of candidateTab to true
                        activate
                        return "selected"
                    end if
                end repeat
                return "missing"
            on error
                return "missing"
            end try
        end tell
        """
        return try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines) == "selected"
    }

    private static func terminalCreateScript(
        context: LaunchContext,
        existingWindowID: Int?
    ) -> String {
        let script = startupInput(for: context, includeCD: true)
        let title = tabTitle(for: context)
        let windowSetup: String
        if let existingWindowID {
            windowSetup = """
            try
                set projectWindow to first window whose id is \(existingWindowID)
                set index of projectWindow to 1
            end try
            """
        } else {
            windowSetup = ""
        }

        return """
        tell application "Terminal"
            set wasRunning to running
            activate
            set projectWindow to missing value
            \(windowSetup)
            if projectWindow is missing value then
                if not wasRunning then
                    -- Terminal auto-opens a default window when launched cold.
                    -- Wait for it, then run the command *in* that window instead
                    -- of letting `do script` spawn a second one.
                    repeat 50 times
                        if (count of windows) > 0 then exit repeat
                        delay 0.05
                    end repeat
                    if (count of windows) > 0 then
                        set createdTab to do script \(appleScriptString(script)) in front window
                        set projectWindow to front window
                    else
                        set createdTab to do script \(appleScriptString(script))
                        set projectWindow to front window
                    end if
                else
                    -- Already running: a plain `do script` opens a fresh window
                    -- for this project (no stray default window is created).
                    set createdTab to do script \(appleScriptString(script))
                    set projectWindow to front window
                end if
            else
                set createdTab to do script \(appleScriptString(script)) in projectWindow
            end if
            set custom title of createdTab to \(appleScriptString(title))
            set title displays custom title of createdTab to true
            return (id of projectWindow) & linefeed & (custom title of createdTab)
        end tell
        """
    }

    private static func tabKey(for context: LaunchContext) -> TabKey {
        TabKey(
            projectID: context.projectID,
            path: (context.workspacePath as NSString).standardizingPath,
            command: context.command.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func tabTitle(for context: LaunchContext) -> String {
        let workspace = context.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = (context.workspacePath as NSString).lastPathComponent
        return workspace.isEmpty ? fallback : workspace
    }

    private static func tabTitleAction(_ title: String) -> String {
        "set_tab_title:\(title)"
    }

    private static func startupInput(for context: LaunchContext, includeCD: Bool) -> String {
        var commands: [String] = []
        if includeCD {
            commands.append("cd \(shellQuote(context.workspacePath))")
        }

        let trimmedCommand = context.command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCommand.isEmpty {
            commands.append(trimmedCommand)
        }

        return commands.joined(separator: "\n") + "\n"
    }

    private static func runAppleScript(_ script: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()

        let so = String(
            data: out.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard p.terminationStatus == 0 else {
            let se = String(
                data: err.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw LaunchError.shellFailed(exitCode: p.terminationStatus, stderr: se)
        }
        return so
    }

    private static func runShell(_ command: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let se = String(
                data: err.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw LaunchError.shellFailed(exitCode: p.terminationStatus, stderr: se)
        }
    }

    /// POSIX single-quote a string for safe use as a single shell argument.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape backslashes and double quotes so the value can sit inside an
    /// AppleScript double-quoted string literal.
    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func appleScriptString(_ value: String) -> String {
        let parts = value.components(separatedBy: "\n").map { part in
            "\"\(appleScriptEscape(part))\""
        }
        return parts.joined(separator: " & linefeed & ")
    }
}
