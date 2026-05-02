// 4th column: collapsible file explorer with two tabs — Files and Diff.
// Files tab: flat list of git-touched files (git status --short).
// Diff  tab: changed files with +/- counts (git diff HEAD --numstat);
//            tapping opens the unified diff in the editor panel.
// Related: GitStatusView.swift, DiffListView.swift (tab content),
//          EditorPanelView.swift (shows DiffEditorView when diff tab is opened),
//          AppState.filePanelVisible (toggle), ContentView.swift (column layout).

import SwiftUI

// MARK: - Tab

private enum FilePanelTab { case files, diff }

// MARK: - FilePanelView

struct FilePanelView: View {
    @Environment(AppState.self) private var appState
    @State private var activeTab: FilePanelTab = .files

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.Color.border).frame(height: 1)

            if let project = appState.selectedProject {
                switch activeTab {
                case .files:
                    GitStatusView(rootPath: project.rootPath)
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
            .background {
                if active { Capsule().fill(Theme.Color.surfaceElevated) }
            }
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
