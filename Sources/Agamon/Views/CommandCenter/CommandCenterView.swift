// Command center palette — unified search over commands, projects, and project files.
// Triggered by Cmd+P (Shortcuts.swift), dismissible by Escape or backdrop click.
// Files are walked asynchronously on open; results are cached for the session.
// Keyboard navigation: ↑↓ to move selection, ↩ to activate, ⎋ to dismiss.
// Related: CommandItem.swift (data model + static builders), AppState.commandCenterVisible,
//          ContentView.swift (hosts the overlay), Shortcuts.swift (Cmd+P binding).

import SwiftUI
import AppKit

// MARK: - CommandCenterView

struct CommandCenterView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var fileItems: [CommandItem] = []
    @State private var isLoadingFiles = false

    private var commandItems: [CommandItem] { CommandItem.commands(using: appState) }
    private var projectItems: [CommandItem] { CommandItem.projects(using: appState) }

    // When empty query: commands + projects only (file list is too long to browse unfiltered).
    // When query present: fuzzy-rank everything by score.
    // Capped at 50 so the result VStack stays fast (LazyVStack breaks scrollTo for off-screen items).
    private var filtered: [CommandItem] {
        let all: [CommandItem]
        if query.isEmpty {
            all = commandItems + projectItems
        } else {
            all = (commandItems + projectItems + fileItems)
                .compactMap { item -> (item: CommandItem, score: Int)? in
                    let (hit, score) = fuzzyScore(query, in: item.title)
                    guard hit else { return nil }
                    return (item, score)
                }
                .sorted { $0.score > $1.score }
                .map(\.item)
        }
        return Array(all.prefix(50))
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { appState.commandCenterVisible = false }

            VStack(spacing: 0) {
                // Search field row
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.Color.textSecondary)
                        .font(.system(size: 15, weight: .medium))

                    PaletteTextField(
                        text: $query,
                        placeholder: "Search commands and files…",
                        onArrowDown: moveDown,
                        onArrowUp:   moveUp,
                        onReturn:    activateSelected,
                        onEscape:    { appState.commandCenterVisible = false }
                    )
                    .frame(height: 24)

                    if isLoadingFiles {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 11)

                if !filtered.isEmpty {
                    Rectangle()
                        .fill(Theme.Color.border)
                        .frame(height: 1)

                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            // VStack (not LazyVStack): all rows must be in the view hierarchy
                            // so scrollTo can find off-screen items. Safe because filtered
                            // is capped at 50 items.
                            VStack(spacing: 0) {
                                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, item in
                                    CommandRow(item: item, isSelected: idx == selectedIndex)
                                        .id(item.id)
                                        .onTapGesture { selectedIndex = idx; activateSelected() }
                                }
                            }
                            .padding(.vertical, Theme.Spacing.xs)
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selectedIndex) { _, new in
                            guard new < filtered.count else { return }
                            // anchor: nil = scroll minimum amount to make item visible
                            proxy.scrollTo(filtered[new].id, anchor: nil)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Color.surface)
                    .shadow(color: .black.opacity(0.65), radius: 28, x: 0, y: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .frame(width: 580)
            .frame(maxWidth: 580)
            // Position slightly above center — VS Code palette position feels right
            .offset(y: -60)
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onAppear { loadFiles() }
    }

    // MARK: - Navigation

    private func moveDown() {
        selectedIndex = min(selectedIndex + 1, max(0, filtered.count - 1))
    }

    private func moveUp() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    private func activateSelected() {
        guard selectedIndex < filtered.count else { return }
        let item = filtered[selectedIndex]
        appState.commandCenterVisible = false
        // Short delay so the dismiss animation starts before the action fires
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { item.action() }
    }

    // MARK: - File loading

    private func loadFiles() {
        guard let rootPath = appState.selectedProject?.rootPath, !isLoadingFiles else { return }
        isLoadingFiles = true
        let root = URL(fileURLWithPath: rootPath)
        Task {
            let urls = await walkFiles(at: root)
            let items = urls.map { url -> CommandItem in
                let path = url.path
                let rel  = path.hasPrefix(root.path + "/") ? String(path.dropFirst(root.path.count + 1)) : path
                return CommandItem(title: url.lastPathComponent, subtitle: rel,
                                   icon: CommandItem.fileIcon(for: url.pathExtension),
                                   category: .file) { [weak appState] in
                    appState?.openFile(url)
                }
            }
            await MainActor.run { fileItems = items; isLoadingFiles = false }
        }
    }

    private func walkFiles(at root: URL) async -> [URL] {
        let ignored: Set<String> = [
            ".git", ".build", ".swiftpm", "node_modules", "__pycache__", "Pods",
            "DerivedData", ".idea", ".vscode", "dist", ".next", "vendor", "target",
            ".cache", ".hg", ".svn", "build", "out",
        ]
        var results: [URL] = []
        var stack: [(URL, Int)] = [(root, 0)]
        while !stack.isEmpty {
            let (dir, depth) = stack.removeLast()
            guard depth <= 7 else { continue }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            ) else { continue }
            for url in contents {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir {
                    if !ignored.contains(url.lastPathComponent) { stack.append((url, depth + 1)) }
                } else {
                    results.append(url)
                    if results.count >= 5000 { return results }
                }
            }
        }
        return results
    }

    // MARK: - Fuzzy match

    // Subsequence match with scoring: consecutive matches +3, word-boundary matches +3,
    // leading-char match +4. Higher score = shown first.
    private func fuzzyScore(_ query: String, in target: String) -> (Bool, Int) {
        let q = query.lowercased()
        let t = target.lowercased()
        var qi = q.startIndex
        var score = 0
        var prevIdx: String.Index? = nil
        for ti in t.indices {
            guard qi < q.endIndex else { break }
            if t[ti] == q[qi] {
                if let prev = prevIdx, t.index(after: prev) == ti { score += 3 }
                else { score += 1 }
                if ti == t.startIndex { score += 4 }
                else if "/_.- :".contains(t[t.index(before: ti)]) { score += 3 }
                prevIdx = ti
                qi = q.index(after: qi)
            }
        }
        return (qi == q.endIndex, score)
    }
}

