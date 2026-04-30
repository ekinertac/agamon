// Top-level unit of organization. One project = one codebase/working context.
// Projects own their tabs and persist to disk via AppState.
// Related: WorkTab.swift (tabs within a project), AppState.swift (persistence + selection).

import Foundation

struct Project: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var rootPath: String
    var tabs: [WorkTab]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, rootPath: String) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.tabs = [WorkTab()]
        self.createdAt = Date()
    }
}
