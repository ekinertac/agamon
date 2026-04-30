// 4th column: collapsible file explorer for the active project.
// Shows only the file tree — file content is displayed in EditorPanelView (column 3).
// ⌘E (via AppState.focusFilePanel) focuses the tree for keyboard navigation.
// Escape inside the tree releases focus back to the terminal via refocusActiveTerminal.
// Related: FileTreeView.swift (tree), EditorPanelView.swift (editor, column 3),
//          AppState.filePanelFocused (set by ShortcutHandler ⌘E), ContentView.swift.

import SwiftUI

struct FilePanelView: View {
    @Environment(AppState.self) private var appState
    @State private var treeFocused: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            divider

            if let project = appState.selectedProject {
                FileTreeView(rootPath: project.rootPath, keyboardFocused: $treeFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .background(Theme.Color.surface)
        .overlay {
            if treeFocused {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Theme.Color.accent.opacity(0.4), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: appState.filePanelFocused) { _, new in
            if new { treeFocused = true }
        }
        .onChange(of: treeFocused) { _, new in
            if !new {
                appState.filePanelFocused = false
                // Defer one run loop so AppKit can settle the new first responder.
                // If the editor just grabbed focus (e.g. file double-click), skip the
                // terminal refocus — overriding it here is the source of the focus race.
                DispatchQueue.main.async {
                    if !(NSApp.keyWindow?.firstResponder is AgamonEditorTextView) {
                        appState.refocusActiveTerminal()
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Files").sectionHeader()
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    appState.toggleFilePanel()
                }
            } label: {
                Image(systemName: "xmark").font(.system(size: 11))
                    .opacity(appState.showsCmdShortcuts ? 0 : 1)
            }
            .buttonStyle(IconButtonStyle())
            .overlay { if appState.showsCmdShortcuts { ShortcutBadge(label: "⌘E") } }
            .animation(.easeInOut(duration: 0.12), value: appState.showsCmdShortcuts)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Panel.headerHeight)
    }

    private var divider: some View {
        Rectangle().fill(Theme.Color.border).frame(height: 1)
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
