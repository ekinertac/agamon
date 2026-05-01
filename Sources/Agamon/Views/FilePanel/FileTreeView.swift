// Hierarchical file browser for the active project's root directory.
// Expansion state lives in FileTreeView (expandedPaths + childrenCache) so keyboard
// navigation can operate on a flat visibleItems list that spans the full tree depth.
// FileTreeRow is a pure presentation row — it receives expansion state as props and
// calls back via onToggle; it never owns children or expansion state itself.
//
// Keyboard nav: ↑↓ move, → expands dir or enters first child, ← collapses or goes to
// parent, Enter opens file / toggles dir, Escape releases focus → terminal.
// Related: FilePanelView.swift (hosts this), EditorPanelView.swift (displays opened files),
//          AppState.swift (openFile, focusEditor, refocusActiveTerminal).

import SwiftUI

struct FileTreeView: View {
    let rootPath: String
    @Binding var keyboardFocused: Bool

    @Environment(AppState.self) private var appState
    @State private var rootItems: [FileItem] = []
    @State private var expandedPaths: Set<URL> = []
    @State private var childrenCache: [URL: [FileItem]] = [:]
    @State private var loadingPaths: Set<URL> = []
    @State private var keyboardIndex: Int = 0
    @State private var highlightedFile: URL?
    @FocusState private var internalFocus: Bool

    // Flat ordered list of every row currently visible (root + expanded subtrees).
    private var visibleItems: [FileItem] { flatten(rootItems) }

