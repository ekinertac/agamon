// App entry point. Declares the SwiftUI App scene and injects AppState into the environment.
// Uses .hiddenTitleBar (no unified toolbar) so content starts below the traffic-light zone.
// This prevents column backgrounds/dividers from bleeding into the title bar area.
// AppDelegate sets activation policy and window background color to match Theme.Color.background.
// Related: ContentView.swift (root layout), AppState.swift (shared state).

import SwiftUI
import AppKit

@main
struct AgamonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            AgamonCommands()
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
        .windowResizability(.contentMinSize)
    }
}

// Sets .regular activation policy so the app appears in Dock and App Switcher.
// A raw SPM executable defaults to .prohibited (background-only) without this.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        let bg = NSColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
        NSApp.windows.forEach { $0.backgroundColor = bg }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// Menu bar commands. Real actions come from AppState via @FocusedValue set in ContentView.
// ShortcutHandler (Shortcuts.swift) shadows these at the view level when a window is focused,
// so keyboard presses always call the view-level handler. Menu clicks go through here.
struct AgamonCommands: Commands {
    @FocusedValue(\.appState) var appState: AppState?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Project...") { appState?.openProject() }
                .keyboardShortcut("o", modifiers: .command)
            Button("New Tab") {
                if let id = appState?.selectedProjectID { appState?.addTab(to: id) }
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(appState?.selectedProjectID == nil)
        }

        CommandMenu("View") {
            Button("Increase Font Size") { appState?.increaseFontSize() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Decrease Font Size") { appState?.decreaseFontSize() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Font Size")    { appState?.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
        }

        CommandMenu("Tab") {
            Button("Next Tab") { appState?.nextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { appState?.prevTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])

            Divider()

            Button("Split Right") {
                let id = appState?.focusedPaneID
                    ?? appState?.selectedTab?.rootPane.firstLeafID
                if let id { appState?.splitPane(id, axis: .horizontal) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(appState?.selectedTab == nil)

            Button("Split Down") {
                let id = appState?.focusedPaneID
                    ?? appState?.selectedTab?.rootPane.firstLeafID
                if let id { appState?.splitPane(id, axis: .vertical) }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(appState?.selectedTab == nil)

            Divider()

            Button("Toggle File Panel") { appState?.toggleFilePanel() }
                .keyboardShortcut("e", modifiers: .command)
        }
    }
}
