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
    // Posted with object: UUID (paneID) when a terminal receives a BEL character.
    static let agamonBell = Notification.Name("agamonBell")
}

@Observable
final class AppState {

    // MARK: - Terminal View Cache

    // Keyed by pane UUID. Outlives SwiftUI view lifecycle so pty sessions survive tab
    // switches, new splits, and any other pane-tree restructuring that triggers makeNSView.
    var terminalViews: [UUID: AgamonTerminalView] = [:]

    // MARK: - Attention

    // Pane IDs that fired a BEL while not focused — drives sidebar badges and pane rings.
    var attentionPaneIDs: Set<UUID> = []

    func hasAttention(for projectID: UUID) -> Bool {
        attentionCount(for: projectID) > 0
    }

    func attentionCount(for projectID: UUID) -> Int {
        guard let project = projects.first(where: { $0.id == projectID }) else { return 0 }
        let leaves = project.tabs.flatMap { $0.rootPane.leafIDs() }
        return leaves.filter { attentionPaneIDs.contains($0) }.count
    }

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
        let paneID: UUID
        if let remembered = tabFocusMemory[tab.id], allLeaves.contains(remembered) {
            paneID = remembered
        } else {
            paneID = tab.rootPane.firstLeafID
        }
        focusedPaneID = paneID
        attentionPaneIDs.remove(paneID)
    }

    private func evictTerminalViews(for pane: PaneNode) {
        switch pane {
        case .leaf(let id, _):
            terminalViews.removeValue(forKey: id)
            TmuxController.shared.killSession(for: id)
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
    var openFiles: [URL] = []        // ordered list of open editor tabs
    var selectedFile: URL? = nil     // currently active editor file
    var editorPanelVisible: Bool = false
    // Bumped by focusEditor() to request first-responder on the editor text view.
    // EditorTextView observes this via its prop and grabs focus when the value changes.
    // Used instead of a notification because the editor view isn't mounted until
    // editorPanelVisible flips true, so a notification posted in the same call would
    // miss the not-yet-existing observer. SwiftUI guarantees updateNSView runs on
    // first mount with the current token, so the freshly-created view picks it up.
    var editorFocusRequestID: Int = 0
    var filePanelVisible: Bool = true
    var filePanelFocused: Bool = false
    var activeModifiers: NSEvent.ModifierFlags = []

    var showsCtrlShortcuts: Bool { activeModifiers.contains(.control) }
    var showsCmdShortcuts:  Bool { activeModifiers.contains(.command) }
    var terminalFontSize: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "terminalFontSize")
        return saved > 0 ? CGFloat(saved) : 13
    }() {
        didSet { UserDefaults.standard.set(Double(terminalFontSize), forKey: "terminalFontSize") }
    }

    var terminalFontFamily: String = UserDefaults.standard.string(forKey: "terminalFontFamily") ?? "" {
        didSet { UserDefaults.standard.set(terminalFontFamily, forKey: "terminalFontFamily") }
    }

    var terminalFontWeight: String = UserDefaults.standard.string(forKey: "terminalFontWeight") ?? "Regular" {
        didSet { UserDefaults.standard.set(terminalFontWeight, forKey: "terminalFontWeight") }
    }

    var selectedDarkThemeName: String = UserDefaults.standard.string(forKey: "selectedDarkThemeName") ?? "Catppuccin Mocha" {
        didSet { UserDefaults.standard.set(selectedDarkThemeName, forKey: "selectedDarkThemeName") }
    }

    var selectedLightThemeName: String = UserDefaults.standard.string(forKey: "selectedLightThemeName") ?? "GitHub Light Default" {
        didSet { UserDefaults.standard.set(selectedLightThemeName, forKey: "selectedLightThemeName") }
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

    func selectEditorTab(at index: Int) {
        guard editorPanelVisible, index < openFiles.count else { return }
        openFile(openFiles[index])
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
        TmuxController.shared.killSession(for: paneID)
        attentionPaneIDs.remove(paneID)
        if let newRoot = projects[pi].tabs[ti].rootPane.removingLeaf(id: paneID) {
            projects[pi].tabs[ti].rootPane = newRoot
            let survivingID = newRoot.firstLeafID
            focusedPaneID = survivingID
            tabFocusMemory[tabID] = survivingID
            attentionPaneIDs.remove(survivingID)
            persist()
            // Explicitly focus the surviving pane — re-parenting doesn't do this automatically.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .agamonFocusTerminal, object: survivingID)
            }
        } else {
            removeTab(tabID, from: projectID)
        }
    }

    // MARK: - Font Size

    func increaseFontSize() { setFontSize(min(terminalFontSize + 1, 32)) }
    func decreaseFontSize() { setFontSize(max(terminalFontSize - 1, 8)) }
    func resetFontSize()    { setFontSize(13) }

    private func setFontSize(_ size: CGFloat) {
        terminalFontSize = size  // didSet persists to UserDefaults
    }

    // MARK: - Editor Panel

    func openFile(_ url: URL) {
        if !openFiles.contains(url) {
            openFiles.append(url)
        }
        selectedFile = url
        editorPanelVisible = true
    }

    func closeFile(_ url: URL) {
        guard let idx = openFiles.firstIndex(of: url) else { return }
        openFiles.remove(at: idx)
        if selectedFile == url {
            if openFiles.isEmpty {
                selectedFile = nil
                editorPanelVisible = false
                refocusActiveTerminal()
            } else {
                selectedFile = openFiles[min(idx, openFiles.count - 1)]
            }
        }
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

    func focusEditor() {
        editorFocusRequestID &+= 1
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
        attentionPaneIDs.remove(neighborID)
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

    // Call once at app start. Tracks modifier-key state, pane click activations, and bell signals.
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
                    self.attentionPaneIDs.remove(id)
                    if let tabID = self.selectedTabID { self.tabFocusMemory[tabID] = id }
                    break
                }
                view = v.superview
            }
            return event
        }

        // Context-sensitive shortcuts: Cmd+1...9 and Cmd+Opt+Left behave differently
        // depending on whether the editor or a terminal is the first responder.
        // AgamonEditorTextView is our marker subclass — checking its type here avoids
        // false positives from sheet text fields or other NSTextView instances in the UI.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard NSApp.keyWindow?.firstResponder is AgamonEditorTextView else { return event }

            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

            // Cmd+1…9 while editor focused → select editor tab, consume event.
            // Without consume, the event would fall through to ShortcutHandler's terminal tab handler.
            if mods == .command,
               let char = event.characters, char.count == 1,
               let n = Int(char), (1...9).contains(n) {
                self.selectEditorTab(at: n - 1)
                return nil
            }

            // Cmd+Opt+Left while editor focused → return focus to the active terminal.
            // keyCode 123 = left arrow. Without consume, pane navigation would fire instead.
            if mods == [.command, .option], event.keyCode == 123 {
                self.refocusActiveTerminal()
                return nil
            }

            // Cmd+W while editor focused → close the active editor tab.
            // Without consume, ShortcutHandler's closeCurrentPane would fire instead.
            if mods == .command, event.characters == "w" {
                if let url = self.selectedFile { self.closeFile(url) }
                return nil
            }

            return event
        }

        // Cmd+Opt+Right when a terminal is focused and there is no pane to the right →
        // jump to the editor panel instead of silently doing nothing.
        // Passes through when a right-neighbor pane exists so focusPane handles it normally.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard NSApp.keyWindow?.firstResponder is AgamonTerminalView else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard mods == [.command, .option], event.keyCode == 124 /* right arrow */ else { return event }
            guard self.editorPanelVisible, let tab = self.selectedTab else { return event }
            let currentID = self.focusedPaneID ?? tab.rootPane.firstLeafID
            if tab.rootPane.neighborLeafID(of: currentID, direction: .right) == nil {
                self.focusEditor()
                return nil
            }
            return event
        }

        // Listen for BEL signals from terminals. Only record attention when the pane
        // is not already the focused one — no need to alert the user if they're watching.
        NotificationCenter.default.addObserver(
            forName: .agamonBell, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let paneID = note.object as? UUID else { return }
            guard self.focusedPaneID != paneID else { return }
            self.attentionPaneIDs.insert(paneID)
        }
    }

    func load() {
        TmuxController.shared.setup()
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
