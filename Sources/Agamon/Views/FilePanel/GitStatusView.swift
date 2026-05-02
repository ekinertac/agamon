// Files tab of FilePanelView — flat list of every file touched since HEAD.
// Runs `git status --short` and maps the 2-char XY status to a single badge letter.
// Double-click opens the file in the editor. Single click just highlights the row.
// Related: FilePanelView.swift (hosts this), DiffListView.swift (Diff tab sibling),
//          AppState.openFile (opens the file in the editor panel).

import SwiftUI

// MARK: - Data

struct GitStatusItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let status: String   // "M", "A", "D", "R", "?"
    let statusColor: SwiftUI.Color
}

// MARK: - View

struct GitStatusView: View {
    let rootPath: String
    @Environment(AppState.self) private var appState
    @State private var items: [GitStatusItem] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded && items.isEmpty {
                emptyState("No changes")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            GitStatusRow(item: item)
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
            let raw    = gitOutput(["status", "--short"], in: root)
            let parsed = Self.parse(raw, rootPath: root)
            await MainActor.run { items = parsed; loaded = true }
        }
    }

    private static func parse(_ output: String, rootPath: String) -> [GitStatusItem] {
        let root = URL(fileURLWithPath: rootPath)
        return output.components(separatedBy: .newlines).compactMap { line in
            guard line.count >= 3 else { return nil as GitStatusItem? }
            let xy   = String(line.prefix(2))
            // Renames look like "old -> new"; take the destination path.
            let path = String(line.dropFirst(3))
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " -> ").last ?? ""
            guard !path.isEmpty else { return nil }
            let (badge, color) = statusBadge(xy)
            let url = root.appendingPathComponent(path)
            return GitStatusItem(url: url, name: url.lastPathComponent,
                                 status: badge, statusColor: color)
        }
    }

    private static func statusBadge(_ xy: String) -> (String, SwiftUI.Color) {
        if xy == "??" { return ("?", Theme.Color.textTertiary) }
        let x = xy.first ?? " "
        let y = xy.dropFirst().first ?? " "
        let ch = x != " " ? x : y
        switch ch {
        case "M": return ("M", Theme.Color.warning)
        case "A": return ("A", Theme.Color.success)
        case "D": return ("D", Theme.Color.danger)
        case "R": return ("R", Theme.Color.accent)
        default:  return (String(ch), Theme.Color.textTertiary)
        }
    }
}

// MARK: - Row

struct GitStatusRow: View {
    let item: GitStatusItem
    @Environment(AppState.self) private var appState
    @State private var isHovered  = false
    @State private var lastTap: Date = .distantPast

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

            Text(item.status)
                .font(.system(size: Theme.FontSize.xs, weight: .semibold, design: .monospaced))
                .foregroundStyle(item.statusColor)
                .frame(width: 14, alignment: .center)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 28)
        .background(isHovered ? Theme.Color.surfaceElevated : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastTap) < NSEvent.doubleClickInterval {
                appState.openFile(item.url)
                appState.focusEditor()
            }
            lastTap = now
        }
    }
}

// MARK: - Empty

private func emptyState(_ message: String) -> some View {
    VStack {
        Spacer()
        Text(message)
            .font(.system(size: Theme.FontSize.sm))
            .foregroundStyle(Theme.Color.textTertiary)
        Spacer()
    }
}
