import Foundation
import SwiftUI

/// Observable model backing the menu bar panel. Single shared instance so the
/// project/worktree list and settings stay consistent everywhere.
///
/// Persistence keys are intentionally kept compatible with the Ghostty++
/// sidebar (`sidebar.*.v1`) so an existing setup migrates with no extra work.
@MainActor
final class WorktreeViewModel: ObservableObject {
    static let shared = WorktreeViewModel()

    @Published var projects: [SidebarProject] = []
    @Published private(set) var worktrees: [UUID: [GitWorktree]] = [:]
    @Published private(set) var workspaceNames: [String: String] = [:]
    @Published private(set) var workspaceOrder: [UUID: [String]] = [:]
    @Published private(set) var managedWorktreePaths: [UUID: Set<String>] = [:]
    @Published var expanded: Set<UUID> = []
    @Published private(set) var loading: Set<UUID> = []
    /// Projects whose root directory is not a git repository. Tracked so the UI
    /// can offer a `git init` action instead of surfacing an error.
    @Published private(set) var notGitRepo: Set<UUID> = []
    @Published var lastError: String?

    /// Terminal launch configuration (which app + command template).
    @Published var terminalConfig: TerminalConfig = .default {
        didSet { saveTerminalConfig() }
    }
    /// Quick-launch buttons (Terminal / codex / claude, user-editable).
    @Published var launchers: [AgentLauncher] = AgentLauncher.defaults {
        didSet { saveLaunchers() }
    }

    private let projectsDefaultsKey = "sidebar.projects.v1"
    private let workspaceNamesDefaultsKey = "sidebar.workspaceNames.v1"
    private let workspaceOrderDefaultsKey = "worktreebar.workspaceOrder.v1"
    private let managedWorktreePathsDefaultsKey = "sidebar.managedWorktreePaths.v1"
    private let terminalConfigDefaultsKey = "worktreebar.terminalConfig.v1"
    private let launchersDefaultsKey = "worktreebar.launchers.v1"

