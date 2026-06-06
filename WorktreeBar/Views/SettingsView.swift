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
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.title3)
                    .foregroundColor(AppPalette.blue)
                Text("Terminal")
                    .font(.headline)
            }

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
            .padding(.horizontal, CardMetrics.cardPaddingH)
            .padding(.vertical, CardMetrics.cardPaddingV)
            .cardBackground(tint: AppPalette.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Launch command template")
                    .font(.subheadline)
                TextEditor(text: $template)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 70)
                    .padding(4)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    }
                    .onChange(of: template) { _ in
                        // Editing the template moves us to "custom".
                        if TerminalConfig.preset(for: selectedPreset)?.template != template {
                            selectedPreset = "custom"
                        }
                        apply()
                    }
                Text("Placeholders: {path} {path_q} {cmd} {cmd_e} {project} {workspace} {title}")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, CardMetrics.cardPaddingH)
            .padding(.vertical, CardMetrics.cardPaddingV)
            .cardBackground(tint: AppPalette.violet)

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview")
                    .font(.subheadline)
                Text(previewText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
                    }
            }
            .padding(.horizontal, CardMetrics.cardPaddingH)
            .padding(.vertical, CardMetrics.cardPaddingV)
            .cardBackground(tint: AppPalette.mint)

            Spacer()
        }
        .padding(16)
        .frame(width: 480, height: 420)
        .background(AppPalette.canvas.ignoresSafeArea())
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