    private func flatten(_ items: [FileItem]) -> [FileItem] {
        items.flatMap { item -> [FileItem] in
            guard item.isDirectory, expandedPaths.contains(item.url) else { return [item] }
            return [item] + flatten(childrenCache[item.url] ?? [])
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { idx, item in
                        FileTreeRow(
                            item: item,
                            isExpanded: expandedPaths.contains(item.url),
                            isLoading: loadingPaths.contains(item.url),
                            highlightedFile: $highlightedFile,
                            isKeyboardSelected: internalFocus && idx == keyboardIndex,
                            onToggle: { toggleExpanded(item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($internalFocus)
            .onKeyPress(.upArrow) {
                guard keyboardIndex > 0 else { return .handled }
                keyboardIndex -= 1
                scroll(to: keyboardIndex, proxy: proxy)
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard keyboardIndex < visibleItems.count - 1 else { return .handled }
                keyboardIndex += 1
                scroll(to: keyboardIndex, proxy: proxy)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard !visibleItems.isEmpty else { return .ignored }
                let item = visibleItems[keyboardIndex]
                guard item.isDirectory else { return .handled }
                if !expandedPaths.contains(item.url) {
                    // Expand the directory
                    toggleExpanded(item)
                } else if keyboardIndex + 1 < visibleItems.count {
                    // Already expanded — move into first child
                    keyboardIndex += 1
                    scroll(to: keyboardIndex, proxy: proxy)
                }
                return .handled
            }
            .onKeyPress(.leftArrow) {
                guard !visibleItems.isEmpty else { return .ignored }
                let item = visibleItems[keyboardIndex]
                if item.isDirectory && expandedPaths.contains(item.url) {
                    toggleExpanded(item)
                } else {
                    // Jump to parent directory
                    let parentDepth = item.depth - 1
                    if parentDepth >= 0 {
                        for i in stride(from: keyboardIndex - 1, through: 0, by: -1) {
                            if visibleItems[i].depth == parentDepth {
                                keyboardIndex = i
                                scroll(to: i, proxy: proxy)
                                break
                            }
                        }
                    }
                }
                return .handled
            }
            .onKeyPress(.return) {
                guard !visibleItems.isEmpty else { return .ignored }
                let item = visibleItems[keyboardIndex]
                if item.isDirectory {
                    toggleExpanded(item)
                } else {
                    internalFocus = false
                    appState.openFile(item.url)
                    appState.focusEditor()
                }
                return .handled
            }
            .onKeyPress(.escape) {
                internalFocus = false
                appState.refocusActiveTerminal()
                return .handled
            }
            .onChange(of: expandedPaths) { _, _ in
                // Clamp after collapse shrinks the list
                keyboardIndex = min(keyboardIndex, max(0, visibleItems.count - 1))
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
    }

    // MARK: - Helpers

    private func toggleExpanded(_ item: FileItem) {
        guard item.isDirectory else { return }
        if expandedPaths.contains(item.url) {
            // Remove this dir and all descendants so re-expanding starts fresh.
            expandedPaths = expandedPaths.filter { !$0.path.hasPrefix(item.url.path + "/") && $0 != item.url }
        } else if childrenCache[item.url] != nil {
            expandedPaths.insert(item.url)
        } else {
            // Read directory off the main thread so the UI doesn't stall.
            loadingPaths.insert(item.url)
            Task.detached(priority: .userInitiated) {
                let children = FileItem.children(of: item.url, depth: item.depth + 1)
                await MainActor.run {
                    childrenCache[item.url] = children
                    loadingPaths.remove(item.url)
                    expandedPaths.insert(item.url)
                }
            }
        }
    }

    private func scroll(to index: Int, proxy: ScrollViewProxy) {
        guard index < visibleItems.count else { return }
        proxy.scrollTo(visibleItems[index].id, anchor: .center)
    }

    private func reload() {
        expandedPaths = []
        childrenCache = [:]
        loadingPaths = []
        keyboardIndex = 0
        let url = URL(fileURLWithPath: rootPath)
        Task.detached(priority: .userInitiated) {
            let items = FileItem.children(of: url, depth: 0)
            await MainActor.run { rootItems = items }
        }
    }
}

// MARK: - Row

// Pure presentation — receives expansion state, calls back via onToggle.
// Children are NOT rendered here; the flat list in FileTreeView handles ordering.
struct FileTreeRow: View {
    let item: FileItem
    let isExpanded: Bool
    var isLoading: Bool = false
    @Binding var highlightedFile: URL?
    var isKeyboardSelected: Bool = false
    var onToggle: () -> Void = {}

    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    private var isOpen: Bool        { appState.selectedFile == item.url }
    private var isHighlighted: Bool { highlightedFile == item.url || isOpen }

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: CGFloat(item.depth) * 14 + Theme.Spacing.md)

            Group {
                if item.isDirectory {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.Color.textTertiary)
                            .frame(width: 12)
                    }
                } else {
                    Spacer().frame(width: 12)
                }
            }

            Spacer().frame(width: Theme.Spacing.xs)

            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))
                .font(.system(size: 11))
                .foregroundStyle(item.isDirectory
                    ? Theme.Color.accent.opacity(0.7)
                    : Theme.Color.textTertiary)
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
                appState.focusEditor()
            }
        }
        .onTapGesture(count: 1) {
            if item.isDirectory { onToggle() }
            else { highlightedFile = item.url }
        }
    }

    private var rowBackground: some View {
        Group {
            if isOpen              { Theme.Color.accentMuted }
            else if isHighlighted  { Theme.Color.accentMuted.opacity(0.6) }
            else if isKeyboardSelected { Theme.Color.accent.opacity(0.15) }
            else if isHovered      { Theme.Color.surfaceElevated }
            else                   { Color.clear }
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":                  return "swift"
        case "py":                     return "doc.text.fill"
        case "js", "ts", "jsx", "tsx": return "doc.text.fill"
        case "json":                   return "doc.badge.gearshape"
        case "md":                     return "doc.richtext.fill"
        case "sh":                     return "terminal.fill"
        default:                       return "doc.fill"
        }
    }
}

// MARK: - FileItem

struct FileItem: Identifiable {
    // URL is stable across recomputation — used for ForEach identity and ScrollViewReader.
    var id: URL { url }
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
                if isDir && ["node_modules", ".build", ".git", "DerivedData"]
                    .contains(childURL.lastPathComponent) { return nil }
                return FileItem(url: childURL, name: childURL.lastPathComponent,
                                isDirectory: isDir, depth: depth)
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }
}
