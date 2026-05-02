// 4th column: collapsible file explorer with Files / Diff pill tabs.
// Files tab: full FileTreeView with git-status badges (M/A/D/?) per file.
//   git status is loaded once per rootPath change and passed into the tree.
// Diff  tab: changed files with +/- counts (git diff HEAD --numstat);
//   tapping a row opens the unified diff in the editor panel.
// Related: FileTreeView.swift (Files tab content), DiffListView.swift (Diff tab),
//          DiffEditorView.swift (diff renderer in editor), AppState.swift,
//          ContentView.swift (column layout).

import SwiftUI

// MARK: - Tab

private enum FilePanelTab { case files, diff }

// MARK: - FilePanelView

struct FilePanelView: View {
    @Environment(AppState.self) private var appState
    @State private var activeTab: FilePanelTab = .files
    @State private var treeFocused: Bool = false
    // Path → single-char badge: "M", "A", "D", "R", "?"
    @State private var gitStatus: [URL: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.Color.border).frame(height: 1)

            if let project = appState.selectedProject {
                switch activeTab {
                case .files:
                    FileTreeView(rootPath: project.rootPath,
                                 keyboardFocused: $treeFocused,
                                 gitStatus: gitStatus)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .diff:
                    DiffListView(rootPath: project.rootPath)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyState
            }
        }
        .background(Theme.Color.surface)
        .onChange(of: appState.filePanelFocused) { _, new in
            if new { treeFocused = true }
        }
        .onChange(of: treeFocused) { _, new in
            if !new { appState.filePanelFocused = false }
        }
        // Polls git status every 2 seconds. .task(id:) restarts automatically when the
        // project changes, and cancels when the view disappears — no manual timer cleanup.
        .task(id: appState.selectedProject?.rootPath) {
            guard let path = appState.selectedProject?.rootPath else { return }
            while !Task.isCancelled {
                loadGitStatus(in: path)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Git status

    private func loadGitStatus(in rootPath: String) {
        Task.detached(priority: .utility) {
            let raw    = gitOutput(["status", "--short"], in: rootPath)
            let parsed = Self.parseStatus(raw, rootPath: rootPath)
            await MainActor.run { gitStatus = parsed }
        }
    }

    private static func parseStatus(_ output: String, rootPath: String) -> [URL: String] {
        let root = URL(fileURLWithPath: rootPath)
        var result: [URL: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            guard line.count >= 3 else { continue }
            let xy   = String(line.prefix(2))
            let path = String(line.dropFirst(3))
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " -> ").last ?? ""
            guard !path.isEmpty else { continue }
            let url   = root.appendingPathComponent(path)
            let badge: String
            if xy == "??" {
                badge = "?"
            } else {
                let x = xy.first ?? " "
                let y = xy.dropFirst().first ?? " "
                badge = String(x != " " ? x : y)
            }
            result[url] = badge
        }
        return result
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            pillControl
            Spacer()
            closeButton
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Panel.headerHeight)
    }

    private var pillControl: some View {
        HStack(spacing: 2) {
            pillTab("Files", tab: .files)
            pillTab("Diff",  tab: .diff)
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Theme.Color.background)
                .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: 1))
        )
    }

    @ViewBuilder
    private func pillTab(_ label: String, tab: FilePanelTab) -> some View {
        let active = activeTab == tab
        Button(label) { activeTab = tab }
            .font(.system(size: 12, weight: active ? .medium : .regular))
            .foregroundStyle(active ? Theme.Color.textPrimary : Theme.Color.textSecondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background { if active { Capsule().fill(Theme.Color.surfaceElevated) } }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.1), value: active)
    }

    private var closeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { appState.toggleFilePanel() }
        } label: {
            Image(systemName: "xmark").font(.system(size: 11))
                .opacity(appState.showsCmdShortcuts ? 0 : 1)
        }
        .buttonStyle(IconButtonStyle())
        .overlay { if appState.showsCmdShortcuts { ShortcutBadge(label: "⌘E") } }
        .animation(.easeInOut(duration: 0.12), value: appState.showsCmdShortcuts)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No project open")
                .font(.system(size: Theme.FontSize.sm))
                .foregroundStyle(Theme.Color.textTertiary)
            Spacer()
        }
    }
}
