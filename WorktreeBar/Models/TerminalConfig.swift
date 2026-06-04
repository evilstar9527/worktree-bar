import Foundation

/// A configurable agent / shell command the user can launch in a worktree.
/// `command` is empty for a plain terminal (no command executed).
struct AgentLauncher: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String
    var systemImage: String
    /// Shell command to run in the worktree. Empty → just open a terminal.
    var command: String

    static let defaults: [AgentLauncher] = [
        AgentLauncher(
            title: "Terminal",
            systemImage: "terminal",
            command: ""
        ),
        AgentLauncher(
            title: "codex",
            systemImage: "sparkles",
            command: "codex --dangerously-bypass-approvals-and-sandbox"
        ),
        AgentLauncher(
            title: "claude",
            systemImage: "sun.max",
            command: "claude --dangerously-skip-permissions"
        ),
    ]
}

/// Which terminal app to launch and the command template used to do it.
/// `template` supports `{path}` (worktree dir) and `{cmd}` (the command to run,
/// may be empty for a plain shell) placeholders.
struct TerminalConfig: Codable, Equatable {
    /// Stable identifier for the chosen preset (or "custom").
    var presetID: String
    /// Command line executed via `/bin/sh -c`, after placeholder substitution.
    var template: String

    /// Built-in presets, keyed by `presetID`.
    static let presets: [TerminalConfig] = [
        TerminalConfig(
            presetID: "ghostty",
            // Ghostty: open a new instance in the worktree, optionally run a command.
            // `-e` is appended only when a command is present (handled at render time).
            template: "open -na Ghostty --args --working-directory={path} {cmd_e}"
        ),
        TerminalConfig(
            presetID: "terminal",
            template: "osascript -e 'tell application \"Terminal\" to do script \"cd {path_q}; {cmd}\"' -e 'tell application \"Terminal\" to activate'"
        ),
        TerminalConfig(
            presetID: "iterm",
            template: "osascript -e 'tell application \"iTerm\" to create window with default profile command \"/bin/sh -lc \\\"cd {path_q}; {cmd}; exec $SHELL\\\"\"'"
        ),
    ]

    static let `default` = presets[0]

    static func preset(for id: String) -> TerminalConfig? {
        presets.first { $0.presetID == id }
    }
}
