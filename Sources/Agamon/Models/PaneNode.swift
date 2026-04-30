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

    // The leftmost/topmost leaf — used as fallback when no pane is explicitly focused.
    var firstLeafID: UUID {
        switch self {
        case .leaf(let id, _): return id
        case .split(_, _, _, let first, _): return first.firstLeafID
        }
    }

    // The rightmost/bottommost leaf.
    var lastLeafID: UUID {
        switch self {
        case .leaf(let id, _): return id
        case .split(_, _, _, _, let second): return second.lastLeafID
        }
    }

    // Path from this node down to the leaf with the given ID.
    // Each step records the split node and whether we descended into `first`.
    // Returns nil if the target is not in this subtree.
    private func pathToLeaf(id: UUID) -> [(node: PaneNode, tookFirst: Bool)]? {
        switch self {
        case .leaf(let leafID, _):
            return leafID == id ? [] : nil
        case .split(_, _, _, let first, let second):
            if let path = first.pathToLeaf(id: id) {
                return [(node: self, tookFirst: true)] + path
            }
            if let path = second.pathToLeaf(id: id) {
                return [(node: self, tookFirst: false)] + path
            }
            return nil
        }
    }

    // Returns the leaf ID that is spatially adjacent to `targetID` in the given direction,
    // or nil if `targetID` is already at that edge.
    func neighborLeafID(of targetID: UUID, direction: PaneNavigationDirection) -> UUID? {
        guard let path = pathToLeaf(id: targetID) else { return nil }
        for step in path.reversed() {
            guard case .split(_, let axis, _, let first, let second) = step.node,
                  axis == direction.axis else { continue }
            if direction.isForward && step.tookFirst  { return second.firstLeafID }
            if !direction.isForward && !step.tookFirst { return first.lastLeafID }
        }
        return nil
    }

    // Remove a leaf by ID. Returns nil only when self IS that leaf (caller promotes sibling).
    // Split nodes always return Some — either the modified subtree or the surviving sibling.
    func removingLeaf(id: UUID) -> PaneNode? {
        switch self {
        case .leaf(let leafID, _):
            return leafID == id ? nil : self
        case .split(let splitID, let axis, let ratio, let first, let second):
            let newFirst  = first.removingLeaf(id: id)
            let newSecond = second.removingLeaf(id: id)
            switch (newFirst, newSecond) {
            case (nil, _): return second   // left leaf removed → promote right subtree
            case (_, nil): return first    // right leaf removed → promote left subtree
            default: return .split(id: splitID, axis: axis, ratio: ratio,
                                   first: newFirst!, second: newSecond!)
            }
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

enum PaneNavigationDirection {
    case left, right, up, down

    var axis: SplitAxis {
        switch self {
        case .left, .right: return .horizontal
        case .up,   .down:  return .vertical
        }
    }

    // True = moving toward the "second" child in the split tree.
    var isForward: Bool {
        switch self {
        case .right, .down: return true
        case .left,  .up:   return false
        }
    }
}
