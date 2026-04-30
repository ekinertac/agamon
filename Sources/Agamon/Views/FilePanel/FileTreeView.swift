// Hierarchical file browser for the active project's root directory.
// Directories expand inline (no separate navigation level) for quick access to nested files.
// Skips hidden files by default — agents rarely need to browse .git or node_modules.
// Related: FilePanelView.swift (hosts this), FileEditorView.swift (opens files selected here).

import SwiftUI

struct FileTreeView: View {
    let rootPath: String
    @Binding var selectedFile: URL?
    @State private var rootItems: [FileItem] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rootItems) { item in
                    FileTreeRow(item: item, selectedFile: $selectedFile)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .onAppear { reload() }
        .onChange(of: rootPath) { reload() }
    }

    private func reload() {
        rootItems = FileItem.children(of: URL(fileURLWithPath: rootPath), depth: 0)
    }
}

// MARK: - Row

struct FileTreeRow: View {
    let item: FileItem
    @Binding var selectedFile: URL?
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var children: [FileItem] = []

    private var isSelected: Bool { selectedFile == item.url }

    var body: some View {
        VStack(spacing: 0) {
            rowContent
            if isExpanded && item.isDirectory {
                ForEach(children) { child in
                    FileTreeRow(item: child, selectedFile: $selectedFile)
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            // Depth indent
            Spacer().frame(width: CGFloat(item.depth) * 14 + Theme.Spacing.md)

            // Expand chevron (directories only)
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

            // Icon
            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))
                .font(.system(size: 11))
                .foregroundStyle(item.isDirectory ? Theme.Color.accent.opacity(0.7) : Theme.Color.textTertiary)
                .frame(width: 14)

            Spacer().frame(width: Theme.Spacing.xs)

            Text(item.name)
                .font(.system(size: Theme.FontSize.sm,
                              weight: item.isDirectory ? .medium : .regular))
                .foregroundStyle(isSelected ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                .lineLimit(1)

            Spacer()
        }
        .frame(height: 24)
        .background(
            isSelected
            ? Theme.Color.accentMuted
            : (isHovered ? Theme.Color.surfaceElevated : Color.clear)
        )
        .onHover { isHovered = $0 }
        .onTapGesture {
            if item.isDirectory {
                isExpanded.toggle()
                if isExpanded && children.isEmpty {
                    children = FileItem.children(of: item.url, depth: item.depth + 1)
                }
            } else {
                selectedFile = item.url
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
                // Skip common large/noisy directories agents don't need to browse
                if isDir && ["node_modules", ".build", ".git", "DerivedData"].contains(childURL.lastPathComponent) {
                    return nil
                }
                return FileItem(url: childURL, name: childURL.lastPathComponent, isDirectory: isDir, depth: depth)
            }
            .sorted { a, b in
                // Directories first, then alphabetical
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }
}
