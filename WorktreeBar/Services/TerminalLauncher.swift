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
    enum LaunchError: LocalizedError {
        case shellFailed(exitCode: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case let .shellFailed(code, msg):
                return "terminal launch failed (\(code)): \(msg)"
            }
        }
    }

    /// Render `config.template` for the given worktree path and command, then
    /// run it. `command` empty means "just open a shell".
    static func launch(config: TerminalConfig, path: String, command: String) throws {
        let rendered = render(template: config.template, path: path, command: command)
        try runShell(rendered)
    }

    /// Substitute placeholders. Exposed for testing/preview.
    static func render(template: String, path: String, command: String) -> String {
        let trimmedCmd = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // {path}: POSIX-quoted for use as a bare shell argument.
        let pathQuoted = shellQuote(path)
        // {path_q} / {cmd}: escaped for embedding inside an AppleScript
        // double-quoted string literal.
        let pathForAppleScript = appleScriptEscape(path)
        let cmdForAppleScript = appleScriptEscape(trimmedCmd)
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
    }

    // MARK: - Internal

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
}
