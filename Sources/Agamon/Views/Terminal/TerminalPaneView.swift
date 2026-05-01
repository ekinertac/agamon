// Wraps SwiftTerm's LocalProcessTerminalView in SwiftUI for one pane.
//
// Key timing constraint: startProcess must fire AFTER the view has its real frame.
// The correct hook is layout() override: it fires exactly when the NSView has been sized.
// AgamonTerminalView subclass uses this to gate startProcess on first non-zero layout.
//
// Focus restoration: when the file panel is dismissed, AppState posts agamonFocusTerminal
// with the target paneID. AgamonTerminalView receives it and calls makeFirstResponder on
// itself directly — bypassing SwiftUI's render cycle which is prone to timing races.
//
// Scrollbar: SwiftTerm adds a bare NSScroller (not NSScrollView) directly as a subview,
// hardcoded to .legacy style. setupScroller() re-applies that style AFTER didAddSubview
// returns, so forcing .overlay there gets clobbered. Instead we hide the scroller
// entirely — SwiftTerm's updateScroller() only touches isEnabled/value/knobProportion,
// never isHidden, so the hide sticks. Mouse-wheel/keyboard scrolling still works.
// Gap fix: SwiftTerm's getEffectiveWidth always subtracts scrollerWidth from bounds.width.
// To compensate, TerminalNSViewWrapper is given a frame that's scrollerWidth pixels wider
// than its container (negative trailing padding). SwiftTerm then fills the full visible
// width with text columns. The ZStack clips the overflow so nothing bleeds out.
//
// Related: SplitContainerView.swift (positions panes), AppState.focusedPaneID (focus ring),
//          Theme.swift (font/color constants), Shortcuts.swift (⌘E wires focusFilePanel).

import SwiftUI
import SwiftTerm
import AppKit

struct TerminalPaneView: View {
    let paneID: UUID
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var isFocused: Bool { appState.focusedPaneID == paneID }

    private var activeThemeName: String {
        colorScheme == .dark ? appState.selectedDarkThemeName : appState.selectedLightThemeName
    }

    private var rootPath: String {
        appState.selectedProject?.rootPath
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    // Legacy scroller width — SwiftTerm subtracts this from bounds.width regardless of
    // visibility. We extend the terminal frame by this amount so text fills the container.
    private var scrollerReservedWidth: CGFloat {
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    }

    var body: some View {
        ZStack {
            TerminalNSViewWrapper(
                paneID: paneID,
                rootPath: rootPath,
                shellPath: appState.shellPath,
                fontFamily: appState.terminalFontFamily,
                fontSize: appState.terminalFontSize,
                isActive: isFocused,
                themeName: activeThemeName
            )
            .padding(.trailing, -scrollerReservedWidth)

            if !isFocused && appState.dimInactivePanes && appState.inactivePaneDimAmount > 0 {
                if appState.dimOnlyText {
                    // Multiply blend: near-black background barely changes; bright text dims visibly.
                    Color(white: 1.0 - appState.inactivePaneDimAmount * 0.7)
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                } else {
                    Color.black.opacity(appState.inactivePaneDimAmount * 0.8)
                        .allowsHitTesting(false)
                }
            }

            if appState.attentionPaneIDs.contains(paneID) {
                Rectangle()
                    .strokeBorder(Color(red: 1.0, green: 0.72, blue: 0.1).opacity(0.85), lineWidth: 2)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.2), value: appState.attentionPaneIDs.contains(paneID))
            }
        }
        .clipped()
    }
}

// MARK: - AgamonTerminalView

// Subclass to start the process on first layout with a real frame, and to receive
// agamonFocusTerminal notifications for programmatic first-responder restoration.
final class AgamonTerminalView: LocalProcessTerminalView {
    var shellLaunch: (() -> Void)?
    var paneID: UUID?
    var appliedThemeName: String = ""
    // Set to true in makeNSView when this pane is the focused one at creation time.
    // On first layout the shell starts and we immediately grab AppKit first-responder.
    var shouldAutoFocus: Bool = false
    private var didLaunch = false
    // Last size sent to SwiftTerm via super.layout(). Guards against TIOCSWINSZ(0,0)
    // during re-parenting transitions and suppresses same-size repeat calls.
    private var lastLayoutSize: CGSize = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Remove first to avoid duplicate observers when a cached view is re-parented.
        NotificationCenter.default.removeObserver(self, name: .agamonFocusTerminal, object: nil)
        guard window != nil else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFocusRequest(_:)),
            name: .agamonFocusTerminal, object: nil
        )
        // Force a full redraw after re-parenting into a new NSHostingView.
        // SwiftTerm's CALayer needs an explicit invalidation — the normal AppKit dirty-rect
        // mechanism doesn't catch this because the layer was valid when the view was detached.
        if didLaunch {
            DispatchQueue.main.async { [weak self] in
                self?.needsDisplay = true
                self?.layer?.setNeedsDisplay()
            }
        }
    }

    // TerminalView.bell(source:) is open — override to post a notification so AppState
    // can record attention for this pane without coupling the view directly to AppState.
    override func bell(source: SwiftTerm.Terminal) {
        super.bell(source: source)
        guard let id = paneID else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .agamonBell, object: id)
        }
    }

    // SwiftTerm adds a bare NSScroller (not NSScrollView) directly as a subview.
    // Hide it: setupScroller() re-applies .legacy after this hook so style overrides
    // don't stick, but isHidden is never touched by SwiftTerm's update path.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if let scroller = subview as? NSScroller {
            scroller.isHidden = true
            scroller.alphaValue = 0
        }
    }

    @objc private func handleFocusRequest(_ note: Notification) {
        guard let id = note.object as? UUID, id == paneID else { return }
        window?.makeFirstResponder(self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        let newSize = bounds.size
        // Guard before super.layout() — a zero-size call during re-parenting sends
        // TIOCSWINSZ(0,0) which resets the tmux session. Same-size calls are no-ops.
        guard newSize.width > 0, newSize.height > 0, newSize != lastLayoutSize else { return }
        lastLayoutSize = newSize
        super.layout()
        guard !didLaunch else { return }
        didLaunch = true
        DispatchQueue.main.async { [weak self] in
            self?.shellLaunch?()
        }
    }
}