// MARK: - CommandRow

private struct CommandRow: View {
    let item: CommandItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textSecondary)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: Theme.FontSize.sm))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)

                // Show path subtitle for files and projects only (not commands — they use right-aligned shortcut)
                if let sub = item.subtitle, item.category != .command {
                    Text(sub)
                        .font(.system(size: Theme.FontSize.xs, design: .monospaced))
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Shortcut badge for commands
            if let sub = item.subtitle, item.category == .command {
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.06))
                    )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - PaletteTextField

// NSTextField wrapper that routes ↑↓↩⎋ to callbacks while the field has keyboard focus.
//
// Why NSTextFieldDelegate.control(_:textView:doCommandBy:) instead of keyDown override:
// NSTextField uses an internal NSTextView (the "field editor") as the actual first responder
// while editing. The field editor consumes all key events before NSTextField.keyDown ever
// fires. The delegate method doCommandBy is called by the field editor for every command
// selector, which is the only reliable hook for navigation keys inside a text field.
private struct PaletteTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void
    var onReturn: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> PaletteNSTextField {
        let field = PaletteNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor(white: 0.4, alpha: 1),
                .font: NSFont.systemFont(ofSize: 15),
            ]
        )
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: PaletteNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteTextField
        init(_ parent: PaletteTextField) { self.parent = parent }

        func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            parent.text = f.stringValue
        }

        // Called by the field editor for every command selector — this fires for
        // navigation keys that keyDown on NSTextField itself never receives.
        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onArrowDown(); return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onArrowUp(); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onReturn(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape(); return true
            default:
                return false
            }
        }
    }
}

// Minimal NSTextField subclass: only purpose is grabbing first responder on appear.
final class PaletteNSTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { self.window?.makeFirstResponder(self) }
        }
    }
}
