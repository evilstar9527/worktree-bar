import SwiftUI
import AppKit

/// Sheet that runs `git worktree add` for a project. Full form: workspace name,
/// new branch toggle, base ref, target path, plus a sane default path of
/// `<repo>/.worktree/<name>`.
struct NewWorktreeSheet: View {
    let project: SidebarProject
    @ObservedObject var model: WorktreeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var path: String = ""
    @State private var ref: String = "HEAD"
    @State private var createBranch: Bool = true
    @State private var workspaceName: String = ""
    @State private var newBranchName: String = ""
    @State private var pathWasEdited: Bool = false
    @State private var availableRefs: [String] = []
    @State private var loadingRefs: Bool = true
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.title3)
                    .foregroundColor(AppPalette.blue)
                Text("New Worktree — \(project.name)")
                    .font(.headline)
            }

            Form {
                TextField("Workspace name", text: $workspaceName)

                TextField("New branch name", text: $newBranchName)
                    .onChange(of: newBranchName) { _ in autofillPathIfNeeded() }

                Toggle("Create new branch (-b)", isOn: $createBranch)
                    .onChange(of: createBranch) { _ in autofillPathIfNeeded() }

                HStack {
                    Text("Base ref")
                    if loadingRefs {
                        ProgressView().controlSize(.small)
                        Spacer()
                    } else {
                        Picker("", selection: $ref) {
                            Text("HEAD").tag("HEAD")
                            ForEach(availableRefs, id: \.self) { r in
                                Text(r).tag(r)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: ref) { _ in autofillPathIfNeeded() }
                    }
                }

                HStack {
                    TextField("Worktree path", text: pathBinding)
                    Button("Browse…") { pickPath() }
                }

                if let err = errorMessage {
                    InfoCard(systemImage: "exclamationmark.triangle.fill", message: err, tint: AppPalette.coral)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(submitting ? "Creating…" : "Create") { submit() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.blue)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(16)
        .frame(minWidth: 520)
        .background(AppPalette.canvas.ignoresSafeArea())
        .task { await loadRefs() }
        .onAppear { autofillPathIfNeeded() }
    }

    private var canSubmit: Bool {
        guard !submitting else { return false }
        guard !path.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if createBranch {
            return !newBranchName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !ref.isEmpty
    }

    private func loadRefs() async {
        let root = project.rootPath
        let refs: [String] = (try? WorktreeService.refs(in: root)) ?? []
        await MainActor.run {
            self.availableRefs = refs
            self.loadingRefs = false
        }
    }

    private func autofillPathIfNeeded() {
        guard !pathWasEdited else { return }
        path = defaultWorktreePath()
    }

    private var pathBinding: Binding<String> {
        Binding(
            get: { path },
            set: { newValue in
                path = newValue
                pathWasEdited = true
            }
        )
    }

    private func defaultWorktreePath() -> String {
        // The worktree directory is named after the branch, never the (often
        // CJK / free-form) workspace name. When not creating a branch we fall
        // back to the chosen base ref.
        let branchName = createBranch
            ? newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
            : ref
        let safeName = sanitizePathComponent(branchName.isEmpty ? "branch" : branchName)
        return ((project.rootPath as NSString).appendingPathComponent(".worktree") as NSString)
            .appendingPathComponent(safeName)
    }

    private func sanitizePathComponent(_ value: String) -> String {
        var result = ""
        var lastWasDash = false
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))

        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return trimmed.isEmpty ? "branch" : trimmed
    }

    private func pickPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            pathWasEdited = true
        }
    }

    private func submit() {
        submitting = true
        errorMessage = nil
        let p = project
        let target = path
        let baseRef = ref
        let mkBranch = createBranch
        let bName = newBranchName
        let wName = workspaceName
        Task {
            let result = await model.createWorktree(
                in: p,
                path: target,
                ref: mkBranch ? "" : baseRef,
                createBranch: mkBranch,
                newBranchName: mkBranch ? bName : nil,
                workspaceName: wName
            )
            await MainActor.run {
                submitting = false
                switch result {
                case .success:
                    dismiss()
                case let .failure(err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }
}
