// An independent terminal session group within a project.
// Each tab owns a PaneNode tree describing its split layout.
// "WorkTab" avoids collision with SwiftUI's Tab type introduced in macOS 15.
// Related: Project.swift (owns tabs), PaneNode.swift (split tree), SplitContainerView.swift (renderer).

import Foundation

struct WorkTab: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var rootPane: PaneNode

    init(id: UUID = UUID(), name: String = "Terminal") {
        self.id = id
        self.name = name
        self.rootPane = PaneNode()
    }
}
