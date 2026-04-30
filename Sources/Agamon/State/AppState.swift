// Central observable state for the entire app. Injected via @Environment(AppState.self).
// All mutation goes through here — views never mutate models directly.
// Persistence: projects are written to ~/.agamon/projects.json on every change.
// Related: Project.swift, WorkTab.swift, PaneNode.swift (the models this state wraps),
//          AgamonApp.swift (injects into environment), ContentView.swift (primary consumer).

import Foundation
import Observation

@Observable
final class AppState {

    // MARK: - State

    var projects: [Project] = []
    var selectedProjectID: UUID?
    var selectedTabID: UUID?
    var focusedPaneID: UUID?
    var filePanelVisible: Bool = true

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
        }
        persist()
    }

    func selectProject(_ id: UUID) {
        selectedProjectID = id
        selectedTabID = projects.first { $0.id == id }?.tabs.first?.id
        focusedPaneID = nil
    }

    // MARK: - Tab Actions

    func addTab(to projectID: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let tab = WorkTab()
        projects[i].tabs.append(tab)
        selectedTabID = tab.id
        persist()
    }

    func removeTab(_ tabID: UUID, from projectID: UUID) {
        guard let pi = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[pi].tabs.removeAll { $0.id == tabID }
        if selectedTabID == tabID {
            selectedTabID = projects[pi].tabs.last?.id
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

    func load() {
        guard let data = try? Data(contentsOf: persistURL),
              let saved = try? JSONDecoder().decode([Project].self, from: data)
        else { return }
        projects = saved
        selectedProjectID = projects.first?.id
        selectedTabID = projects.first?.tabs.first?.id
    }
}