// MARK: - NSViewRepresentable

struct TerminalNSViewWrapper: NSViewRepresentable {
    let paneID: UUID
    let rootPath: String
    let shellPath: String
    let fontFamily: String
    let fontSize: CGFloat
    let isActive: Bool
    let themeName: String

    @Environment(AppState.self) private var appState

    func makeNSView(context: Context) -> AgamonTerminalView {
        // Return cached view — preserves the running pty session across SwiftUI identity
        // resets (tab switch, new split, pane tree restructure).
        // removeFromSuperview first: clears AutoLayout constraints tied to the old
        // NSHostingView so the new one gets a clean slate and doesn't fight stale constraints.
        if let cached = appState.terminalViews[paneID] {
            cached.removeFromSuperview()
            cached.processDelegate = context.coordinator
            return cached
        }

        let tv = AgamonTerminalView(frame: .zero)
        tv.paneID = paneID
        tv.shouldAutoFocus = isActive
        tv.processDelegate = context.coordinator
        applyTheme(to: tv)

        tv.shellLaunch = { [weak tv] in
            guard let tv else { return }
            let (exec, args): (String, [String])
            let tmux = TmuxController.shared
            if tmux.isAvailable, let id = tv.paneID {
                // Use tmux: new-session -A reattaches the existing session if it exists,
                // creating a new one otherwise. Session names are stable (pane UUID is persisted).
                (exec, args) = tmux.attachArgs(for: id, workingDir: rootPath)
            } else {
                (exec, args) = (shellPath, [])
            }
            tv.startProcess(executable: exec, args: args, environment: nil, execName: nil,
                            currentDirectory: rootPath)
            if tv.shouldAutoFocus {
                DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
            }
        }

        appState.terminalViews[paneID] = tv
        return tv
    }

    func updateNSView(_ nsView: AgamonTerminalView, context: Context) {
        context.coordinator.parent = self
        let currentFamily = nsView.font.familyName ?? ""
        let wantFamily = resolvedFontFamily()
        if nsView.font.pointSize != fontSize || currentFamily != wantFamily {
            nsView.font = nerdFont(size: fontSize)
        }
        if nsView.appliedThemeName != themeName {
            applyTheme(to: nsView)
        }
    }

    func makeCoordinator() -> TerminalCoordinator { TerminalCoordinator(self) }

    private func applyTheme(to tv: AgamonTerminalView) {
        let theme = TerminalTheme.all[themeName]
            ?? TerminalTheme.all["Catppuccin Mocha"]
            ?? TerminalTheme.all.values.first!
        tv.nativeBackgroundColor = theme.background
        tv.nativeForegroundColor = theme.foreground
        tv.layer?.backgroundColor = theme.background.cgColor
        tv.caretColor = theme.cursor
        tv.caretTextColor = theme.cursorText
        if let selBg = theme.selectionBackground { tv.selectedTextBackgroundColor = selBg }
        tv.font = nerdFont(size: fontSize)
        tv.installColors(theme.palette)
        tv.appliedThemeName = themeName
        tv.getTerminal().setCursorStyle(.blinkBlock)
    }

    private func resolvedFontFamily() -> String {
        if !fontFamily.isEmpty { return fontFamily }
        let defaults = ["IosevkaTerm Nerd Font Mono", "IosevkaTermNerdFontMono-Regular",
                        "IosevkaTerm NFM"]
        return defaults.first { NSFont(name: $0, size: 13) != nil } ?? ""
    }

    private func nerdFont(size: CGFloat) -> NSFont {
        // Try user-specified family first, then built-in candidates, then system fallback.
        let candidates = fontFamily.isEmpty
            ? ["IosevkaTerm Nerd Font Mono", "IosevkaTermNerdFontMono-Regular",
               "IosevkaTermNerdFontMono-Medium", "IosevkaTerm NFM"]
            : [fontFamily]
        for name in candidates {
            if let font = NSFont(name: name, size: size) { return font }
        }
        if !fontFamily.isEmpty,
           let font = NSFontManager.shared.font(withFamily: fontFamily,
                                                traits: [], weight: 5, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

}

// MARK: - Coordinator

final class TerminalCoordinator: NSObject, LocalProcessTerminalViewDelegate {
    var parent: TerminalNSViewWrapper

    init(_ parent: TerminalNSViewWrapper) {
        self.parent = parent
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {}
}
