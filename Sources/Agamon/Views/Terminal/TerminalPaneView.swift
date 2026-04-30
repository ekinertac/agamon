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
// Related: SplitContainerView.swift (positions panes), AppState.focusedPaneID (focus ring),
//          Theme.swift (font/color constants), Shortcuts.swift (⌘E wires focusFilePanel).

import SwiftUI
import SwiftTerm
import AppKit

struct TerminalPaneView: View {
    let paneID: UUID
    @Environment(AppState.self) private var appState

    var isFocused: Bool { appState.focusedPaneID == paneID }

    private var rootPath: String {
        appState.selectedProject?.rootPath
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    var body: some View {
        ZStack {
            TerminalNSViewWrapper(
                paneID: paneID,
                rootPath: rootPath,
                shellPath: appState.shellPath,
                fontFamily: appState.terminalFontFamily,
                fontSize: appState.terminalFontSize,
                isActive: isFocused
            )

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
        }
    }
}

// MARK: - AgamonTerminalView

// Subclass to start the process on first layout with a real frame, and to receive
// agamonFocusTerminal notifications for programmatic first-responder restoration.
final class AgamonTerminalView: LocalProcessTerminalView {
    var shellLaunch: (() -> Void)?
    var paneID: UUID?
    // Set to true in makeNSView when this pane is the focused one at creation time.
    // On first layout the shell starts and we immediately grab AppKit first-responder.
    var shouldAutoFocus: Bool = false
    private var didLaunch = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFocusRequest(_:)),
            name: .agamonFocusTerminal, object: nil
        )
        configureOverlayScroller()
    }

    // SwiftTerm embeds an NSScrollView internally; find it and switch to overlay style
    // so the scrollbar only appears while scrolling rather than always being visible.
    private func configureOverlayScroller() {
        func findScrollView(in view: NSView) -> NSScrollView? {
            if let sv = view as? NSScrollView { return sv }
            return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
        }
        if let sv = findScrollView(in: self) {
            sv.scrollerStyle = .overlay
            sv.autohidesScrollers = true
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
        super.layout()
        guard !didLaunch, bounds.width > 0, bounds.height > 0 else { return }
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

    func makeNSView(context: Context) -> AgamonTerminalView {
        let tv = AgamonTerminalView(frame: .zero)
        tv.paneID = paneID
        tv.shouldAutoFocus = isActive
        tv.processDelegate = context.coordinator
        applyTheme(to: tv)

        tv.shellLaunch = { [weak tv] in
            guard let tv else { return }
            tv.startProcess(executable: shellPath, args: [], environment: nil, execName: nil,
                            currentDirectory: rootPath)
            if tv.shouldAutoFocus {
                DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
            }
        }

        return tv
    }

    func updateNSView(_ nsView: AgamonTerminalView, context: Context) {
        context.coordinator.parent = self
        let currentFamily = nsView.font.familyName ?? ""
        let wantFamily = resolvedFontFamily()
        if nsView.font.pointSize != fontSize || currentFamily != wantFamily {
            nsView.font = nerdFont(size: fontSize)
        }
    }

    func makeCoordinator() -> TerminalCoordinator { TerminalCoordinator(self) }

    private func applyTheme(to tv: AgamonTerminalView) {
        let bg = NSColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
        tv.nativeBackgroundColor = bg
        tv.nativeForegroundColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
        tv.layer?.backgroundColor = bg.cgColor
        tv.caretColor = NSColor(red: 74/255, green: 158/255, blue: 1.0, alpha: 1)
        tv.getTerminal().setCursorStyle(.blinkBlock)
        tv.font = nerdFont(size: fontSize)
        tv.installColors(agnosterPalette)
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

    // Agnoster-iTerm-Theme ANSI 0-15.
    // SwiftTerm.Color(red:green:blue:) takes 16-bit values (0-65535).
    // Multiply 8-bit (0-255) by 257 to convert: 255 * 257 = 65535.
    private var agnosterPalette: [SwiftTerm.Color] {
        func c(_ r: UInt16, _ g: UInt16, _ b: UInt16) -> SwiftTerm.Color {
            SwiftTerm.Color(red: r * 257, green: g * 257, blue: b * 257)
        }
        return [
            c(  0,   0,   0),  // 0  black
            c(172,  65,  66),  // 1  red
            c( 68, 140,  68),  // 2  green
            c(193, 156,   0),  // 3  yellow
            c( 54, 109, 193),  // 4  blue
            c(133,  72, 155),  // 5  magenta
            c(  0, 160, 170),  // 6  cyan
            c(152, 152, 152),  // 7  white
            c(102, 102, 102),  // 8  bright black
            c(241, 164, 113),  // 9  bright red
            c(127, 237, 140),  // 10 bright green
            c(245, 248, 168),  // 11 bright yellow
            c(165, 191, 221),  // 12 bright blue
            c(233, 144, 210),  // 13 bright magenta
            c(  0, 227, 227),  // 14 bright cyan
            c(255, 255, 255),  // 15 bright white
        ]
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
