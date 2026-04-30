// Recursive tree describing split layout within a tab.
// Leaves hold a reference to a terminal session; branches encode a split axis + ratio.
// The `indirect` enum makes arbitrary nesting cheap — no heap allocation per level.
// Related: WorkTab.swift (owns rootPane), SplitContainerView.swift (renders the tree),
//          TerminalSession.swift (leaf sessions), AppState.swift (mutates the tree for splits).

import Foundation

indirect enum PaneNode: Identifiable, Codable, Hashable {
    case leaf(id: UUID, sessionID: UUID?)
    case split(id: UUID, axis: SplitAxis, ratio: CGFloat, first: PaneNode, second: PaneNode)

    var id: UUID {
        switch self {
        case .leaf(let id, _):            return id
        case .split(let id, _, _, _, _):  return id
        }
    }

    // Default: single empty leaf pane.
    init() {
        self = .leaf(id: UUID(), sessionID: nil)
    }

    // All leaf IDs in depth-first order — used to sync sessions when layout changes.
    func leafIDs() -> [UUID] {
        switch self {
        case .leaf(let id, _):
            return [id]
        case .split(_, _, _, let first, let second):
            return first.leafIDs() + second.leafIDs()
        }
    }

    // Split a leaf into two, keeping the original as `first`.
    func splitting(leafID: UUID, axis: SplitAxis, ratio: CGFloat = 0.5) -> PaneNode {
        switch self {
        case .leaf(let id, let sessionID) where id == leafID:
            return .split(
                id: UUID(),
                axis: axis,
                ratio: ratio,
                first: .leaf(id: id, sessionID: sessionID),
                second: .leaf(id: UUID(), sessionID: nil)
            )
        case .leaf:
            return self
        case .split(let id, let a, let r, let first, let second):
            return .split(
                id: id, axis: a, ratio: r,
                first:  first.splitting(leafID: leafID, axis: axis, ratio: ratio),
                second: second.splitting(leafID: leafID, axis: axis, ratio: ratio)
            )
        }
    }
}

enum SplitAxis: String, Codable, Hashable {
    case horizontal   // side by side (│)
    case vertical     // stacked     (─)
}
