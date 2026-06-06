import SwiftUI
import AppKit

/// The content shown when the menu bar icon is clicked. Lists projects, each
/// expandable into its managed worktrees, with quick-launch buttons.
struct MenuContentView: View {
    enum Presentation {
        case menu
        case window
    }

    @ObservedObject var model: WorktreeViewModel
    var presentation: Presentation = .menu

    @Environment(\.openWindow) private var openWindow

    @State private var renaming: GitWorktree?
    @State private var renameText: String = ""
    @State private var activeReorderID: String?
    @State private var reorderPreviewID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ZStack {
                AppPalette.canvas.ignoresSafeArea()

                if model.projects.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: CardMetrics.rowVSpacing) {
                            ForEach(model.projects) { project in
                                projectSection(project)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, gutter)
                        .padding(.vertical, 10)
                    }
                }
            }

            Divider()
            footer
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .onAppear { model.refreshAllExpanded() }
    }

    /// Narrow popover wants tighter spacing than the standalone window.
    private var compact: Bool { presentation == .menu }
    private var gutter: CGFloat { compact ? CardMetrics.compactGutter : CardMetrics.sectionGutter }
    private var cardPaddingH: CGFloat { compact ? CardMetrics.compactPaddingH : CardMetrics.cardPaddingH }

    private var frameSize: CGSize {
        switch presentation {
        case .menu:
            CGSize(width: 380, height: 440)
        case .window:
            CGSize(width: 680, height: 560)
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tree.fill")
                .font(.title3)
                .foregroundStyle(
                    LinearGradient(colors: [AppPalette.mint, AppPalette.blue],
                                   startPoint: .top, endPoint: .bottom)
                )
            Text("Worktrees")
                .font(.headline)
            Spacer()
            Button {
                PanelPresenter.bringToFront()
                openWindow(id: "worktrees")
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .help("Open Worktrees window")

            Button {
                addProject()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Add a git project")

            Button {
                PanelPresenter.bringToFront()
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppPalette.blue.opacity(0.06))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let err = model.lastError {
                InfoCard(systemImage: "exclamationmark.triangle.fill", message: err, tint: AppPalette.coral)
            }
            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppPalette.blue.opacity(0.04))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tree.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(colors: [AppPalette.mint, AppPalette.blue],
                                   startPoint: .top, endPoint: .bottom)
                )
            Text("No projects yet")
                .foregroundColor(.secondary)
            Button("Add a git project…") { addProject() }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.blue)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, gutter)
    }

    // MARK: - Project section

    @ViewBuilder
    private func projectSection(_ project: SidebarProject) -> some View {
        let isExpanded = model.expanded.contains(project.id)
        let reorderID = "project:\(project.id.uuidString)"

        HoverableRow { isHovered in
            HStack(spacing: 6) {
                dragHandle(
                    id: reorderID,
                    rowHeight: 28,
                    moveBy: { model.moveProject(project, by: $0) },
                    previewID: { projectPreviewID(for: project, by: $0) },
                    help: "Drag to reorder project"
                )

                Button {
                    model.toggleExpanded(project)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Image(systemName: "folder.fill")
                        .font(.callout)
                        .foregroundColor(AppPalette.indigo)
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)

                Spacer()

                if model.loading.contains(project.id) {
                    ProgressView().controlSize(.small)
                }

                Group {
                    Button {
                        newWorktree(project)
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 20)
                    .help("New worktree")

                    Button {
                        model.refresh(project)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 20)
                    .help("Refresh")

                    Button(role: .destructive) {
                        model.removeProject(project)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 20)
                    .help("Remove project")
                }
                .foregroundColor(.secondary)
                .opacity(isHovered ? 1.0 : 0.55)
                .animation(.easeOut(duration: 0.12), value: isHovered)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: CardMetrics.cardCornerRadius, style: .continuous)
                    .fill(AppPalette.indigo.opacity(isExpanded ? 0.10 : (isHovered ? 0.06 : 0.0)))
            }
            .overlay(reorderHighlightOverlay(for: reorderID))
        }

        if isExpanded {
            let trees = model.worktrees[project.id] ?? []
            if model.notGitRepo.contains(project.id) {
                notGitRepoRow(project)
            } else if trees.isEmpty && !model.loading.contains(project.id) {
                emptyWorktreeRow
            } else {
                ForEach(trees) { wt in
                    worktreeRow(
                        wt,
                        in: project,
                        isCurrent: model.isCurrentWorkspace(wt, in: project)
                    )
                }
            }
        }
    }

    /// Dashed placeholder card shown when an expanded project has no worktrees.
    private var emptyWorktreeRow: some View {
        Text("No worktrees found.")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, cardPaddingH)
            .padding(.vertical, 10)
            .padding(.leading, 26)
            .dashedCard()
    }

    @ViewBuilder
    private func notGitRepoRow(_ project: SidebarProject) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Not a git repository")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button {
                model.initGit(project)
            } label: {
                Label("git init", systemImage: "wand.and.stars")
                    .font(.caption)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, cardPaddingH)
        .padding(.vertical, 8)
        .padding(.leading, 26)
        .dashedCard()
    }

    @ViewBuilder
    private func worktreeRow(_ wt: GitWorktree, in project: SidebarProject, isCurrent: Bool) -> some View {
        let reorderID = "workspace:\(project.id.uuidString):\(wt.path)"

        HoverableRow { isHovered in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    dragHandle(
                        id: reorderID,
                        rowHeight: 42,
                        moveBy: { model.moveWorkspace(wt, in: project.id, by: $0) },
                        previewID: { workspacePreviewID(for: wt, in: project.id, by: $0) },
                        help: "Drag to reorder workspace"
                    )

                    Image(systemName: isCurrent ? "house.fill" : "point.3.connected.trianglepath.dotted")
                        .font(.callout)
                        .foregroundColor(isCurrent ? AppPalette.blue : AppPalette.mint)
                    Text(model.displayName(for: wt))
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .lineLimit(1)

                    badges(for: wt, isCurrent: isCurrent)

                    Spacer()

                    HStack(spacing: 3) {
                        ForEach(Array(model.launchers.enumerated()), id: \.element.id) { index, launcher in
                            launcherButton(launcher, index: index, wt: wt, in: project)
                        }
                    }
                    .opacity(isHovered ? 1.0 : 0.8)
                    .animation(.easeOut(duration: 0.12), value: isHovered)
                }
                Text(model.secondaryLabel(for: wt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 26)
            }
            .padding(.horizontal, cardPaddingH)
            .padding(.vertical, CardMetrics.cardPaddingV)
            .cardBackground(tint: isCurrent ? AppPalette.blue : AppPalette.mint,
                            isAccented: isCurrent,
                            isHovered: isHovered)
            .overlay(reorderHighlightOverlay(for: reorderID))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                model.openTerminal(wt, in: project)
            }
            .help("Double-click to open a terminal here")
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
                // The project's root workspace should be removed by removing the
                // project, not via `git worktree remove`.
                if !isCurrent {
                    Divider()
                    Button("Delete Workspace…", role: .destructive) {
                        confirmDelete(wt, in: project)
                    }
                }
            }
            .popover(isPresented: renameBinding(for: wt)) {
                renamePopover(for: wt)
            }
        }
    }

    /// Status badges shown after a worktree's name. Order: current, then the
    /// git-state flags. All are pure display over existing `GitWorktree` fields.
    @ViewBuilder
    private func badges(for wt: GitWorktree, isCurrent: Bool) -> some View {
        HStack(spacing: 4) {
            if isCurrent {
                WorktreeBadge(kind: .current, compact: compact)
            }
            if wt.isDetached, wt.branch == nil {
                WorktreeBadge(kind: .detached, compact: compact)
            }
            if wt.isLocked {
                WorktreeBadge(kind: .locked, compact: compact)
            }
            if wt.isPrunable {
                WorktreeBadge(kind: .prunable, compact: compact)
            }
        }
    }

    private func launcherButton(_ launcher: AgentLauncher, index: Int, wt: GitWorktree, in project: SidebarProject) -> some View {
        Button {
            model.open(wt, in: project, launcher: launcher)
        } label: {
            Image(systemName: launcher.systemImage)
        }
        .buttonStyle(LauncherIconButtonStyle(tint: AppPalette.launcherColor(index)))
        .contextMenu {
            Button("Open New Tab") {
                model.open(wt, in: project, launcher: launcher, mode: .newTab)
            }

            if model.supportsTerminalSplits {
                Button("Split Right") {
                    model.open(wt, in: project, launcher: launcher, mode: .splitRight)
                }
                Button("Split Down") {
                    model.open(wt, in: project, launcher: launcher, mode: .splitDown)
                }
            }
        }
        .help(launcher.command.isEmpty
              ? "Open \(launcher.title)"
              : "Run: \(launcher.command)")
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
        PanelPresenter.chooseDirectory(
            prompt: "Add Project",
            message: "Choose the root of a git repository"
        ) { path in
            guard let path else { return }
            let name = (path as NSString).lastPathComponent
            model.addProject(name: name, rootPath: path)
        }
    }

    private func newWorktree(_ project: SidebarProject) {
        WindowRouter.shared.newWorktreeProject = project
        PanelPresenter.bringToFront()
        openWindow(id: "new-worktree")
    }

    private func confirmDelete(_ wt: GitWorktree, in project: SidebarProject) {
        WindowRouter.shared.deleteTarget = .init(worktree: wt, project: project)
        PanelPresenter.bringToFront()
        openWindow(id: "delete-worktree")
    }

    private func dragHandle(
        id: String,
        rowHeight: CGFloat,
        moveBy: @escaping (Int) -> Void,
        previewID: @escaping (Int) -> String?,
        help: String
    ) -> some View {
        let isActive = activeReorderID == id
        let stepHeight = max(rowHeight, 24)

        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isActive ? .accentColor : .secondary)
            .frame(width: 26, height: 24)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        activeReorderID = id
                        let offset = reorderOffset(for: value.translation.height, stepHeight: stepHeight)
                        reorderPreviewID = previewID(offset)
                    }
                    .onEnded { value in
                        let offset = reorderOffset(for: value.translation.height, stepHeight: stepHeight)
                        if offset != 0 {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                moveBy(offset)
                            }
                        }

                        activeReorderID = nil
                        reorderPreviewID = nil
                    }
            )
            .help(help)
    }

    private func reorderOffset(for distance: CGFloat, stepHeight: CGFloat) -> Int {
        let steps = Int(abs(distance) / stepHeight)
        guard steps > 0 else { return 0 }
        return distance > 0 ? steps : -steps
    }

    private func projectPreviewID(for project: SidebarProject, by offset: Int) -> String? {
        guard let from = model.projects.firstIndex(where: { $0.id == project.id }) else {
            return nil
        }
        let to = max(0, min(model.projects.count - 1, from + offset))
        return "project:\(model.projects[to].id.uuidString)"
    }

    private func workspacePreviewID(for worktree: GitWorktree, in projectID: UUID, by offset: Int) -> String? {
        guard let trees = model.worktrees[projectID],
              let from = trees.firstIndex(where: { $0.path == worktree.path }) else {
            return nil
        }
        let to = max(0, min(trees.count - 1, from + offset))
        return "workspace:\(projectID.uuidString):\(trees[to].path)"
    }

    /// Reorder-preview highlight, drawn as an overlay *above* the card so the
    /// card's opaque fill doesn't hide it. Accent stroke (2pt) + soft fill, with
    /// the same corner radius/style as the card so all three layers register.
    /// `allowsHitTesting(false)` is required — otherwise it swallows the drag
    /// handle gesture and launcher taps.
    private func reorderHighlightOverlay(for id: String) -> some View {
        let active = reorderPreviewID == id
        return RoundedRectangle(cornerRadius: CardMetrics.cardCornerRadius, style: .continuous)
            .fill(AppPalette.indigo.opacity(active ? 0.20 : 0))
            .overlay {
                RoundedRectangle(cornerRadius: CardMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppPalette.indigo.opacity(active ? 0.95 : 0), lineWidth: 2.5)
            }
            .allowsHitTesting(false)
    }
}
