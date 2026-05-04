// Central keyboard shortcut registry.
//
// Two-layer approach:
//   1. AgamonCommands (menu bar) calls AppState via @FocusedValue — lets menu items work
//      when clicked AND displays the shortcut badge in the menu.
//   2. ShortcutHandler (invisible view overlay in ContentView) registers the same shortcuts
//      at the view level, which takes priority over Commands when a window is focused.
//      ⌘W is handled ONLY here because we need to shadow the system Close Window command.
//
// Related: AgamonApp.swift (Commands), ContentView.swift (embeds ShortcutHandler),
//          AppState.swift (all action methods called here).

import SwiftUI

// MARK: - FocusedValue key

struct AppStateFocusKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[AppStateFocusKey.self] }
        set { self[AppStateFocusKey.self] = newValue }
    }
}

// MARK: - ShortcutHandler

// Rendered as a zero-opacity, zero-hit-testing overlay so buttons are always in the
// view hierarchy (required for .keyboardShortcut to register) without affecting layout
// or stealing clicks.
struct ShortcutHandler: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            // Tab navigation
            Button("", action: appState.nextTab)
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("", action: appState.prevTab)
                .keyboardShortcut("[", modifiers: [.command, .shift])

            // ⌘W: shadows system "Close Window" — closes pane or tab instead
            Button("", action: appState.closeCurrentPane)
                .keyboardShortcut("w", modifiers: .command)

            // File panel toggle + focus
            Button("", action: appState.focusFilePanel)
                .keyboardShortcut("e", modifiers: .command)

            // Open project folder picker
            Button("", action: appState.openProject)
                .keyboardShortcut("o", modifiers: .command)

            // Tab selection ⌘1–⌘9
            ForEach(1...9, id: \.self) { n in
                Button("") { appState.selectTab(at: n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: .command)
            }

            // Project selection ⌃1–⌃9
            ForEach(1...9, id: \.self) { n in
                Button("") { appState.selectProject(at: n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: .control)
            }

            // Pane / editor resize ⌘⌃⌥arrow (context-aware: terminals or editor panel)
            Button("") { appState.resizeActiveContent(direction: .left) }
                .keyboardShortcut(.leftArrow,  modifiers: [.command, .control, .option])
            Button("") { appState.resizeActiveContent(direction: .right) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .control, .option])
            Button("") { appState.resizeActiveContent(direction: .up) }
                .keyboardShortcut(.upArrow,    modifiers: [.command, .control, .option])
            Button("") { appState.resizeActiveContent(direction: .down) }
                .keyboardShortcut(.downArrow,  modifiers: [.command, .control, .option])

            // Pane navigation ⌘⌥arrow
            Button("") { appState.focusPane(direction: .left) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("") { appState.focusPane(direction: .right) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("") { appState.focusPane(direction: .up) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("") { appState.focusPane(direction: .down) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            // Escape: return focus to the active terminal from anywhere (also closes terminal search)
            Button("", action: appState.refocusActiveTerminal)
                .keyboardShortcut(.escape, modifiers: [])

            // Find: Cmd+F opens terminal search overlay (editor NSTextView handles it natively)
            Button("", action: appState.openFind)
                .keyboardShortcut("f", modifiers: .command)

            // Command center
            Button("", action: appState.openCommandCenter)
                .keyboardShortcut("p", modifiers: .command)

            // Zoom focused pane to fill the container, or restore the split layout
            Button("", action: appState.togglePaneZoom)
                .keyboardShortcut(.return, modifiers: [.command, .shift])

            // Terminal / editor font size (context-aware: targets editor when focused, terminal otherwise)
            Button("", action: appState.increaseFontSize).keyboardShortcut("+", modifiers: .command)
            Button("", action: appState.increaseFontSize).keyboardShortcut("=", modifiers: .command)
            Button("", action: appState.decreaseFontSize).keyboardShortcut("-", modifiers: .command)
            Button("", action: appState.resetFontSize).keyboardShortcut("0", modifiers: .command)

            // UI font size (⌘⇧+/-)
            Button("", action: appState.increaseUIFontSize).keyboardShortcut("+", modifiers: [.command, .shift])
            Button("", action: appState.increaseUIFontSize).keyboardShortcut("=", modifiers: [.command, .shift])
            Button("", action: appState.decreaseUIFontSize).keyboardShortcut("-", modifiers: [.command, .shift])
            Button("", action: appState.resetUIFontSize).keyboardShortcut("0", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
