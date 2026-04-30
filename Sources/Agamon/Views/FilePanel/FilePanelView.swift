// Container for the right-side file panel: header + file tree + inline editor.
// When a file is selected, the tree collapses to 200px and the editor fills the rest.
// File loading uses task(id:) rather than onChange — task is guaranteed to run on every
// id change even when the view tree is being rebuilt, where onChange can be skipped.
// Related: FileTreeView.swift (tree), FileEditorView.swift (editor),
//          AppState.filePanelVisible (toggle), ContentView.swift (hosts this).

import SwiftUI

struct FilePanelView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFile: URL?
    @State private var fileContent: String = ""
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            divider

            if let project = appState.selectedProject {
                if let url = selectedFile {
                    FileTreeView(rootPath: project.rootPath, selectedFile: $selectedFile)
                        .frame(maxHeight: 200)
                    divider
                    FileEditorView(url: url, content: $fileContent, loadError: loadError)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FileTreeView(rootPath: project.rootPath, selectedFile: $selectedFile)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyState
            }
        }
        .background(Theme.Color.surface)
        // task(id:) is more reliable than onChange when the view tree is rebuilding simultaneously.
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
                // Try latin-1 fallback for files with non-UTF8 encoding
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
                    appState.filePanelVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
            }
            .buttonStyle(IconButtonStyle())
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
