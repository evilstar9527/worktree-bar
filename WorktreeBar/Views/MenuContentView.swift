import SwiftUI
import AppKit

/// The content shown when the menu bar icon is clicked. Lists projects, each
/// expandable into its managed worktrees, with quick-launch buttons.
struct MenuContentView: View {
    @ObservedObject var model: WorktreeViewModel
    @Environment(\.openWindow) private var openWindow

    @State private var renaming: GitWorktree?
    @State private var renameText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if model.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.projects) { project in
                            projectSection(project)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 460)
            }

            Divider()
            footer
        }
        .frame(width: 380)
        .onAppear { model.refreshAllExpanded() }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            Text("Worktrees")
                .font(.headline)
            Spacer()
            Button {
                addProject()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Add a git project")

            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            if let err = model.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tree")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No projects yet")
                .foregroundColor(.secondary)
            Button("Add a git project…") { addProject() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Project section

    @ViewBuilder
    private func projectSection(_ project: SidebarProject) -> some View {
        let isExpanded = model.expanded.contains(project.id)

        HStack(spacing: 6) {
            Button {
                model.toggleExpanded(project)
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .frame(width: 12)
                Text(project.name)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderless)

            Spacer()

            if model.loading.contains(project.id) {
                ProgressView().controlSize(.small)
            }

            Menu {
                Button("New Worktree…") { newWorktree(project) }
                Button("Refresh") { model.refresh(project) }
                Divider()
                Button("Remove Project", role: .destructive) {
                    model.removeProject(project)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(width: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)

        if isExpanded {
            let trees = model.worktrees[project.id] ?? []
            if trees.isEmpty && !model.loading.contains(project.id) {
                Text("No managed worktrees. Use “New Worktree…”.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 34)
                    .padding(.vertical, 4)
            } else {
                ForEach(trees) { wt in
                    worktreeRow(wt, in: project)
                }
            }
        }
    }

    @ViewBuilder
    private func worktreeRow(_ wt: GitWorktree, in project: SidebarProject) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(model.displayName(for: wt))
                    .lineLimit(1)
                Spacer()

                ForEach(model.launchers) { launcher in
                    Button {
                        model.open(wt, command: launcher.command)
                    } label: {
                        Image(systemName: launcher.systemImage)
                    }
                    .buttonStyle(.borderless)
                    .help(launcher.command.isEmpty
                          ? "Open \(launcher.title)"
                          : "Run: \(launcher.command)")
                }
            }
            Text(model.secondaryLabel(for: wt))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.leading, 34)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .contextMenu {
            Button("Rename Workspace…") { beginRename(wt) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(wt.path, forType: .string)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [URL(fileURLWithPath: wt.path)]
                )
            }
            Divider()
            Button("Delete Workspace…", role: .destructive) {
                confirmDelete(wt, in: project)
            }
        }
        .popover(isPresented: renameBinding(for: wt)) {
            renamePopover(for: wt)
        }
    }

    // MARK: - Rename

    private func renameBinding(for wt: GitWorktree) -> Binding<Bool> {
        Binding(
            get: { renaming == wt },
            set: { if !$0 { renaming = nil } }
        )
    }

    private func beginRename(_ wt: GitWorktree) {
        renameText = model.displayName(for: wt)
        renaming = wt
    }

    private func renamePopover(for wt: GitWorktree) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rename workspace").font(.subheadline)
            TextField("Name", text: $renameText)
                .frame(width: 220)
                .onSubmit { commitRename(wt) }
            HStack {
                Spacer()
                Button("Cancel") { renaming = nil }
                Button("Save") { commitRename(wt) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private func commitRename(_ wt: GitWorktree) {
        model.renameWorkspace(for: wt, to: renameText)
        renaming = nil
    }

    // MARK: - Actions

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose the root of a git repository"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.lastPathComponent
        model.addProject(name: name, rootPath: url.path)
    }

    private func newWorktree(_ project: SidebarProject) {
        WindowRouter.shared.newWorktreeProject = project
        openWindow(id: "new-worktree")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func confirmDelete(_ wt: GitWorktree, in project: SidebarProject) {
        WindowRouter.shared.deleteTarget = .init(worktree: wt, project: project)
        openWindow(id: "delete-worktree")
        NSApp.activate(ignoringOtherApps: true)
    }
}
