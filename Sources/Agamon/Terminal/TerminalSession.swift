// Represents one live shell process attached to a pane.
// Currently spawns a direct shell via SwiftTerm's LocalProcessTerminalView.
// Future: replace with tmux pane attachment via TmuxController for session persistence.
// Related: TmuxController.swift (future session backend), TerminalPaneView.swift (renders this session),
//          PaneNode.swift (leaf nodes reference session IDs).

import Foundation
import Observation

@Observable
final class TerminalSession {
    let id: UUID
    let paneID: UUID
    private(set) var isAlive: Bool = false
    private(set) var title: String = "Terminal"
    private(set) var workingDirectory: String?

    init(paneID: UUID) {
        self.id = UUID()
        self.paneID = paneID
    }

    func markAlive() {
        isAlive = true
    }

    func markDead() {
        isAlive = false
    }

    func update(title: String) {
        self.title = title
    }

    func update(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }
}