    init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: projectsDefaultsKey),
           let decoded = try? JSONDecoder().decode([SidebarProject].self, from: data) {
            projects = decoded
        }
        loadWorkspaceNames()
        loadWorkspaceOrder()
        loadManagedWorktreePaths()
        loadTerminalConfig()
        loadLaunchers()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: projectsDefaultsKey)
        }
    }

    private func loadWorkspaceNames() {
        guard let data = UserDefaults.standard.data(forKey: workspaceNamesDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            workspaceNames = [:]
            return
        }
        workspaceNames = decoded
    }

    private func saveWorkspaceNames() {
        if let data = try? JSONEncoder().encode(workspaceNames) {
            UserDefaults.standard.set(data, forKey: workspaceNamesDefaultsKey)
        }
    }

    private func loadWorkspaceOrder() {
        guard let data = UserDefaults.standard.data(forKey: workspaceOrderDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            workspaceOrder = [:]
            return
        }

        workspaceOrder = Dictionary(
            uniqueKeysWithValues: decoded.compactMap { key, paths in
                guard let id = UUID(uuidString: key) else { return nil }
                return (id, paths.map(normalizedPath))
            }
        )
    }

    private func saveWorkspaceOrder() {
        let encoded = Dictionary(
            uniqueKeysWithValues: workspaceOrder.map { id, paths in
                (id.uuidString, paths.map(normalizedPath))
            }
        )

        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: workspaceOrderDefaultsKey)
        }
    }

    private func loadManagedWorktreePaths() {
        guard let data = UserDefaults.standard.data(forKey: managedWorktreePathsDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            managedWorktreePaths = [:]
            return
        }

        managedWorktreePaths = Dictionary(
            uniqueKeysWithValues: decoded.compactMap { key, paths in
                guard let id = UUID(uuidString: key) else { return nil }
                return (id, Set(paths.map(normalizedPath)))
            }
        )
    }

    private func saveManagedWorktreePaths() {
        let encoded = Dictionary(
            uniqueKeysWithValues: managedWorktreePaths.map { id, paths in
                (id.uuidString, Array(paths).sorted())
            }
        )

        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: managedWorktreePathsDefaultsKey)
        }
    }

    private func loadTerminalConfig() {
        guard let data = UserDefaults.standard.data(forKey: terminalConfigDefaultsKey),
              let decoded = try? JSONDecoder().decode(TerminalConfig.self, from: data) else {
            terminalConfig = .default
            return
        }
        terminalConfig = decoded
    }

    private func saveTerminalConfig() {
        if let data = try? JSONEncoder().encode(terminalConfig) {
            UserDefaults.standard.set(data, forKey: terminalConfigDefaultsKey)
        }
    }

    private func loadLaunchers() {
        guard let data = UserDefaults.standard.data(forKey: launchersDefaultsKey),
              let decoded = try? JSONDecoder().decode([AgentLauncher].self, from: data),
              !decoded.isEmpty else {
            launchers = AgentLauncher.defaults
            return
        }
        launchers = decoded
    }

    private func saveLaunchers() {
        if let data = try? JSONEncoder().encode(launchers) {
            UserDefaults.standard.set(data, forKey: launchersDefaultsKey)
        }
    }

    // MARK: - Project mutations

    func addProject(name: String, rootPath: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let path = rootPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !path.isEmpty else { return }
        let project = SidebarProject(name: trimmed, rootPath: path)
        projects.append(project)
        save()
        expanded.insert(project.id)
        refresh(project)
    }

    func removeProject(_ project: SidebarProject) {
        projects.removeAll { $0.id == project.id }
        worktrees.removeValue(forKey: project.id)
        workspaceOrder.removeValue(forKey: project.id)
        managedWorktreePaths.removeValue(forKey: project.id)
        expanded.remove(project.id)
        notGitRepo.remove(project.id)
        save()
        saveWorkspaceOrder()
        saveManagedWorktreePaths()
    }

    func updateProject(_ project: SidebarProject) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        save()
    }

    func moveProject(_ movingID: UUID, before targetID: UUID) {
        guard let from = projects.firstIndex(where: { $0.id == movingID }),
              let to = projects.firstIndex(where: { $0.id == targetID }),
              from != to else {
            return
        }

        let project = projects.remove(at: from)
        let adjustedTo = projects.firstIndex(where: { $0.id == targetID }) ?? to
        projects.insert(project, at: adjustedTo)
        save()
    }

    func moveProject(_ project: SidebarProject, by offset: Int) {
        guard let from = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let to = max(0, min(projects.count - 1, from + offset))
        guard from != to else { return }

        let item = projects.remove(at: from)
        projects.insert(item, at: to)
        save()
    }

    // MARK: - Worktree refresh

    func toggleExpanded(_ project: SidebarProject) {
        if expanded.contains(project.id) {
            expanded.remove(project.id)
        } else {
            expanded.insert(project.id)
            if worktrees[project.id] == nil {
                refresh(project)
            }
        }
    }

    func refresh(_ project: SidebarProject) {
        let id = project.id
        let root = project.rootPath
        loading.insert(id)
        Task.detached { [weak self] in
            // Distinguish "not a git repo" (an expected state we offer to fix)
            // from genuine git failures.
            guard WorktreeService.isGitRepo(in: root) else {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.loading.remove(id)
                    self.notGitRepo.insert(id)
                    self.worktrees[id] = []
                }
                return
            }

            let result: Result<[GitWorktree], Error>
            do {
                let list = try WorktreeService.list(in: root)
                result = .success(list)
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.loading.remove(id)
                self.notGitRepo.remove(id)
                switch result {
                case let .success(list):
                    self.worktrees[id] = self.visibleWorktrees(from: list, for: id)
                    self.lastError = nil
                case let .failure(err):
                    self.lastError = err.localizedDescription
                }
            }
        }
    }

    /// `git init` a project's root, then refresh so its `current` workspace
    /// shows up.
    func initGit(_ project: SidebarProject) {
        let root = project.rootPath
        loading.insert(project.id)
        Task.detached { [weak self] in
            let result: Result<Void, Error>
            do {
                try WorktreeService.initRepo(in: root)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .success:
                    self.lastError = nil
                    self.refresh(project)
                case let .failure(err):
                    self.loading.remove(project.id)
                    self.lastError = err.localizedDescription
                }
            }
        }
    }

    func refreshAllExpanded() {
        for p in projects where expanded.contains(p.id) {
            refresh(p)
        }
    }

    // MARK: - Worktree display names

    func displayName(for worktree: GitWorktree) -> String {
        let key = normalizedPath(worktree.path)
        if let name = workspaceNames[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return worktree.displayLabel
    }

    func secondaryLabel(for worktree: GitWorktree) -> String {
        let display = displayName(for: worktree)
        if display == worktree.displayLabel {
            return worktree.path
        }
        return "\(worktree.displayLabel) — \(worktree.path)"
    }

    func isCurrentWorkspace(_ worktree: GitWorktree, in project: SidebarProject) -> Bool {
        normalizedPath(worktree.path) == normalizedPath(project.rootPath)
    }

    func renameWorkspace(for worktree: GitWorktree, to name: String) {
        let key = normalizedPath(worktree.path)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            workspaceNames.removeValue(forKey: key)
        } else {
            workspaceNames[key] = trimmed
        }

        saveWorkspaceNames()
    }

    // MARK: - Worktree mutations

    func createWorktree(
        in project: SidebarProject,
        path: String,
        ref: String,
        createBranch: Bool,
        newBranchName: String?,
        workspaceName: String?
    ) async -> Result<Void, Error> {
        do {
            try WorktreeService.add(
                in: project.rootPath,
                path: path,
                ref: ref,
                createBranch: createBranch,
                newBranchName: newBranchName
            )
            let trimmedWorkspace = workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await MainActor.run {
                self.markManagedWorktree(path: path, projectID: project.id)
                if !trimmedWorkspace.isEmpty {
                    self.workspaceNames[self.normalizedPath(path)] = trimmedWorkspace
                    self.saveWorkspaceNames()
                }
                self.refresh(project)
            }
            return .success(())
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
            return .failure(error)
        }
    }

    func deleteWorkspace(
        _ worktree: GitWorktree,
        in project: SidebarProject,
        deleteLocalBranch: Bool
    ) async -> Result<Void, Error> {
        do {
            try WorktreeService.remove(
                in: project.rootPath,
                path: worktree.path,
                branch: worktree.branch,
                deleteLocalBranch: deleteLocalBranch
            )

            await MainActor.run {
                self.unmarkManagedWorktree(path: worktree.path, projectID: project.id)
                self.workspaceNames.removeValue(forKey: self.normalizedPath(worktree.path))
                self.saveWorkspaceNames()
                self.refresh(project)
            }
            return .success(())
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
            return .failure(error)
        }
    }

    // MARK: - Launching

    var supportsTerminalSplits: Bool {
        terminalConfig.presetID == "ghostty"
    }

    func open(
        _ worktree: GitWorktree,
        in project: SidebarProject,
        launcher: AgentLauncher,
        mode: TerminalLauncher.LaunchMode = .selectExisting
    ) {
        let workspaceName = displayName(for: worktree)
        let commandTitle = launcher.command.isEmpty ? "" : launcher.title
        let context = TerminalLauncher.LaunchContext(
            projectID: project.id,
            projectName: project.name,
            workspacePath: worktree.path,
            workspaceName: workspaceName,
            commandTitle: commandTitle,
            command: launcher.command,
            mode: mode
        )

        do {
            try TerminalLauncher.launch(
                config: terminalConfig,
                context: context
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Open a plain terminal (no command) in the worktree. Used for the
    /// double-click shortcut. Prefers the user's command-less launcher so its
    /// tab title/grouping stays consistent, falling back to a built-in one if
    /// the user removed it.
    func openTerminal(_ worktree: GitWorktree, in project: SidebarProject) {
        let terminal = launchers.first { $0.command.isEmpty }
            ?? AgentLauncher(title: "Terminal", systemImage: "terminal", command: "")
        open(worktree, in: project, launcher: terminal)
    }

    func open(_ worktree: GitWorktree, command: String) {
        do {
            try TerminalLauncher.launch(
                config: terminalConfig,
                path: worktree.path,
                command: command
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func normalizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    /// Show every real worktree for the project, including the repo's primary
    /// one. Bare entries are skipped since they have no working directory to
    /// open a terminal in. Order is preserved from `git worktree list`, whose
    /// first entry is always the primary worktree.
    private func visibleWorktrees(from list: [GitWorktree], for projectID: UUID) -> [GitWorktree] {
        let visible = list.filter { !$0.isBare }
        let originalIndex = Dictionary(
            uniqueKeysWithValues: visible.enumerated().map { idx, worktree in
                (normalizedPath(worktree.path), idx)
            }
        )
        let orderIndex = Dictionary(
            uniqueKeysWithValues: workspaceOrder[projectID, default: []].enumerated().map { idx, path in
                (normalizedPath(path), idx)
            }
        )

        return visible.sorted { lhs, rhs in
            let leftPath = normalizedPath(lhs.path)
            let rightPath = normalizedPath(rhs.path)
            let leftRank = orderIndex[leftPath] ?? Int.max
            let rightRank = orderIndex[rightPath] ?? Int.max
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return (originalIndex[leftPath] ?? 0) < (originalIndex[rightPath] ?? 0)
        }
    }

    func moveWorkspace(_ movingPath: String, before targetPath: String, in projectID: UUID) {
        guard var current = worktrees[projectID],
              let from = current.firstIndex(where: { normalizedPath($0.path) == normalizedPath(movingPath) }),
              let to = current.firstIndex(where: { normalizedPath($0.path) == normalizedPath(targetPath) }),
              from != to else {
            return
        }

        let moving = current.remove(at: from)
        let adjustedTo = current.firstIndex(where: { normalizedPath($0.path) == normalizedPath(targetPath) }) ?? to
        current.insert(moving, at: adjustedTo)
        worktrees[projectID] = current
        workspaceOrder[projectID] = current.map { normalizedPath($0.path) }
        saveWorkspaceOrder()
    }

    func moveWorkspace(_ worktree: GitWorktree, in projectID: UUID, by offset: Int) {
        guard var current = worktrees[projectID],
              let from = current.firstIndex(where: { normalizedPath($0.path) == normalizedPath(worktree.path) }) else {
            return
        }

        let to = max(0, min(current.count - 1, from + offset))
        guard from != to else { return }

        let item = current.remove(at: from)
        current.insert(item, at: to)
        worktrees[projectID] = current
        workspaceOrder[projectID] = current.map { normalizedPath($0.path) }
        saveWorkspaceOrder()
    }

    private func markManagedWorktree(path: String, projectID: UUID) {
        var paths = managedWorktreePaths[projectID, default: []]
        paths.insert(normalizedPath(path))
        managedWorktreePaths[projectID] = paths
        saveManagedWorktreePaths()
    }

    private func unmarkManagedWorktree(path: String, projectID: UUID) {
        var paths = managedWorktreePaths[projectID, default: []]
        paths.remove(normalizedPath(path))
        if paths.isEmpty {
            managedWorktreePaths.removeValue(forKey: projectID)
        } else {
            managedWorktreePaths[projectID] = paths
        }
        saveManagedWorktreePaths()
    }
}
