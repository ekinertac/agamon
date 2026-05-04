// Hierarchical file browser for the active project's root directory.
// Expansion state lives in FileTreeView (expandedPaths + childrenCache) so keyboard
// navigation can operate on a flat visibleItems list that spans the full tree depth.
// FileTreeRow is a pure presentation row — it receives expansion state as props and
// calls back via onToggle; it never owns children or expansion state itself.
//
// Keyboard nav: ↑↓ move, → expands dir or enters first child, ← collapses or goes to
// parent, Enter opens file / toggles dir, Escape releases focus → terminal.
// Context menu on each row: New File, New Folder, Rename, Delete (trash).
// Related: FilePanelView.swift (hosts this), EditorPanelView.swift (displays opened files),
//          AppState.swift (openFile, focusEditor, refocusActiveTerminal).

import SwiftUI

// Shows an NSAlert with a text field accessory. Returns trimmed input or nil if cancelled/empty.
@discardableResult
private func askForName(title: String, placeholder: String, initial: String = "") -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
    tf.stringValue = initial
    tf.placeholderString = placeholder
    alert.accessoryView = tf
    alert.window.initialFirstResponder = tf
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let name = tf.stringValue.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
}

struct FileTreeView: View {
    let rootPath: String
    @Binding var keyboardFocused: Bool
    var gitStatus: [URL: String] = [:]

    @Environment(AppState.self) private var appState
    @State private var rootItems: [FileItem] = []
    @State private var expandedPaths: Set<URL> = []
    @State private var childrenCache: [URL: [FileItem]] = [:]
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
                            highlightedFile: $highlightedFile,
                            isKeyboardSelected: internalFocus && idx == keyboardIndex,
                            gitBadge: gitStatus[item.url],
                            onToggle: { toggleExpanded(item) },
                            onReload: { reload() }
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
            expandedPaths = expandedPaths.filter { !$0.path.hasPrefix(item.url.path + "/") && $0 != item.url }
        } else {
            expandedPaths.insert(item.url)
        }
    }

    private func scroll(to index: Int, proxy: ScrollViewProxy) {
        guard index < visibleItems.count else { return }
        proxy.scrollTo(visibleItems[index].id, anchor: .center)
    }

    private func reload() {
        let root = URL(fileURLWithPath: rootPath)
        var cache: [URL: [FileItem]] = [:]
        FileItem.prefill(from: root, depth: 0, into: &cache)
        childrenCache = cache
        rootItems = cache[root] ?? []
        // Keep only expanded paths that still exist; don't collapse the whole tree.
        expandedPaths = expandedPaths.filter { FileManager.default.fileExists(atPath: $0.path) }
        keyboardIndex = min(keyboardIndex, max(0, visibleItems.count - 1))
    }
}

// MARK: - Row

// Pure presentation — receives expansion state, calls back via onToggle / onReload.
// Children are NOT rendered here; the flat list in FileTreeView handles ordering.
// Context menu (New File, New Folder, Rename, Delete) lives here and delegates
// filesystem changes back to FileTreeView via onReload.
struct FileTreeRow: View {
    let item: FileItem
    let isExpanded: Bool
    @Binding var highlightedFile: URL?
    var isKeyboardSelected: Bool = false
    var gitBadge: String? = nil
    var onToggle: () -> Void = {}
    var onReload: () -> Void = {}

    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var lastTapTime: Date = .distantPast

    private var isOpen: Bool        { appState.selectedFile == item.url }
    private var isHighlighted: Bool { highlightedFile == item.url || isOpen }

    var body: some View {
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

            if let badge = gitBadge {
                Text(badge)
                    .font(.system(size: Theme.FontSize.xs, weight: .semibold, design: .monospaced))
                    .foregroundStyle(badgeColor(badge))
                    .frame(width: 14, alignment: .center)
                    .padding(.trailing, Theme.Spacing.xs)
            }
        }
        .frame(height: 24)
        .background(rowBackground)
        .onHover { isHovered = $0 }
        .onTapGesture {
            // Single handler avoids SwiftUI's ~300ms disambiguation delay that
            // count:2 + count:1 stacking introduces on every single tap.
            let now = Date()
            let isDouble = now.timeIntervalSince(lastTapTime) < NSEvent.doubleClickInterval
            lastTapTime = now
            if item.isDirectory {
                onToggle()
            } else if isDouble {
                appState.openFile(item.url)
                appState.focusEditor()
            } else {
                highlightedFile = item.url
            }
        }
        .contextMenu {
            Button("New File") {
                // Create inside the directory if item is a dir, otherwise alongside it.
                let parentDir = item.isDirectory
                    ? item.url
                    : item.url.deletingLastPathComponent()
                guard let name = askForName(title: "New File", placeholder: "filename.swift") else { return }
                let newURL = parentDir.appendingPathComponent(name)
                do {
                    try "".write(to: newURL, atomically: true, encoding: .utf8)
                    onReload()
                    appState.openFile(newURL)
                } catch {
                    let err = NSAlert()
                    err.messageText = "Could not create file"
                    err.informativeText = error.localizedDescription
                    err.runModal()
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Folder") {
                let parentDir = item.isDirectory
                    ? item.url
                    : item.url.deletingLastPathComponent()
                guard let name = askForName(title: "New Folder", placeholder: "FolderName") else { return }
                let newURL = parentDir.appendingPathComponent(name)
                do {
                    try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
                    onReload()
                } catch {
                    let err = NSAlert()
                    err.messageText = "Could not create folder"
                    err.informativeText = error.localizedDescription
                    err.runModal()
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button("Rename") {
                guard let newName = askForName(
                    title: "Rename \"\(item.name)\"",
                    placeholder: item.name,
                    initial: item.name
                ) else { return }
                let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
                do {
                    try FileManager.default.moveItem(at: item.url, to: newURL)
                    // Keep AppState in sync for any open editor tabs referencing the old URL.
                    appState.renameOpenFile(from: item.url, to: newURL)
                    onReload()
                } catch {
                    let err = NSAlert()
                    err.messageText = "Could not rename"
                    err.informativeText = error.localizedDescription
                    err.runModal()
                }
            }

            Button("Delete", role: .destructive) {
                let confirm = NSAlert()
                confirm.messageText = "Move \"\(item.name)\" to Trash?"
                confirm.informativeText = "This action can be undone from the Trash."
                confirm.addButton(withTitle: "Move to Trash")
                confirm.addButton(withTitle: "Cancel")
                confirm.alertStyle = .warning
                guard confirm.runModal() == .alertFirstButtonReturn else { return }
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    // Remove from open files if it was open.
                    appState.renameOpenFile(from: item.url, to: nil)
                    onReload()
                } catch {
                    let err = NSAlert()
                    err.messageText = "Could not delete"
                    err.informativeText = error.localizedDescription
                    err.runModal()
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }

    private func badgeColor(_ badge: String) -> SwiftUI.Color {
        switch badge {
        case "M": return Theme.Color.warning
        case "A": return Theme.Color.success
        case "D": return Theme.Color.danger
        case "R": return Theme.Color.accent
        default:  return Theme.Color.textTertiary
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

    // Recursively pre-walk the tree into cache so every expand is a pure dict lookup.
    static func prefill(from url: URL, depth: Int, into cache: inout [URL: [FileItem]]) {
        let items = children(of: url, depth: depth)
        cache[url] = items
        for item in items where item.isDirectory {
            prefill(from: item.url, depth: depth + 1, into: &cache)
        }
    }

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
