// 3rd column: text editor panel with multi-file tab bar.
// Tab state (open files, selected file) lives in AppState. Per-file content and dirty flags
// are owned here as @State dictionaries so they survive tab switches without re-loading.
// Supports two tab kinds via URL scheme:
//   - Regular file tabs (file:// scheme)  → FileEditorView (editable, Cmd+S saves)
//   - Diff tabs (agamon-diff:// scheme)   → DiffEditorView (read-only unified diff)
// AppState.openDiff constructs agamon-diff:// URLs; loadFile guards isFileURL to skip them.
// Related: FileEditorView.swift, DiffEditorView.swift (content views),
//          GitStatusView.swift / DiffListView.swift (trigger openFile / openDiff),
//          AppState.swift (openFiles / selectedFile / openDiff).

import SwiftUI

struct EditorPanelView: View {
    @Environment(AppState.self) private var appState

    // Per-file content cache — survives tab switches, loaded lazily on first open.
    @State private var fileContents: [URL: String] = [:]
    // Per-file dirty tracking — keyed by URL so switching tabs preserves unsaved state.
    @State private var dirtyFiles: Set<URL> = []
    @State private var loadErrors: [URL: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Rectangle().fill(Theme.Color.border).frame(height: 1)

            if let url = appState.selectedFile {
                if url.scheme == "agamon-diff" {
                    DiffEditorView(
                        fileURL:  URL(fileURLWithPath: url.path),
                        rootPath: appState.selectedProject?.rootPath ?? ""
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FileEditorView(
                        url:       url,
                        content:   contentBinding(for: url),
                        isDirty:   dirtyBinding(for: url),
                        loadError: loadErrors[url]
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyState
            }
        }
        .background(Theme.Color.surface)
        .onAppear {
            for url in appState.openFiles where fileContents[url] == nil { loadFile(url) }
        }
        .onChange(of: appState.openFiles) { _, newFiles in
            for url in newFiles where fileContents[url] == nil { loadFile(url) }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(appState.openFiles, id: \.self) { url in
                        EditorTabItem(
                            url:      url,
                            isActive: appState.selectedFile == url,
                            isDirty:  dirtyFiles.contains(url),
                            onSelect: { appState.openFile(url) },
                            onClose:  { appState.closeFile(url) }
                        )
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { appState.closeEditor() }
            } label: {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(IconButtonStyle())
            .padding(.horizontal, Theme.Spacing.sm)
        }
        .frame(height: Theme.Panel.headerHeight)
        .background(Theme.Color.surface)
    }

    // MARK: - Helpers

    private func contentBinding(for url: URL) -> Binding<String> {
        Binding(
            get: { fileContents[url] ?? "" },
            set: { fileContents[url] = $0 }
        )
    }

    private func dirtyBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { dirtyFiles.contains(url) },
            set: { isDirty in
                if isDirty { dirtyFiles.insert(url) }
                else       { dirtyFiles.remove(url) }
            }
        )
    }

    private func loadFile(_ url: URL) {
        // agamon-diff:// URLs are virtual — DiffEditorView fetches the diff itself.
        guard url.isFileURL else { return }
        Task.detached(priority: .userInitiated) {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                await MainActor.run { fileContents[url] = content; loadErrors[url] = nil }
            } catch {
                let latin = (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
                await MainActor.run {
                    fileContents[url] = latin
                    loadErrors[url] = latin.isEmpty ? error.localizedDescription : nil
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

// MARK: - EditorTabItem

// Single tab in the editor tab bar.
// Diff tabs (agamon-diff:// scheme) show a ± icon instead of the dirty dot,
// since they are read-only and can't have unsaved changes.
struct EditorTabItem: View {
    let url: URL
    let isActive: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    private var isDiff: Bool { url.scheme == "agamon-diff" }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if isDiff {
                Image(systemName: "plusminus")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
            } else {
                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: 5, height: 5)
                    .opacity(isDirty ? 1 : 0)
            }

            Text(url.lastPathComponent)
                .font(.system(size: Theme.FontSize.xs, design: .monospaced))
                .foregroundStyle(isActive ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                .lineLimit(1)

            // Close button — always in layout so tab width doesn't shift on hover
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.25)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Panel.headerHeight)
        .background(Rectangle().fill(isActive ? Theme.Color.surfaceElevated : Color.clear))
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(isDiff ? Theme.Color.success : Theme.Color.accent).frame(height: 1)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Color.border).frame(width: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onSelect() }
    }
}
