// 3rd column: text editor panel with multi-file tab bar.
// Tab state (open files, selected file) lives in AppState. Per-file content and dirty flags
// are owned here as @State dictionaries so they survive tab switches without re-loading.
// Two tab kinds via URL scheme:
//   file://       → FileEditorView  (editable, Cmd+S saves)
//   agamon-diff:// → DiffEditorView (read-only unified diff)
// loadFile guards url.isFileURL so virtual diff URLs are never read as files.
// Related: FileEditorView.swift, DiffEditorView.swift (content views),
//          DiffListView.swift (triggers openDiff), AppState.swift (openFiles / openDiff).

import AppKit
import SwiftUI

struct EditorPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.uiFontOffset) private var fontOffset

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
                    .clipped()
                } else {
                    FileEditorView(
                        url: url,
                        content: contentBinding(for: url),
                        isDirty: dirtyBinding(for: url),
                        loadError: loadErrors[url]
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
            } else {
                emptyState
            }
        }
        .background(Theme.Color.surface)
        .overlay {
            // Dim the editor when focus is elsewhere, matching terminal pane dimming.
            if !appState.editorFocused && appState.dimInactivePanes && appState.inactivePaneDimAmount > 0 {
                Color.black.opacity(appState.inactivePaneDimAmount * 0.6)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            for url in appState.openFiles where fileContents[url] == nil { loadFile(url) }
        }
        .onChange(of: appState.openFiles) { _, newFiles in
            for url in newFiles where fileContents[url] == nil { loadFile(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agamonRequestCloseFile)) { note in
            guard let url = note.object as? URL else { return }
            handleClose(url: url)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(appState.openFiles, id: \.self) { url in
                        EditorTabItem(
                            url: url,
                            isActive: appState.selectedFile == url,
                            isDirty: dirtyFiles.contains(url),
                            onSelect: { appState.openFile(url) },
                            onClose: { handleClose(url: url) }
                        )
                    }
                }
            }
            Spacer(minLength: 0)
            // Close panel button — sits at far right outside the scroll area
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

    // Close a tab, showing a save dialog first when the file has unsaved changes.
    // Enter = Save, Cmd+D = Discard, Escape = Cancel (standard macOS destructive-action pattern).
    private func handleClose(url: URL) {
        guard dirtyFiles.contains(url) else { appState.closeFile(url); return }

        let alert = NSAlert()
        alert.messageText = "Save \"\(url.lastPathComponent)\"?"
        alert.informativeText = "Your changes will be lost if you don't save."
        alert.addButton(withTitle: "Save")        // .alertFirstButtonReturn — Enter
        alert.addButton(withTitle: "Don't Save")  // .alertSecondButtonReturn — Cmd+D
        alert.addButton(withTitle: "Cancel")      // .alertThirdButtonReturn  — Escape
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command

        switch alert.runModal() {
        case .alertFirstButtonReturn:   // Save
            if let content = fileContents[url] {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
            dirtyFiles.remove(url)
            appState.closeFile(url)
        case .alertSecondButtonReturn:  // Don't Save
            dirtyFiles.remove(url)
            appState.closeFile(url)
        default:                        // Cancel — do nothing
            break
        }
    }

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
        guard url.isFileURL else { return }   // skip agamon-diff:// virtual URLs
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
                .font(.system(size: Theme.FontSize.sm + fontOffset))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("Double-click a file in the explorer")
                .font(.system(size: Theme.FontSize.xs + fontOffset))
                .foregroundStyle(Theme.Color.textTertiary.opacity(0.5))
            Spacer()
        }
    }
}

// MARK: - EditorTabItem

// Single tab in the editor tab bar.
// Dirty state shows an accent dot on the left. Close button is always present but
// dims when not hovering so it doesn't compete with the filename visually.
struct EditorTabItem: View {
    let url: URL
    let isActive: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @Environment(\.uiFontOffset) private var fontOffset
    @State private var hovering = false
    private var isDiff: Bool { url.scheme == "agamon-diff" }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if isDiff {
                Image(systemName: "plusminus")
                    .font(.system(size: 8 + fontOffset, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
            } else {
                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: 5, height: 5)
                    .opacity(isDirty ? 1 : 0)
            }

            Text(url.lastPathComponent)
                .font(.system(size: Theme.FontSize.xs + fontOffset, design: .monospaced))
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
        .background(
            Rectangle()
                .fill(isActive ? Theme.Color.surfaceElevated : Color.clear)
        )
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Theme.Color.accent)
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .trailing) {
            // Right border separator between tabs
            Rectangle()
                .fill(Theme.Color.border)
                .frame(width: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onSelect() }
    }
}
