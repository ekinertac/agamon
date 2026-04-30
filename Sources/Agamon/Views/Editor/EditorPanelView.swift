// 3rd column: standalone text editor panel.
// Reads appState.selectedFile (set by FileTreeView double-click) and loads content here.
// The editor panel is independent of the file explorer — closing one doesn't affect the other.
// File content is loaded via task(id:) so switching files always triggers a fresh load.
// Related: FileTreeView.swift (sets selectedFile via appState.openFile),
//          FileEditorView.swift (renders the NSTextView editor body),
//          AppState.swift (selectedFile, editorPanelVisible, openFile, closeEditor),
//          ContentView.swift (positions this as column 3).

import SwiftUI

struct EditorPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var fileContent: String = ""
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.Color.border).frame(height: 1)

            if let url = appState.selectedFile {
                FileEditorView(url: url, content: $fileContent, loadError: loadError)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .background(Theme.Color.surface)
        .onAppear { loadFile(appState.selectedFile) }
        .onChange(of: appState.selectedFile) { _, url in loadFile(url) }
    }

    private var header: some View {
        HStack {
            Text("Editor").sectionHeader()
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    appState.closeEditor()
                }
            } label: {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(IconButtonStyle())
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Panel.headerHeight)
    }

    private func loadFile(_ url: URL?) {
        guard let url else { fileContent = ""; loadError = nil; return }
        // Read on a background thread so large files don't stall the main actor.
        Task.detached(priority: .userInitiated) {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                await MainActor.run { fileContent = content; loadError = nil }
            } catch {
                let latin = (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
                await MainActor.run {
                    fileContent = latin
                    loadError = latin.isEmpty ? error.localizedDescription : nil
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Spacer()
            Text("No file open")
                .font(.system(size: Theme.FontSize.sm))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("Double-click a file in the explorer")
                .font(.system(size: Theme.FontSize.xs))
                .foregroundStyle(Theme.Color.textTertiary.opacity(0.5))
            Spacer()
        }
    }
}
