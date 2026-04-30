// Root layout: [projects] | [terminals] | [editor] | [file explorer].
// Columns 3 and 4 are independently collapsible. The editor (column 3) auto-opens when
// a file is double-clicked in the explorer; the explorer (column 4) is toggled with ⌘E.
// Uses a manual HStack rather than NavigationSplitView for full control over widths and chrome.
// Related: SidebarView.swift, SplitContainerView.swift, EditorPanelView.swift,
//          FilePanelView.swift, AppState.swift (drives visibility and selection).

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            // Column 1: project list
            SidebarView()
                .frame(width: Theme.Sidebar.width)

            divider

            // Column 2: terminal tabs + split panes
            VStack(spacing: 0) {
                if let project = appState.selectedProject {
                    TabBarView(project: project)
                    hDivider
                    terminalArea
                } else {
                    WelcomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Column 3: text editor (shown when a file is open)
            if appState.editorPanelVisible {
                divider
                EditorPanelView()
                    .frame(width: Theme.EditorPanel.width)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Column 4: file explorer
            if appState.filePanelVisible {
                divider
                FilePanelView()
                    .frame(width: Theme.FilePanel.width)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Theme.Color.background)
        .preferredColorScheme(.dark)
        .onAppear {
            appState.load()
            appState.startModifierMonitor()
        }
        .focusedSceneValue(\.appState, appState)
        .overlay { ShortcutHandler() }
    }

    // All tabs are kept in the hierarchy simultaneously — only the active one is visible.
    // This prevents AgamonTerminalView from being re-parented on tab switch, which would
    // send TIOCSWINSZ to the pty, trigger SIGWINCH in tmux, and wipe the visible content.
    @ViewBuilder
    private var terminalArea: some View {
        if let project = appState.selectedProject, !project.tabs.isEmpty {
            ZStack {
                ForEach(project.tabs) { tab in
                    SplitContainerView(pane: tab.rootPane)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(tab.id == appState.selectedTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == appState.selectedTabID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emptyState("No tabs open")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Color.border)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private var hDivider: some View {
        Rectangle()
            .fill(Theme.Color.border)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty States

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @State private var showingNewProject = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("Agamon")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)

            Text("A focused terminal for running agents")
                .font(.system(size: Theme.FontSize.md))
                .foregroundStyle(Theme.Color.textSecondary)

            Button("Open Project Folder") {
                showingNewProject = true
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.background)
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet()
        }
    }
}

private func emptyState(_ message: String) -> some View {
    Text(message)
        .font(.system(size: Theme.FontSize.md))
        .foregroundStyle(Theme.Color.textTertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.background)
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var rootPath: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("New Project")
                .font(.system(size: Theme.FontSize.xl, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Name").sectionHeader()
                TextField("My Project", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.FontSize.md))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .padding(Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(Theme.Color.surfaceElevated)
                    )
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Root Directory").sectionHeader()
                HStack {
                    TextField("/path/to/project", text: $rootPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: Theme.FontSize.md, design: .monospaced))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .padding(Theme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .fill(Theme.Color.surfaceElevated)
                        )
                    Button("Browse") { pickFolder() }
                        .buttonStyle(GhostButtonStyle())
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(GhostButtonStyle())
                Button("Create") {
                    let projectName = name.isEmpty ? URL(fileURLWithPath: rootPath).lastPathComponent : name
                    appState.addProject(name: projectName, rootPath: rootPath)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(rootPath.isEmpty)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 420)
        .background(Theme.Color.surface)
        .preferredColorScheme(.dark)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
            if name.isEmpty { name = url.lastPathComponent }
        }
    }
}
