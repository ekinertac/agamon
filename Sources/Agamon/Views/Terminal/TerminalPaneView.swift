// Wraps SwiftTerm's LocalProcessTerminalView in SwiftUI for one pane.
//
// Key timing constraint: startProcess must fire AFTER the view has its real frame.
// DispatchQueue.main.async is not reliable — it can still race with SwiftUI's layout pass.
// The correct hook is layout() override: it fires exactly when the NSView has been sized.
// AgamonTerminalView subclass uses this to gate startProcess on first non-zero layout.
//
// Related: SplitContainerView.swift (positions panes), TmuxController.swift (future backend),
//          AppState.focusedPaneID (drives focus ring), Theme.swift (font/color constants).

import SwiftUI
import SwiftTerm
import AppKit

struct TerminalPaneView: View {
    let paneID: UUID
    @Environment(AppState.self) private var appState

    var isFocused: Bool { appState.focusedPaneID == paneID }

    var body: some View {
        ZStack {
            TerminalNSViewWrapper(paneID: paneID)
                .onTapGesture { appState.focusedPaneID = paneID }

            if isFocused {
                Rectangle()
                    .stroke(Theme.Color.accent.opacity(0.5), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - AgamonTerminalView

// Subclass to start the process on first layout with a real frame.
// layout() is called by AppKit after the view is positioned and sized — guaranteed
// to have correct bounds, unlike makeNSView (frame .zero) or DispatchQueue.main.async
// (which can fire before the layout pass completes).
final class AgamonTerminalView: LocalProcessTerminalView {
    var shellLaunch: (() -> Void)?
    private var didLaunch = false

    override func layout() {
        super.layout()
        guard !didLaunch, bounds.width > 0, bounds.height > 0 else { return }
        didLaunch = true
        // Dispatch async to avoid re-entrancy into the layout system.
        DispatchQueue.main.async { [weak self] in
            self?.shellLaunch?()
        }
    }
}

// MARK: - NSViewRepresentable

struct TerminalNSViewWrapper: NSViewRepresentable {
    let paneID: UUID

    func makeNSView(context: Context) -> AgamonTerminalView {
        let tv = AgamonTerminalView(frame: .zero)
        tv.processDelegate = context.coordinator
        applyTheme(to: tv)

        tv.shellLaunch = { [weak tv] in
            guard let tv else { return }
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            tv.startProcess(executable: shell, args: [], environment: nil, execName: nil)
        }

        return tv
    }

    func updateNSView(_ nsView: AgamonTerminalView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> TerminalCoordinator { TerminalCoordinator(self) }

    private func applyTheme(to tv: AgamonTerminalView) {
        let bg = NSColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
        tv.nativeBackgroundColor = bg
        tv.nativeForegroundColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
        tv.layer?.backgroundColor = bg.cgColor
        tv.caretColor = NSColor(red: 74/255, green: 158/255, blue: 1.0, alpha: 1)
        tv.getTerminal().setCursorStyle(.blinkBlock)
        tv.font = nerdFont(size: 13)
        tv.installColors(agnosterPalette)
    }

    private func nerdFont(size: CGFloat) -> NSFont {
        let candidates = [
            "IosevkaTerm Nerd Font Mono",
            "IosevkaTermNerdFontMono-Regular",
            "IosevkaTermNerdFontMono-Medium",
            "IosevkaTerm NFM",
        ]
        for name in candidates {
            if let font = NSFont(name: name, size: size) { return font }
        }
        if let font = NSFontManager.shared.font(withFamily: "IosevkaTerm Nerd Font Mono",
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
