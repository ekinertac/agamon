// Recursively renders a PaneNode tree as nested split views.
// Leaf nodes → TerminalPaneView. Branch nodes → HSplitView or VSplitView.
// GeometryReader is used at each branch to size children from the ratio.
// Note: ratio is immutable per render pass — drag-to-resize will require state mutation
// via AppState (not yet implemented; drag handles are a future feature).
// Related: PaneNode.swift (the tree being rendered), TerminalPaneView.swift (leaf renderer),
//          AppState.swift (splitPane mutation).

import SwiftUI

struct SplitContainerView: View {
    let pane: PaneNode

    var body: some View {
        switch pane {
        case .leaf(let id, _):
            TerminalPaneView(paneID: id)

        case .split(_, let axis, let ratio, let first, let second):
            GeometryReader { geo in
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        SplitContainerView(pane: first)
                            .frame(width: (geo.size.width - 1) * ratio)
                        splitDivider(axis: .horizontal)
                        SplitContainerView(pane: second)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        SplitContainerView(pane: first)
                            .frame(height: (geo.size.height - 1) * ratio)
                        splitDivider(axis: .vertical)
                        SplitContainerView(pane: second)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private func splitDivider(axis: SplitAxis) -> some View {
        Rectangle()
            .fill(Theme.Color.border)
            .frame(
                width:  axis == .horizontal ? 1 : nil,
                height: axis == .vertical   ? 1 : nil
            )
    }
}
