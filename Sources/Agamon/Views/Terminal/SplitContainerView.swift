// Recursively renders a PaneNode tree as nested split views.
// Leaf nodes → TerminalPaneView. Branch nodes → NSSplitViewWrapper (AppKit NSSplitView).
//
// Why NSSplitView instead of SwiftUI HStack: NSSplitView draws its divider internally
// at exactly 1px with zero layout gap between subviews. SwiftUI ZStack/HStack approaches
// always reserve layout space for the hit area, creating a visible gap.
//
// The NSSplitViewWrapper uses NSHostingView to embed child SwiftUI SplitContainerViews
// inside NSSplitView's arranged subviews, giving AppKit full control of the divider.
//
// Related: PaneNode.swift (tree), TerminalPaneView.swift (leaf), AppState.swift (ratio updates).

import SwiftUI
import AppKit

// MARK: - SplitContainerView

struct SplitContainerView: View {
    let pane: PaneNode
    @Environment(AppState.self) private var appState

    var body: some View {
        switch pane {
        case .leaf(let id, _):
            TerminalPaneView(paneID: id)

        case .split(let splitID, let axis, let ratio, let first, let second):
            NSSplitViewWrapper(
                splitID: splitID,
                axis: axis,
                ratio: ratio,
                firstPane: first,
                secondPane: second,
                onRatioCommit: { appState.updateSplitRatio(splitID: splitID, newRatio: $0) }
            )
        }
    }
}

// MARK: - NSSplitViewWrapper

// NSViewRepresentable that hosts two SwiftUI child views inside NSSplitView.
// NSSplitView owns the divider — 1px, zero gap, native drag interaction.
struct NSSplitViewWrapper: NSViewRepresentable {
    let splitID: UUID
    let axis: SplitAxis
    let ratio: CGFloat
    let firstPane: PaneNode
    let secondPane: PaneNode
    let onRatioCommit: (CGFloat) -> Void

    @Environment(AppState.self) private var appState

    func makeNSView(context: Context) -> NSSplitView {
        let sv = AgamonSplitView()
        sv.isVertical = (axis == .horizontal)
        sv.dividerStyle = .thin
        sv.delegate = context.coordinator

        let first = NSHostingView(rootView: childView(firstPane))
        let second = NSHostingView(rootView: childView(secondPane))
        sv.addArrangedSubview(first)
        sv.addArrangedSubview(second)

        context.coordinator.splitView = sv
        return sv
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        let coord = context.coordinator

        // Refresh child content (pane tree may have changed)
        if let first = nsView.arrangedSubviews[0] as? NSHostingView<AnyView> {
            first.rootView = childView(firstPane)
        }
        if let second = nsView.arrangedSubviews[1] as? NSHostingView<AnyView> {
            second.rootView = childView(secondPane)
        }

        // Apply ratio from AppState only when the divider isn't being dragged,
        // and only when the stored ratio differs from current position.
        if !coord.isDragging {
            let total = nsView.isVertical ? nsView.bounds.width : nsView.bounds.height
            guard total > 0 else { return }
            let current = nsView.isVertical
                ? nsView.arrangedSubviews[0].frame.width
                : nsView.arrangedSubviews[0].frame.height
            let target = total * ratio
            if abs(current - target) > 1 {
                nsView.setPosition(target, ofDividerAt: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onRatioCommit: onRatioCommit) }

    private func childView(_ pane: PaneNode) -> AnyView {
        AnyView(SplitContainerView(pane: pane).environment(appState))
    }
}

// MARK: - Coordinator

final class SplitCoordinator: NSObject, NSSplitViewDelegate {
    var isDragging = false
    var onRatioCommit: (CGFloat) -> Void
    weak var splitView: NSSplitView?

    init(onRatioCommit: @escaping (CGFloat) -> Void) {
        self.onRatioCommit = onRatioCommit
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        isDragging = true
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard isDragging,
              let sv = notification.object as? NSSplitView,
              sv.arrangedSubviews.count >= 2 else { return }
        let total = sv.isVertical ? sv.bounds.width : sv.bounds.height
        let pos   = sv.isVertical
            ? sv.arrangedSubviews[0].frame.width
            : sv.arrangedSubviews[0].frame.height
        guard total > 0 else { return }
        onRatioCommit(pos / total)
        isDragging = false
    }

    func splitView(_ sv: NSSplitView,
                   constrainMinCoordinate _: CGFloat,
                   ofSubviewAt _: Int) -> CGFloat { 80 }

    func splitView(_ sv: NSSplitView,
                   constrainMaxCoordinate _: CGFloat,
                   ofSubviewAt _: Int) -> CGFloat {
        let total = sv.isVertical ? sv.bounds.width : sv.bounds.height
        return max(80, total - 80)
    }

    // Expand the 1px divider's hit area to 8px on each side.
    func splitView(_ sv: NSSplitView,
                   effectiveRect _: NSRect,
                   forDrawnRect drawnRect: NSRect,
                   ofDividerAt _: Int) -> NSRect {
        drawnRect.insetBy(dx: -8, dy: -8)
    }
}

// Make the coordinator accessible via the correct typealias
extension NSSplitViewWrapper {
    typealias Coordinator = SplitCoordinator
}

// MARK: - AgamonSplitView

// NSSplitView subclass that tints the divider to match Theme.Color.border.
final class AgamonSplitView: NSSplitView {
    override var dividerColor: NSColor {
        NSColor(white: 1.0, alpha: 0.07)
    }
}
