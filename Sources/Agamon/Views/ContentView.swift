// Root layout: [projects] | [terminals] | [editor] | [file explorer].
// Columns 3 and 4 are independently collapsible. The editor (column 3) auto-opens when
// a file is double-clicked in the explorer; the explorer (column 4) is toggled with ⌘E.
// Uses a manual HStack rather than NavigationSplitView for full control over widths and chrome.
// Related: SidebarView.swift, SplitContainerView.swift, EditorPanelView.swift,
//          FilePanelView.swift, AppState.swift (drives visibility and selection).

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    // editorPanelWidth lives in AppState so keyboard resize shortcuts can modify it.
    // editorPanelBaseWidth is drag-local: captures width at gesture start so the delta math works.
    @State private var editorPanelBaseWidth: CGFloat = Theme.EditorPanel.width
    @State private var filePanelWidth: CGFloat = Theme.FilePanel.width
    @State private var filePanelBaseWidth: CGFloat = Theme.FilePanel.width

    var body: some View {
        HStack(spacing: 0) {
            // Column 1: project list
            if appState.sidebarVisible {
                SidebarView()
                    .frame(width: Theme.Sidebar.width)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                divider
            }

            // Column 2: terminal tabs + split panes.
            // NEVER conditionally removed — using if-removal triggers viewDidMoveToWindow on
            // every AgamonTerminalView, resetting lastLayoutSize and firing TIOCSWINSZ for all
            // terminals. opacity(0) keeps NSViews in their hosting view so no re-parenting occurs.
            // The expanded editor is overlaid on top of this column when editorZoomed.
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
            .opacity(appState.editorZoomed ? 0 : 1)
            .allowsHitTesting(!appState.editorZoomed)
            .overlay {
                // Editor zoom: fills Column 2's full frame (which equals total area minus sidebar).
                if appState.editorZoomed && appState.editorPanelVisible {
                    EditorPanelView()
                        .transition(.opacity)
                }
            }

            // Column 3: text editor in its normal fixed-width position (not zoomed).
            if appState.editorPanelVisible && appState.zoomedPaneID == nil && !appState.editorZoomed {
                ResizeDivider {
                    appState.editorPanelWidth = max(Theme.EditorPanel.minWidth, editorPanelBaseWidth - $0)
                } onEnd: {
                    editorPanelBaseWidth = appState.editorPanelWidth
                }
                EditorPanelView()
                    .frame(width: appState.editorPanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Column 4: file explorer — hidden during any zoom.
            if appState.filePanelVisible && appState.zoomedPaneID == nil && !appState.editorZoomed {
                ResizeDivider {
                    filePanelWidth = max(Theme.FilePanel.minWidth, filePanelBaseWidth - $0)
                } onEnd: {
                    filePanelBaseWidth = filePanelWidth
                }
                FilePanelView()
                    .frame(width: filePanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .environment(\.uiFontOffset, appState.uiFontSizeOffset)
        .background(Theme.Color.background)
        .preferredColorScheme(.dark)
        .focusedSceneValue(\.appState, appState)
        .overlay { ShortcutHandler() }
        .overlay {
            if appState.commandCenterVisible {
                CommandCenterView()
                    .environment(appState)
            }
        }
        .animation(.easeOut(duration: 0.12), value: appState.commandCenterVisible)
        .animation(.easeOut(duration: 0.15), value: appState.sidebarVisible)
        .animation(.easeOut(duration: 0.18), value: appState.zoomedPaneID == nil)
        .animation(.easeOut(duration: 0.18), value: appState.editorZoomed)
    }

    // ALL projects' tabs are kept in the hierarchy simultaneously — only the active one is visible.
    // This extends the same-project tab strategy to cover project switches: no re-parenting ever,
    // so TIOCSWINSZ(0,0) is never sent and tmux sessions survive switching between projects.
    @ViewBuilder
    private var terminalArea: some View {
        if appState.selectedProject?.tabs.isEmpty == false {
            ZStack {
                ForEach(appState.projects) { project in
                    ForEach(project.tabs) { tab in
                        let isVisible = project.id == appState.selectedProjectID
                                     && tab.id == appState.selectedTabID
                        SplitContainerView(pane: tab.rootPane, projectRootPath: project.rootPath)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(isVisible ? 1 : 0)
                            .allowsHitTesting(isVisible)
                    }
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

// MARK: - Resize Divider

// 1px visible line with an 8px invisible hit area overlay.
// Layout width stays 1px — the overlay doesn't affect the HStack geometry.
struct ResizeDivider: View {
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void

    var body: some View {
        Rectangle()
            .fill(Theme.Color.border)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.push() }
                        else        { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { onDrag($0.translation.width) }
                            .onEnded   { _ in onEnd() }
                    )
            )
    }
}

// MARK: - Empty States

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.uiFontOffset) private var fontOffset

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("Agamon")
                .font(.system(size: 28 + fontOffset, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)

            Text("A focused terminal for running agents")
                .font(.system(size: Theme.FontSize.md + fontOffset))
                .foregroundStyle(Theme.Color.textSecondary)

            Button("Open Project Folder") {
                appState.openProject()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.background)
    }
}

private func emptyState(_ message: String) -> some View {
    // This is a free function — it can't read @Environment, so it
    // uses the default body text size. Views that call this pass through
    // the offset via the environment automatically.
    Text(message)
        .font(.system(size: Theme.FontSize.md))
        .foregroundStyle(Theme.Color.textTertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.background)
}

