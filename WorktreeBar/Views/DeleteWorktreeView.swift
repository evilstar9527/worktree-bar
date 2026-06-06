import SwiftUI

/// Confirmation window for deleting a worktree, with an opt-in to also delete
/// the local branch (`git branch -D`).
struct DeleteWorktreeView: View {
    @ObservedObject var model: WorktreeViewModel
    @ObservedObject var router: WindowRouter
    @Environment(\.dismiss) private var dismiss

    @State private var deleteLocalBranch: Bool = false
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let target = router.deleteTarget {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.title3)
                        .foregroundColor(AppPalette.coral)
                    Text("Delete workspace?")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName(for: target.worktree))
                        .fontWeight(.medium)
                    Text(target.worktree.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CardMetrics.cardPaddingH)
                .padding(.vertical, CardMetrics.cardPaddingV)
                .cardBackground(tint: AppPalette.coral)

                if let branch = target.worktree.branch {
                    Toggle("Also delete local branch “\(branch)” (-D)", isOn: $deleteLocalBranch)
                }

                InfoCard(
                    systemImage: "info.circle",
                    message: "This removes the worktree from git. The directory is deleted by git if it is clean.",
                    tint: AppPalette.amber,
                    lineLimit: nil
                )

                if let err = errorMessage {
                    InfoCard(systemImage: "exclamationmark.triangle.fill", message: err, tint: AppPalette.coral)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(submitting ? "Deleting…" : "Delete", role: .destructive) {
                        submit(target)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.coral)
                    .keyboardShortcut(.defaultAction)
                    .disabled(submitting)
                }
            } else {
                Text("Nothing to delete.")
                Button("Close") { dismiss() }
            }
        }
        .padding(16)
        .frame(minWidth: 420)
        .background(AppPalette.canvas.ignoresSafeArea())
    }

    private func submit(_ target: WindowRouter.DeleteTarget) {
        submitting = true
        errorMessage = nil
        Task {
            let result = await model.deleteWorkspace(
                target.worktree,
                in: target.project,
                deleteLocalBranch: deleteLocalBranch
            )
            await MainActor.run {
                submitting = false
                switch result {
                case .success:
                    router.deleteTarget = nil
                    dismiss()
                case let .failure(err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }
}
