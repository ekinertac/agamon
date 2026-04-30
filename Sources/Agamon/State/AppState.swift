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
    // Bypasses SwiftUI's render cycle so it's not subject to updateNSView timing races.
    static let agamonFocusTerminal = Notification.Name("agamonFocusTerminal")
}

@Observable
final class AppState {

    // MARK: - State

    var projects: [Project] = []
    var selectedProjectID: UUID?
    var selectedTabID: UUID?
    var focusedPaneID: UUID?
    var filePanelVisible: Bool = true
    var filePanelFocused: Bool = false
    var activeModifiers: NSEvent.ModifierFlags = []

    var showsCtrlShortcuts: Bool { activeModifiers.contains(.control) }
    var showsCmdShortcuts:  Bool { activeModifiers.contains(.command) }
    var terminalFontSize: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "terminalFontSize")
        return saved > 0 ? CGFloat(saved) : 13
    }()

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
        let newIdx = (idx + 1) % project.tabs.count
        selectedTabID = project.tabs[newIdx].id
        focusedPaneID = project.tabs[newIdx].rootPane.firstLeafID
    }

    func prevTab() {
        guard let project = selectedProject,
              let idx = project.tabs.firstIndex(where: { $0.id == selectedTabID }),
              project.tabs.count > 1
        else { return }
        let newIdx = (idx - 1 + project.tabs.count) % project.tabs.count
        selectedTabID = project.tabs[newIdx].id
        focusedPaneID = project.tabs[newIdx].rootPane.firstLeafID
    }

    func selectTab(at index: Int) {
        guard let project = selectedProject, index < project.tabs.count else { return }
        selectedTabID = project.tabs[index].id
        focusedPaneID = project.tabs[index].rootPane.firstLeafID
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

    // MARK: - Pane Navigation

    func focusPane(direction: PaneNavigationDirection) {
        guard let tab = selectedTab,
              let currentID = focusedPaneID ?? selectedTab?.rootPane.firstLeafID,
              let neighborID = tab.rootPane.neighborLeafID(of: currentID, direction: direction)
        else { return }
        focusedPaneID = neighborID
        NotificationCenter.default.post(name: .agamonFocusTerminal, object: neighborID)
    }

    // MARK: - Pane / Split Actions

    func splitPane(_ paneID: UUID, axis: SplitAxis) {
        guard let projectID = selectedProjectID,
              let tabID = selectedTabID,
              let pi = projects.firstIndex(where: { $0.id == projectID }),
              let ti = projects[pi].tabs.firstIndex(where: { $0.id == tabID })
        else { return }

        projects[pi].tabs[ti].rootPane = projects[pi].tabs[ti].rootPane
            .splitting(leafID: paneID, axis: axis)
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

    // Call once at app start. Tracks modifier-key state so views can reveal shortcut hints.
    func startModifierMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.activeModifiers = event.modifierFlags
                .intersection([.command, .control, .option, .shift])
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
