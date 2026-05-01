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
                fontWeight: appState.terminalFontWeight,
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

    // MARK: - Cmd+click: open URLs, file paths, directories
    // Events are intercepted in AppState.startModifierMonitor (leftMouseDown + mouseMoved
    // + flagsChanged monitors) because SwiftTerm doesn't mark those NSView methods as open.

    // Extract the token (word) from the terminal buffer at the given view-coordinate point.
    // Uses Buffer.getChar(at:) (screen coords, public API) + CharData.getCharacter() (public).
    // Stops at whitespace and common shell delimiters. Returns nil if nothing detectable found.
    func tokenAt(_ point: NSPoint) -> String? {
        let term = getTerminal()
        let buf  = term.buffer
        guard term.cols > 0, term.rows > 0 else { return nil }

        // SwiftTerm subtracts the legacy scroller width from bounds.width for column math.
        let scrollerW  = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let cellWidth  = (bounds.width - scrollerW) / CGFloat(term.cols)
        let cellHeight = bounds.height / CGFloat(term.rows)
        guard cellWidth > 0, cellHeight > 0 else { return nil }

        let col = max(0, min(term.cols - 1, Int(point.x / cellWidth)))
        let row = max(0, min(term.rows - 1, Int(point.y / cellHeight)))

        // Build the visible line as a Character array using the public getChar(at:) API.
        // getChar(at:) takes screen coordinates (row 0 = visible top) and adds yDisp internally.
        var chars: [Character] = []
        for c in 0..<term.cols {
            chars.append(buf.getChar(at: Position(col: c, row: row)).getCharacter())
        }

        // Expand left/right from click column, stopping at shell delimiters.
        let stops: Set<Character> = [" ", "\t", "\"", "'", "`", "(", ")", "[", "]",
                                      "{", "}", "|", ";", "&", "<", ">", "\\"]
        guard col < chars.count, !stops.contains(chars[col]) else { return nil }

        var left = col, right = col
        while left > 0             && !stops.contains(chars[left  - 1]) { left  -= 1 }
        while right < chars.count - 1 && !stops.contains(chars[right + 1]) { right += 1 }

        let token = String(chars[left...right]).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    func resolveAndOpen(_ token: String) {
        // 1. http/https/ftp — open in default browser
        if let url = URL(string: token),
           let scheme = url.scheme,
           ["http", "https", "ftp"].contains(scheme) {
            NSWorkspace.shared.open(url)
            return
        }

        // 2. file:// URL
        if let url = URL(string: token), url.isFileURL {
            openPath(url.path)
            return
        }

        // 3. Absolute path or ~/...
        if token.hasPrefix("/") || token.hasPrefix("~/") {
            openPath((token as NSString).expandingTildeInPath)
            return
        }

        // 4. Relative path tokens that contain a slash (e.g. src/main.swift, ./foo)
        if token.contains("/") {
            openPath((token as NSString).expandingTildeInPath)
        }
    }

    private func openPath(_ path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }
        let url = URL(fileURLWithPath: path)
        if isDir.boolValue {
            NSWorkspace.shared.open(url)   // opens in Finder
        } else {
            NotificationCenter.default.post(name: .agamonOpenFile, object: url)
        }
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
    let fontWeight: String
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
        let currentWeight = nsView.font.fontDescriptor.object(forKey: .face) as? String ?? ""
        if nsView.font.pointSize != fontSize || currentFamily != wantFamily || currentWeight != fontWeight {
            nsView.font = resolvedFont(size: fontSize)
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
        tv.font = resolvedFont(size: fontSize)
        tv.installColors(theme.palette)
        tv.appliedThemeName = themeName
        tv.getTerminal().setCursorStyle(.blinkBlock)
    }

    private func resolvedFontFamily() -> String {
        if !fontFamily.isEmpty { return fontFamily }
        return ["IosevkaTerm Nerd Font Mono", "IosevkaTermNerdFontMono-Regular", "IosevkaTerm NFM"]
            .first { NSFont(name: $0, size: 13) != nil } ?? ""
    }

    private func resolvedFont(size: CGFloat) -> NSFont {
        let family = resolvedFontFamily()
        if !family.isEmpty,
           let font = NSFontManager.shared.font(withFamily: family,
                                                traits: [], weight: 5, size: size) {
            // Apply the requested weight face if available
            if !fontWeight.isEmpty, fontWeight != "Regular" {
                let weighted = NSFontManager.shared.font(withFamily: family,
                                                         traits: [], weight: 5, size: size)
                let desc = NSFontDescriptor(fontAttributes: [
                    .family: family, .face: fontWeight
                ])
                if let wf = NSFont(descriptor: desc, size: size) { return wf }
            }
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
