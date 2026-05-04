// Data model for a single command center entry.
// CommandItem.commands() and CommandItem.projects() build the static lists from AppState.
// File items are built asynchronously by CommandCenterView and appended at query time.
// Related: CommandCenterView.swift (displays and filters these), AppState.swift (action targets).

import Foundation

struct CommandItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?  // shortcut hint for commands, relative path for files, root path for projects
    let icon: String       // SF Symbol name
    let category: Category
    var action: () -> Void

    enum Category { case command, project, file }

    // MARK: - Static builders

    static func commands(using appState: AppState) -> [CommandItem] {
        [
            CommandItem(title: "New Tab",            subtitle: "⌘T",   icon: "plus.rectangle.on.rectangle", category: .command) {
                if let id = appState.selectedProjectID { appState.addTab(to: id) }
            },
            CommandItem(title: "Split Right",        subtitle: "⌘D",   icon: "rectangle.split.2x1",  category: .command) {
                let id = appState.focusedPaneID ?? appState.selectedTab?.rootPane.firstLeafID
                if let id { appState.splitPane(id, axis: .horizontal) }
            },
            CommandItem(title: "Split Down",         subtitle: "⌘⇧D",  icon: "rectangle.split.1x2",  category: .command) {
                let id = appState.focusedPaneID ?? appState.selectedTab?.rootPane.firstLeafID
                if let id { appState.splitPane(id, axis: .vertical) }
            },
            CommandItem(title: "Zoom Pane",          subtitle: "⌘⇧↩",  icon: "arrow.up.left.and.arrow.down.right", category: .command, action: appState.togglePaneZoom),
            CommandItem(title: "Close Pane",         subtitle: "⌘W",   icon: "xmark.rectangle",      category: .command, action: appState.closeCurrentPane),
            CommandItem(title: "Toggle File Panel",  subtitle: "⌘E",   icon: "sidebar.right",         category: .command, action: appState.toggleFilePanel),
            CommandItem(title: "Open Project Folder…", subtitle: "⌘O", icon: "folder.badge.plus",     category: .command, action: appState.openProject),
            CommandItem(title: appState.editorFocused ? "Increase Editor Font" : "Increase Terminal Font",
                        subtitle: "⌘+",  icon: "plus.magnifyingglass",  category: .command, action: appState.increaseFontSize),
            CommandItem(title: appState.editorFocused ? "Decrease Editor Font" : "Decrease Terminal Font",
                        subtitle: "⌘−",  icon: "minus.magnifyingglass", category: .command, action: appState.decreaseFontSize),
            CommandItem(title: "Reset Terminal/Editor Font",
                        subtitle: "⌘0",  icon: "textformat",            category: .command, action: appState.resetFontSize),
            CommandItem(title: "Increase UI Font Size", subtitle: "⌘⇧+", icon: "textformat.size.larger",  category: .command, action: appState.increaseUIFontSize),
            CommandItem(title: "Decrease UI Font Size", subtitle: "⌘⇧−", icon: "textformat.size.smaller", category: .command, action: appState.decreaseUIFontSize),
            CommandItem(title: "Reset UI Font Size",    subtitle: "⌘⇧0", icon: "textformat",              category: .command, action: appState.resetUIFontSize),
            CommandItem(title: appState.editorLineWrap ? "Disable Line Wrap" : "Enable Line Wrap",
                        subtitle: nil, icon: "text.word.spacing", category: .command) {
                appState.editorLineWrap.toggle()
            },
        ]
    }

    // Only populated when there are multiple projects — switching to the current one is a no-op.
    static func projects(using appState: AppState) -> [CommandItem] {
        guard appState.projects.count > 1 else { return [] }
        return appState.projects.compactMap { project in
            guard project.id != appState.selectedProjectID else { return nil }
            return CommandItem(title: project.name, subtitle: project.rootPath,
                               icon: "square.2.layers.3d", category: .project) {
                appState.selectProject(project.id)
            }
        }
    }

    // MARK: - File icon helper

    static func fileIcon(for ext: String) -> String {
        switch ext.lowercased() {
        case "swift", "m", "mm", "c", "cpp", "h", "rs", "go",
             "py", "rb", "js", "ts", "jsx", "tsx", "mjs":
            return "doc.text"
        case "json", "jsonc":     return "curlybraces"
        case "yaml", "yml", "toml": return "list.dash"
        case "md", "txt", "rst": return "text.alignleft"
        case "sh", "bash", "zsh", "fish": return "terminal"
        case "html", "htm":      return "globe"
        case "css", "scss":      return "paintbrush"
        case "sql":              return "tablecells"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        default:                 return "doc"
        }
    }
}
