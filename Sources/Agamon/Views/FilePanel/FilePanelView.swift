// Container for the right-side file panel: header + file tree + inline editor.
// When a file is selected, the tree collapses to 200px and the editor fills the rest.
//
// ⌘E (via AppState.focusFilePanel) sets filePanelFocused = true, which this view
// syncs into a local @State that's passed as a binding to FileTreeView. FileTreeView
// then requests @FocusState focus and enables ↑/↓/Enter/Escape keyboard navigation.
//
// File loading uses task(id:) rather than onChange — task is guaranteed to run on every
// id change even when the view tree is being rebuilt, where onChange can be skipped.
// Related: FileTreeView.swift (tree), FileEditorView.swift (editor),
//          AppState.filePanelFocused (set by ShortcutHandler ⌘E), ContentView.swift.

import SwiftUI

struct FilePanelView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFile: URL?
    @State private var fileContent: String = ""
    @State private var loadError: String?
    @State private var treeFocused: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            divider

            if let project = appState.selectedProject {
                if let url = selectedFile {
                    FileTreeView(rootPath: project.rootPath, selectedFile: $selectedFile,
                                 keyboardFocused: .constant(false))
                        .frame(maxHeight: 200)
                    divider
                    FileEditorView(url: url, content: $fileContent, loadError: loadError)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FileTreeView(rootPath: project.rootPath, selectedFile: $selectedFile,
                                 keyboardFocused: $treeFocused)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyState
            }
        }
        .background(Theme.Color.surface)
        .overlay {
            // Focus ring when keyboard-navigating the tree
            if treeFocused {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Theme.Color.accent.opacity(0.4), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        // Drive treeFocused from AppState (set by ⌘E in ShortcutHandler)
        .onChange(of: appState.filePanelFocused) { _, new in
            if new { treeFocused = true }
        }
        // Sync focus release back to AppState and restore terminal first-responder
        .onChange(of: treeFocused) { _, new in
            if !new {
                appState.filePanelFocused = false
                appState.refocusActiveTerminal()
            }
        }
        .task(id: selectedFile) {
            guard let url = selectedFile else {
                fileContent = ""
                loadError = nil
                return
            }
            do {
                fileContent = try String(contentsOf: url, encoding: .utf8)
                loadError = nil
            } catch {
                fileContent = (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
                loadError = fileContent.isEmpty ? error.localizedDescription : nil
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Files").sectionHeader()
            Spacer()

            if selectedFile != nil {
                Button {
                    selectedFile = nil
                    fileContent = ""
                    loadError = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                }
                .buttonStyle(IconButtonStyle())
                .help("Back to tree")
            }

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
        .padding(.vertical, Theme.Spacing.sm)
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
