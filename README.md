# Worktree Bar

A macOS menu-bar app for managing **git worktrees**. Add your repos, expand a
project to see its worktrees, and open any worktree in your terminal — or run an
agent (codex / claude) in it — with one click. The kind of sidebar that an
in-terminal tool gets for free, packaged as a standalone menu-bar accessory.

> Personal, unsigned tool. Ad-hoc signed, sandbox off (it shells out to
> `git` and `open`). macOS 13+.

## Features

- **Projects → worktrees** — add a git repo, expand it to list every worktree
  from `git worktree list`. The repo's primary worktree is marked **CURRENT**.
- **One-click launch** — per-worktree buttons open a terminal (or run a
  configured agent command). Ghostty supports new tab / split right / split down
  via the context menu.
- **Double-click a worktree card** to open a plain terminal there.
- **Create / delete worktrees** — `git worktree add` (with a new branch and a
  sane default path of `<repo>/.worktree/<branch>`) and `git worktree remove`,
  with an opt-in `git branch -D`.
- **Rename, reorder (drag), reveal in Finder, copy path.**
- **Not-a-repo handling** — offers `git init` instead of erroring.
- **Configurable terminal** — Ghostty / Terminal.app / iTerm2 presets, or a
  custom launch-command template. Quick-launch buttons are user-editable.

## Install

Grab the latest `.dmg` from
[Releases](https://github.com/evilstar9527/worktree-bar/releases), open it, and
drag **Worktree Bar** to Applications.

Because the build is **ad-hoc signed** (no Apple Developer ID), Gatekeeper will
block it on first launch. Either:

- Right-click the app → **Open** → confirm, or
- `xattr -dr com.apple.quarantine /Applications/WorktreeBar.app`

The app lives in the menu bar (no Dock icon). Click the tree icon to open the
panel.

## Build from source

Requires [XcodeGen](https://github.com/yonsm/XcodeGen) and Xcode 16+.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project WorktreeBar.xcodeproj -scheme WorktreeBar -configuration Debug build
```

`project.yml` is the source of truth for the Xcode project; run
`xcodegen generate` after editing it. New source files under `WorktreeBar/` are
picked up automatically on regenerate.

## Project layout

```
WorktreeBar/
  WorktreeBarApp.swift        # @main, MenuBarExtra + windows
  Models/                     # SidebarProject, GitWorktree, TerminalConfig, AgentLauncher
  Services/
    WorktreeService.swift     # git CLI wrapper (list/add/remove/init/refs)
    TerminalLauncher.swift    # open worktrees in Ghostty / Terminal / custom
  ViewModels/
    WorktreeViewModel.swift   # single source of state, persisted to UserDefaults
  Views/                      # MenuContentView, New/Delete/Settings, CardStyle (palette)
```

## Releasing

Releases are automated. Pushing to the **`release`** branch runs
[`.github/workflows/release-branch.yml`](.github/workflows/release-branch.yml),
which:

1. reads the version from the [`VERSION`](VERSION) file (must be `X.Y.Z`),
2. stamps it into the build, compiles a Release `.app`,
3. ad-hoc signs it and packages a DMG,
4. publishes a GitHub Release tagged `vX.Y.Z` with the DMG attached.

To cut a release: bump `VERSION`, merge to `main`, then fast-forward/push
`release`. A re-push without bumping `VERSION` fails fast (the tag already
exists).
