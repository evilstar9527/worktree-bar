import SwiftUI

/// Settings window: choose the preferred terminal preset, optionally edit the
/// raw launch template, and preview how it renders.
struct SettingsView: View {
    @ObservedObject var model: WorktreeViewModel

    @State private var selectedPreset: String = TerminalConfig.default.presetID
    @State private var template: String = TerminalConfig.default.template

    private let presetNames: [String: String] = [
        "ghostty": "Ghostty",
        "terminal": "Terminal.app",
        "iterm": "iTerm2",
        "custom": "Custom",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Terminal")
                .font(.headline)

            Picker("Preferred terminal", selection: $selectedPreset) {
                ForEach(["ghostty", "terminal", "iterm"], id: \.self) { id in
                    Text(presetNames[id] ?? id).tag(id)
                }
                Text("Custom").tag("custom")
            }
            .onChange(of: selectedPreset) { id in
                if let preset = TerminalConfig.preset(for: id) {
                    template = preset.template
                }
                apply()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Launch command template")
                    .font(.subheadline)
                TextEditor(text: $template)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 70)
                    .border(Color.secondary.opacity(0.3))
                    .onChange(of: template) { _ in
                        // Editing the template moves us to "custom".
                        if TerminalConfig.preset(for: selectedPreset)?.template != template {
                            selectedPreset = "custom"
                        }
                        apply()
                    }
                Text("Placeholders: {path} {path_q} {cmd} {cmd_e}")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview")
                    .font(.subheadline)
                Text(previewText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 480, height: 320)
        .onAppear {
            selectedPreset = model.terminalConfig.presetID
            template = model.terminalConfig.template
        }
    }

    private var previewText: String {
        TerminalLauncher.render(
            template: template,
            path: "/Users/me/proj/.worktree/feature-x",
            command: "claude --dangerously-skip-permissions"
        )
    }

    private func apply() {
        model.terminalConfig = TerminalConfig(presetID: selectedPreset, template: template)
    }
}
