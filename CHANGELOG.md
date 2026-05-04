# Changelog

All notable changes to Agamon are documented here.
Versions follow [Semantic Versioning](https://semver.org/). Changes since the last tag are listed under **Unreleased**.

---

## [Unreleased]

### Added
- Shortcuts tab in Settings — read-only reference for every registered key binding, grouped by context, with individual keyboard-key cap badges
- Panel toggle buttons in the tab bar (sidebar, editor panel, file panel) — mirrors the Xcode toolbar layout
- Sidebar toggle button at the left end of the tab bar
- Three-tier font size system: terminal (⌘+/−), text editor (⌘+/− when editor focused), and UI offset (⌘⇧+/−) — all configurable in Settings → Text
- Auto-close pane/tab when the shell process exits (Ctrl+D)
- Project rename in the sidebar context menu
- Multi-window support (⌘N)

### Fixed
- ⌘1–9 tab switching now works when a terminal pane has keyboard focus (AppKit NSView was consuming the events before SwiftUI's shortcut handler)
- Settings gear button now opens the macOS Settings window
- Editor line-number ruler no longer overflows into the tab bar
- ⌘E and ⌘O shortcut badges are no longer clipped — moved out of cramped button overlays into the HStack spacer area
- Terminal sessions survive project and tab switches (no TIOCSWINSZ(0,0) reset)
- Keyboard focus and last-pane position are restored when switching tabs or projects

---

## [v0.3] — Editor improvements, file tree CRUD, per-project state

### Added
- File tree: create, rename, and delete files and folders from the context menu
- Per-project file panel state (expanded folders, scroll position) persists across sessions
- HTML preview tab in the editor panel
- Editor tab navigation: ⌘⇧[ / ⌘⇧] cycle through open editor tabs; ⌘1–9 jumps directly (context-aware — switches terminal tabs when terminal is focused)
- Keyboard focus restored correctly after switching projects or tabs

### Fixed
- Terminal state no longer resets when switching between projects
- Diff view works when the project root is a subdirectory of a git repo
- Editor theme uses raw palette colors so syntax tokens match the active terminal theme
- Real-time git status badges in the file tree

---

## [v0.2] — Syntax highlighting, command center, find, pane zoom

### Added
- Syntax highlighting in the file editor — theme-driven, 10 distinct token colors
- Command center (⌘P) — fuzzy search over files in the current project
- Find bar: ⌘F in the terminal opens an overlay search; ⌘F in the editor opens the native find bar
- Pane zoom: ⌘⇧↩ expands the focused pane to fill the container; press again to restore the split
- Files / Diff pill tabs in the file panel: git-status badges on the file tree, a changed-files list, and a unified diff viewer
- Typora-style markdown rendering in the editor
- Line-wrap toggle for the editor
- Shift+Tab dedents in the editor
- Resizable file panel
- Context-aware ⌘1/⌘2 switches file explorer tabs (Files vs Diff) when the file panel is focused
- Codesign + notarization wired into the GitHub Actions release workflow
- MIT license, contributing guide, and issue templates

### Fixed
- Resize jitter resolved by using global coordinate space for drag gestures
- ⌘W closes diff tabs correctly

---

## [v0.1] — Initial release

- Terminal multiplexer: unlimited projects, tabs per project, and split panes (horizontal and vertical)
- Spatial pane navigation: ⌘⌥↑↓←→ moves focus between panes; ⌘⌃⌥↑↓←→ resizes
- File panel with a file tree browser and a text editor
- Settings: pane dimming, terminal font family/size/weight, shell path
- Keyboard shortcut hints: hold ⌘ to reveal ⌘1–9 on tabs; hold ⌃ to reveal ⌃1–9 on projects
- Accent color follows the macOS System Settings accent color
- Dark-only UI with a design token system (Theme.swift)
