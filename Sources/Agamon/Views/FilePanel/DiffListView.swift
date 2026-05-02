// Diff tab of FilePanelView — flat list of changed files with +/- line counts.
// Runs `git diff HEAD --numstat` so both staged and unstaged changes are included.
// Tapping a row calls AppState.openDiff which opens DiffEditorView in the editor panel.
// Related: FilePanelView.swift (hosts this), FileTreeView.swift (Files tab sibling),
//          DiffEditorView.swift (renders the selected file's unified diff),
//          AppState.openDiff (creates the agamon-diff:// URL routed to DiffEditorView).

import SwiftUI

// MARK: - Data

struct DiffFileItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let added: Int
    let deleted: Int
}

// MARK: - View

struct DiffListView: View {
    let rootPath: String
    @Environment(AppState.self) private var appState
    @State private var items: [DiffFileItem] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded && items.isEmpty {
                VStack {
                    Spacer()
                    Text("No diff")
                        .font(.system(size: Theme.FontSize.sm))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            DiffFileRow(item: item)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: rootPath) { reload() }
    }

    private func reload() {
        let root = rootPath
        Task.detached(priority: .utility) {
            let raw    = gitOutput(["diff", "HEAD", "--numstat"], in: root)
            let parsed = Self.parse(raw, rootPath: root)
            await MainActor.run { items = parsed; loaded = true }
        }
    }

    private static func parse(_ output: String, rootPath: String) -> [DiffFileItem] {
        let root = URL(fileURLWithPath: rootPath)
        return output.components(separatedBy: .newlines).compactMap { line -> DiffFileItem? in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3,
                  let added   = Int(parts[0]),
                  let deleted = Int(parts[1]) else { return nil }
            let path = parts[2].trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " => ").last ?? parts[2]
            guard !path.isEmpty else { return nil }
            let url = root.appendingPathComponent(path)
            return DiffFileItem(url: url, name: url.lastPathComponent,
                                added: added, deleted: deleted)
        }
    }
}

// MARK: - Row

struct DiffFileRow: View {
    let item: DiffFileItem
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(width: 14, alignment: .center)

            Text(item.name)
                .font(.system(size: Theme.FontSize.sm))
                .foregroundStyle(Theme.Color.textSecondary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                Text("+\(item.added)")
                    .font(.system(size: Theme.FontSize.xs, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Color.success)
                Text("-\(item.deleted)")
                    .font(.system(size: Theme.FontSize.xs, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Color.danger)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 28)
        .background(isHovered ? Theme.Color.surfaceElevated : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { appState.openDiff(item.url) }
    }
}
