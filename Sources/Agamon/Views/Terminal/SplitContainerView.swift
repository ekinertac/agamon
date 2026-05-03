// Flat layout: all pane leaves are positioned absolutely using GeometryReader + normalized
// frames from PaneNode.allLeafFrames(). Dividers are SwiftUI views with DragGesture.
//
// Why flat instead of recursive NSSplitView: NSSplitView re-parented AgamonTerminalView
// instances on every pane-tree change (new split, close split). Re-parenting triggered
// viewDidMoveToWindow + zero-size layout() → TIOCSWINSZ(0,0) → SIGWINCH → tmux redraw.
// The flat approach never re-parents: existing pane views receive only frame/size updates
// via updateNSView; makeNSView is called only for brand-new pane IDs.
//
// Related: PaneNode.swift (tree + frame math), TerminalPaneView.swift (leaf), AppState.swift.

import SwiftUI
import AppKit

struct SplitContainerView: View {
    let pane: PaneNode
    let projectRootPath: String
    @Environment(AppState.self) private var appState

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let zoomed = appState.zoomedPaneID
            ZStack {
                ForEach(pane.allLeafFrames()) { entry in
                    // When zoomed: expand the target to fill the container, hide all others.
                    // Opacity-only hide preserves pty sessions and avoids re-parenting.
                    let isTarget = zoomed == nil || entry.id == zoomed
                    let f: CGRect = (zoomed == entry.id)
                        ? CGRect(x: 0, y: 0, width: 1, height: 1)
                        : entry.frame
                    let w = max(1, f.width  * size.width)
                    let h = max(1, f.height * size.height)
                    TerminalPaneView(paneID: entry.id, projectRootPath: projectRootPath)
                        .frame(width: w, height: h)
                        .position(
                            x: f.minX * size.width  + w / 2,
                            y: f.minY * size.height + h / 2
                        )
                        .opacity(isTarget ? 1 : 0)
                        .allowsHitTesting(isTarget)
                }
                // Hide dividers while zoomed — they sit on top of the expanded pane otherwise.
                if zoomed == nil {
                    ForEach(pane.allDividerInfos()) { info in
                        PaneDividerView(info: info, containerSize: size) { ratio in
                            appState.updateSplitRatio(splitID: info.id, newRatio: ratio)
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

// MARK: - PaneDividerView

// Renders one split divider: a 1px visible line + 8px transparent hit area with drag gesture.
// Uses .position() so it layers correctly over the absolute-positioned terminal panes.
struct PaneDividerView: View {
    let info: PaneDividerInfo
    let containerSize: CGSize
    let onRatioChange: (CGFloat) -> Void

    // Normalized position captured at drag start; nil between drags.
    @State private var dragBaseNormPos: CGFloat? = nil

    // Normalized divider center position along the split axis (0-1 in whole container space).
    private var normalizedPos: CGFloat {
        info.axis == .horizontal
            ? info.splitFrame.minX + info.splitFrame.width  * info.ratio
            : info.splitFrame.minY + info.splitFrame.height * info.ratio
    }

    var body: some View {
        if info.axis == .horizontal {
            horizontalDivider
        } else {
            verticalDivider
        }
    }

    // Vertical 1px line for a left|right split.
    @ViewBuilder
    private var horizontalDivider: some View {
        let x = normalizedPos * containerSize.width
        let y = info.splitFrame.minY * containerSize.height
        let h = max(1, info.splitFrame.height * containerSize.height)
        ZStack {
            Rectangle()
                .fill(Theme.Color.border)
                .frame(width: 1, height: h)
            Rectangle()
                .fill(Color.clear)
                .frame(width: 8, height: h)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { NSCursor.resizeLeftRight.push() }
                    else        { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let base = dragBaseNormPos ?? normalizedPos
                            if dragBaseNormPos == nil { dragBaseNormPos = normalizedPos }
                            let newNorm = base + value.translation.width / containerSize.width
                            guard info.splitFrame.width > 0 else { return }
                            let newRatio = max(0.1, min(0.9,
                                (newNorm - info.splitFrame.minX) / info.splitFrame.width))
                            onRatioChange(newRatio)
                        }
                        .onEnded { _ in dragBaseNormPos = nil }
                )
        }
        .position(x: x, y: y + h / 2)
    }

    // Horizontal 1px line for a top─bottom split.
    @ViewBuilder
    private var verticalDivider: some View {
        let x = info.splitFrame.minX * containerSize.width
        let w = max(1, info.splitFrame.width * containerSize.width)
        let y = normalizedPos * containerSize.height
        ZStack {
            Rectangle()
                .fill(Theme.Color.border)
                .frame(width: w, height: 1)
            Rectangle()
                .fill(Color.clear)
                .frame(width: w, height: 8)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { NSCursor.resizeUpDown.push() }
                    else        { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let base = dragBaseNormPos ?? normalizedPos
                            if dragBaseNormPos == nil { dragBaseNormPos = normalizedPos }
                            let newNorm = base + value.translation.height / containerSize.height
                            guard info.splitFrame.height > 0 else { return }
                            let newRatio = max(0.1, min(0.9,
                                (newNorm - info.splitFrame.minY) / info.splitFrame.height))
                            onRatioChange(newRatio)
                        }
                        .onEnded { _ in dragBaseNormPos = nil }
                )
        }
        .position(x: x + w / 2, y: y)
    }
}
