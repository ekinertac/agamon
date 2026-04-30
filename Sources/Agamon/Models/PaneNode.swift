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

    // Compute normalized (0-1) frames for every leaf in the tree.
    // Horizontal split axis = left│right; vertical = top─bottom.
    // Origin is top-left, matching SwiftUI's coordinate system.
    func allLeafFrames(in frame: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1))
        -> [(id: UUID, frame: CGRect)]
    {
        switch self {
        case .leaf(let id, _):
            return [(id, frame)]
        case .split(_, let axis, let ratio, let first, let second):
            let (f, s) = childFrames(axis: axis, ratio: ratio, in: frame)
            return first.allLeafFrames(in: f) + second.allLeafFrames(in: s)
        }
    }

    private func childFrames(axis: SplitAxis, ratio: CGFloat,
                              in frame: CGRect) -> (CGRect, CGRect) {
        if axis == .horizontal {
            let w = frame.width * ratio
            return (
                CGRect(x: frame.minX,     y: frame.minY, width: w,              height: frame.height),
                CGRect(x: frame.minX + w, y: frame.minY, width: frame.width - w, height: frame.height)
            )
        } else {
            let h = frame.height * ratio
            return (
                CGRect(x: frame.minX, y: frame.minY,     width: frame.width, height: h),
                CGRect(x: frame.minX, y: frame.minY + h, width: frame.width, height: frame.height - h)
            )
        }
    }

    // Returns the visually nearest leaf ID in the given direction.
    // Scoring: distance-in-direction + perpendicular-center-misalignment.
    // Lower score = better match, so the most-aligned adjacent pane always wins.
    func neighborLeafID(of targetID: UUID, direction: PaneNavigationDirection) -> UUID? {
        let allFrames = allLeafFrames()
        guard let currentEntry = allFrames.first(where: { $0.id == targetID }) else { return nil }
        let cur = currentEntry.frame
        let ε: CGFloat = 0.001

        var best: (id: UUID, score: CGFloat)?
        for entry in allFrames where entry.id != targetID {
            let f = entry.frame
            let score: CGFloat
            switch direction {
            case .left  where f.maxX <= cur.minX + ε:
                score = (cur.midX - f.midX) + abs(cur.midY - f.midY)
            case .right where f.minX >= cur.maxX - ε:
                score = (f.midX - cur.midX) + abs(cur.midY - f.midY)
            case .up    where f.maxY <= cur.minY + ε:
                score = (cur.midY - f.midY) + abs(cur.midX - f.midX)
            case .down  where f.minY >= cur.maxY - ε:
                score = (f.midY - cur.midY) + abs(cur.midX - f.midX)
            default: continue
            }
            if best == nil || score < best!.score { best = (entry.id, score) }
        }
        return best?.id
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
