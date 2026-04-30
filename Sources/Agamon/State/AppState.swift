// Central observable state for the entire app. Injected via @Environment(AppState.self).
// All mutation goes through here — views never mutate models directly.
// Persistence: projects are written to ~/.agamon/projects.json on every change.
// Related: Project.swift, WorkTab.swift, PaneNode.swift (the models this state wraps),
//          AgamonApp.swift (injects into environment), ContentView.swift (primary consumer).

import AppKit
import Foundation
import Observation

extension Notification.Name {
    // Posted with object: UUID (paneID) to command a specific terminal to become first responder.
    static let agamonFocusTerminal = Notification.Name("agamonFocusTerminal")
}

@Observable
final class AppState {

    // MARK: - Terminal View Cache

    // Keyed by pane UUID. Outlives SwiftUI view lifecycle so pty sessions survive tab
    // switches, new splits, and any other pane-tree restructuring that triggers makeNSView.
    var terminalViews: [UUID: AgamonTerminalView] = [:]

    // MARK: - Tab Focus Memory

    // Session-only (not persisted). Saves last focused paneID per tab so switching
    // back to a tab restores the exact pane that was active when you left it.
    private var tabFocusMemory: [UUID: UUID] = [:]

    private func rememberFocus() {
        guard let tabID = selectedTabID, let paneID = focusedPaneID else { return }
        tabFocusMemory[tabID] = paneID
    }

    // Restore the remembered pane for a tab, falling back to firstLeaf if it no longer exists.
    private func restoreFocus(for tab: WorkTab) {
        let allLeaves = tab.rootPane.leafIDs()
        if let remembered = tabFocusMemory[tab.id], allLeaves.contains(remembered) {
            focusedPaneID = remembered
        } else {
            focusedPaneID = tab.rootPane.firstLeafID
        }
    }

    private func evictTerminalViews(for pane: PaneNode) {
        switch pane {
        case .leaf(let id, _):
            terminalViews.removeValue(forKey: id)
        case .split(_, _, _, let first, let second):
            evictTerminalViews(for: first)
            evictTerminalViews(for: second)
        }
    }

    // MARK: - State

    var projects: [Project] = []
    var selectedProjectID: UUID?
    var selectedTabID: UUID?
    var focusedPaneID: UUID?
    var selectedFile: URL? = nil
    var editorPanelVisible: Bool = false
    var filePanelVisible: Bool = true
    var filePanelFocused: Bool = false
    var activeModifiers: NSEvent.ModifierFlags = []

