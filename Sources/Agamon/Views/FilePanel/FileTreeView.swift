// Hierarchical file browser for the active project's root directory.
// Single-click highlights; double-click calls appState.openFile() which sets selectedFile
// and makes the editor panel (column 3) visible.
// Keyboard navigation: ↑/↓ moves through root items, Enter opens, Escape releases focus.
// Hidden files and build artifacts (node_modules, .build, .git, DerivedData) are skipped.
// Related: FilePanelView.swift (hosts this, owns keyboardFocused state),
//          EditorPanelView.swift (displays the file opened here),
//          AppState.swift (selectedFile, openFile).

import SwiftUI

struct FileTreeView: View {
    let rootPath: String
    @Binding var keyboardFocused: Bool

    @Environment(AppState.self) private var appState
    @State private var rootItems: [FileItem] = []
    @State private var keyboardIndex: Int = 0
    @State private var highlightedFile: URL?
    @FocusState private var internalFocus: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(rootItems.enumerated()), id: \.element.id) { idx, item in
                    FileTreeRow(
                        item: item,
                        highlightedFile: $highlightedFile,
                        isKeyboardSelected: internalFocus && idx == keyboardIndex
                    )
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .focusable()
        .focused($internalFocus)
        .onKeyPress(.upArrow) {
            keyboardIndex = max(0, keyboardIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            keyboardIndex = min(rootItems.count - 1, keyboardIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !rootItems.isEmpty else { return .ignored }
            let item = rootItems[keyboardIndex]
            if !item.isDirectory {
                appState.openFile(item.url)
                DispatchQueue.main.async { appState.focusEditor() }
            }
            return .handled
        }
        .onKeyPress(.escape) {
            internalFocus = false
            appState.refocusActiveTerminal()
            return .handled
        }
        .onChange(of: keyboardFocused) { _, new in
            if new { internalFocus = true; keyboardIndex = 0 }
        }
        .onChange(of: internalFocus) { _, new in
            if !new { keyboardFocused = false }
        }
        .onAppear { reload() }
        .onChange(of: rootPath) { reload() }
    }

    private func reload() {
        rootItems = FileItem.children(of: URL(fileURLWithPath: rootPath), depth: 0)
        keyboardIndex = 0
    }
}

// MARK: - Row

struct FileTreeRow: View {
    let item: FileItem
    @Binding var highlightedFile: URL?
    var isKeyboardSelected: Bool = false

    @Environment(AppState.self) private var appState
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var children: [FileItem] = []
    @State private var lastTapTime: Date = .distantPast

    private var isOpen: Bool       { appState.selectedFile == item.url }
    private var isHighlighted: Bool { highlightedFile == item.url || isOpen }

    var body: some View {
        VStack(spacing: 0) {
            rowContent
            if isExpanded && item.isDirectory {
                ForEach(children) { child in
                    FileTreeRow(item: child, highlightedFile: $highlightedFile)
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: CGFloat(item.depth) * 14 + Theme.Spacing.md)

            Group {
                if item.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Color.textTertiary)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }
            }

            Spacer().frame(width: Theme.Spacing.xs)

            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))
                .font(.system(size: 11))
                .foregroundStyle(item.isDirectory ? Theme.Color.accent.opacity(0.7) : Theme.Color.textTertiary)
                .frame(width: 14)

            Spacer().frame(width: Theme.Spacing.xs)

            Text(item.name)
                .font(.system(size: Theme.FontSize.sm,
                              weight: item.isDirectory ? .medium : .regular))
                .foregroundStyle(isHighlighted ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                .lineLimit(1)

            Spacer()
        }
        .frame(height: 24)
        .background(rowBackground)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            if !item.isDirectory {
                highlightedFile = item.url
                appState.openFile(item.url)
                DispatchQueue.main.async { appState.focusEditor() }
            }
        }
        .onTapGesture(count: 1) {
            if item.isDirectory {
                isExpanded.toggle()
                if isExpanded && children.isEmpty {
                    children = FileItem.children(of: item.url, depth: item.depth + 1)
                }
            } else {
                highlightedFile = item.url
            }
        }
    }

    private var rowBackground: some View {
        Group {
            if isOpen {
                Theme.Color.accentMuted
            } else if isHighlighted {
                Theme.Color.accentMuted.opacity(0.6)
            } else if isKeyboardSelected {
                Theme.Color.accent.opacity(0.15)
            } else if isHovered {
                Theme.Color.surfaceElevated
            } else {
                Color.clear
            }
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py":    return "doc.text.fill"
        case "js", "ts", "jsx", "tsx": return "doc.text.fill"
        case "json":  return "doc.badge.gearshape"
        case "md":    return "doc.richtext.fill"
        case "sh":    return "terminal.fill"
        default:      return "doc.fill"
        }
    }
}

// MARK: - FileItem

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let depth: Int

    static func children(of url: URL, depth: Int) -> [FileItem] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .compactMap { childURL -> FileItem? in
                let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir && ["node_modules", ".build", ".git", "DerivedData"].contains(childURL.lastPathComponent) {
                    return nil
                }
                return FileItem(url: childURL, name: childURL.lastPathComponent, isDirectory: isDir, depth: depth)
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }
}