    var showsCtrlShortcuts: Bool { activeModifiers.contains(.control) }
    var showsCmdShortcuts:  Bool { activeModifiers.contains(.command) }
    var terminalFontSize: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "terminalFontSize")
        return saved > 0 ? CGFloat(saved) : 13
    }()

    var terminalFontFamily: String = UserDefaults.standard.string(forKey: "terminalFontFamily") ?? "" {
        didSet { UserDefaults.standard.set(terminalFontFamily, forKey: "terminalFontFamily") }
    }

    var shellPath: String = {
        UserDefaults.standard.string(forKey: "shellPath")
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
    }() {
        didSet { UserDefaults.standard.set(shellPath, forKey: "shellPath") }
    }

    var dimInactivePanes: Bool = {
        UserDefaults.standard.object(forKey: "dimInactivePanes") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "dimInactivePanes")
    }() {
        didSet { UserDefaults.standard.set(dimInactivePanes, forKey: "dimInactivePanes") }
    }

    var inactivePaneDimAmount: Double = {
        let v = UserDefaults.standard.double(forKey: "inactivePaneDimAmount")
        return v > 0 ? v : 0.35
    }() {
        didSet { UserDefaults.standard.set(inactivePaneDimAmount, forKey: "inactivePaneDimAmount") }
    }

    var dimOnlyText: Bool = UserDefaults.standard.bool(forKey: "dimOnlyText") {
        didSet { UserDefaults.standard.set(dimOnlyText, forKey: "dimOnlyText") }
    }

    // MARK: - Derived

    var selectedProject: Project? {
        get { projects.first { $0.id == selectedProjectID } }
        set {
            guard let p = newValue,
                  let i = projects.firstIndex(where: { $0.id == p.id })
            else { return }
            projects[i] = p
        }
    }

    var selectedTab: WorkTab? {
        selectedProject?.tabs.first { $0.id == selectedTabID }
    }

    // MARK: - Project Actions

    func addProject(name: String, rootPath: String) {
        let project = Project(name: name, rootPath: rootPath)
        projects.append(project)
        selectProject(project.id)
        persist()
    }

    func removeProject(_ id: UUID) {
        if let project = projects.first(where: { $0.id == id }) {
            project.tabs.forEach { evictTerminalViews(for: $0.rootPane) }
        }
        projects.removeAll { $0.id == id }
        if selectedProjectID == id {
            selectedProjectID = projects.last?.id
            selectedTabID = projects.last?.tabs.first?.id
            focusedPaneID = projects.last?.tabs.first?.rootPane.firstLeafID
        }
        persist()
    }

    func selectProject(_ id: UUID) {
        selectedProjectID = id
        let firstTab = projects.first { $0.id == id }?.tabs.first
        selectedTabID = firstTab?.id
        focusedPaneID = firstTab?.rootPane.firstLeafID
    }

    // Opens a folder picker and immediately adds the selected directory as a project.
    func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.addProject(name: url.lastPathComponent, rootPath: url.path)
        }
    }

    // MARK: - Tab Actions

    func addTab(to projectID: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let tab = WorkTab()
        projects[i].tabs.append(tab)
        selectedTabID = tab.id
        focusedPaneID = tab.rootPane.firstLeafID
        persist()
    }

    func removeTab(_ tabID: UUID, from projectID: UUID) {
        guard let pi = projects.firstIndex(where: { $0.id == projectID }) else { return }
        if let tab = projects[pi].tabs.first(where: { $0.id == tabID }) {
            evictTerminalViews(for: tab.rootPane)
        }
        projects[pi].tabs.removeAll { $0.id == tabID }
        if selectedTabID == tabID {
            let fallback = projects[pi].tabs.last
            selectedTabID = fallback?.id
            focusedPaneID = fallback?.rootPane.firstLeafID
        }
        persist()
    }

    func renameTab(_ tabID: UUID, in projectID: UUID, to name: String) {
        guard let pi = projects.firstIndex(where: { $0.id == projectID }),
              let ti = projects[pi].tabs.firstIndex(where: { $0.id == tabID })
        else { return }
        projects[pi].tabs[ti].name = name
        persist()
    }

    // MARK: - Tab Navigation

    func nextTab() {
        guard let project = selectedProject,
              let idx = project.tabs.firstIndex(where: { $0.id == selectedTabID }),
              project.tabs.count > 1
        else { return }
        rememberFocus()
        let tab = project.tabs[(idx + 1) % project.tabs.count]
        selectedTabID = tab.id
        restoreFocus(for: tab)
    }

    func prevTab() {
        guard let project = selectedProject,
              let idx = project.tabs.firstIndex(where: { $0.id == selectedTabID }),
              project.tabs.count > 1
        else { return }
        rememberFocus()
        let tab = project.tabs[(idx - 1 + project.tabs.count) % project.tabs.count]
        selectedTabID = tab.id
        restoreFocus(for: tab)
    }

    func selectTab(at index: Int) {
        guard let project = selectedProject, index < project.tabs.count else { return }
        rememberFocus()
        let tab = project.tabs[index]
        selectedTabID = tab.id
        restoreFocus(for: tab)
    }

    func selectProject(at index: Int) {
        guard index < projects.count else { return }
        selectProject(projects[index].id)
    }

    // MARK: - Pane Close

    // Removes the focused pane from the split tree. If it's the only pane, closes the tab.
    func closeCurrentPane() {
        guard let projectID = selectedProjectID,
              let tabID = selectedTabID,
              let pi = projects.firstIndex(where: { $0.id == projectID }),
              let ti = projects[pi].tabs.firstIndex(where: { $0.id == tabID })
        else { return }

        let paneID = focusedPaneID ?? projects[pi].tabs[ti].rootPane.firstLeafID
        terminalViews.removeValue(forKey: paneID)
        if let newRoot = projects[pi].tabs[ti].rootPane.removingLeaf(id: paneID) {
            projects[pi].tabs[ti].rootPane = newRoot
            focusedPaneID = newRoot.firstLeafID
            persist()
        } else {
            removeTab(tabID, from: projectID)
        }
    }

    // MARK: - Font Size

    func increaseFontSize() { setFontSize(min(terminalFontSize + 1, 32)) }
    func decreaseFontSize() { setFontSize(max(terminalFontSize - 1, 8)) }
    func resetFontSize()    { setFontSize(13) }

    private func setFontSize(_ size: CGFloat) {
        terminalFontSize = size
        UserDefaults.standard.set(Double(size), forKey: "terminalFontSize")
    }

    // MARK: - Editor Panel

    func openFile(_ url: URL) {
        selectedFile = url
        editorPanelVisible = true
    }

    func closeEditor() {
        editorPanelVisible = false
    }

    // MARK: - File Panel

    func focusFilePanel() {
        // Pin focusedPaneID before handing focus away so we know where to return.
        if focusedPaneID == nil {
            focusedPaneID = selectedTab?.rootPane.firstLeafID
        }
        filePanelVisible = true
        filePanelFocused = true
    }

    func toggleFilePanel() {
        if filePanelVisible {
            filePanelVisible = false
            filePanelFocused = false
        } else {
            focusFilePanel()
        }
    }

    // Posts a notification so the active terminal's NSView calls makeFirstResponder on itself.
    // Uses NotificationCenter rather than updateNSView to avoid SwiftUI render-cycle timing races.
    func refocusActiveTerminal() {
        if focusedPaneID == nil {
            focusedPaneID = selectedTab?.rootPane.firstLeafID
        }
        guard let id = focusedPaneID else { return }
        NotificationCenter.default.post(name: .agamonFocusTerminal, object: id)
    }

    // Updates the ratio of a split node without persisting — ratios are session-only.
    func updateSplitRatio(splitID: UUID, newRatio: CGFloat) {
        guard let pi = projects.firstIndex(where: { $0.id == selectedProjectID }),
              let ti = projects[pi].tabs.firstIndex(where: { $0.id == selectedTabID })
        else { return }
        projects[pi].tabs[ti].rootPane = projects[pi].tabs[ti].rootPane
            .updatingRatio(splitID: splitID, newRatio: newRatio)
    }

    // MARK: - Pane Navigation

    func focusPane(direction: PaneNavigationDirection) {
        guard let tab = selectedTab,
              let currentID = focusedPaneID ?? selectedTab?.rootPane.firstLeafID,
              let neighborID = tab.rootPane.neighborLeafID(of: currentID, direction: direction)
        else { return }
        focusedPaneID = neighborID
        tabFocusMemory[tab.id] = neighborID
        NotificationCenter.default.post(name: .agamonFocusTerminal, object: neighborID)
    }

    // MARK: - Pane / Split Actions

    func splitPane(_ paneID: UUID, axis: SplitAxis) {
        guard let projectID = selectedProjectID,
              let tabID = selectedTabID,
              let pi = projects.firstIndex(where: { $0.id == projectID }),
              let ti = projects[pi].tabs.firstIndex(where: { $0.id == tabID })
        else { return }

        let newPaneID = UUID()
        projects[pi].tabs[ti].rootPane = projects[pi].tabs[ti].rootPane
            .splitting(leafID: paneID, axis: axis, newPaneID: newPaneID)
        focusedPaneID = newPaneID
        tabFocusMemory[tabID] = newPaneID
        NotificationCenter.default.post(name: .agamonFocusTerminal, object: newPaneID)
        persist()
    }

    // MARK: - Persistence

    private var persistURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agamon")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("projects.json")
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: persistURL, options: .atomic)
    }

    // Call once at app start. Tracks modifier-key state and pane click activations.
    func startModifierMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.activeModifiers = event.modifierFlags
                .intersection([.command, .control, .option, .shift])
            return event
        }

        // Hit-test on every left click to find which AgamonTerminalView (and therefore
        // which pane) was clicked. SwiftTerm's NSView consumes mouse events so onTapGesture
        // never fires — intercepting here at the event level is the reliable alternative.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let window = event.window else { return event }
            let point = event.locationInWindow
            var view: NSView? = window.contentView?.hitTest(point)
            while let v = view {
                if let terminal = v as? AgamonTerminalView, let id = terminal.paneID {
                    self.focusedPaneID = id
                    if let tabID = self.selectedTabID { self.tabFocusMemory[tabID] = id }
                    break
                }
                view = v.superview
            }
            return event
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: persistURL),
              let saved = try? JSONDecoder().decode([Project].self, from: data)
        else { return }
        projects = saved
        selectedProjectID = projects.first?.id
        let firstTab = projects.first?.tabs.first
        selectedTabID = firstTab?.id
        focusedPaneID = firstTab?.rootPane.firstLeafID
    }
}
