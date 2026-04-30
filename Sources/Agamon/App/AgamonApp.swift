// App entry point. Declares the SwiftUI App scene and injects AppState into the environment.
// Sets window chrome to unified/hidden-titlebar for a clean full-bleed dark look.
// AppDelegate is required (not just SwiftUI lifecycle) to set activation policy before launch —
// without it, a raw executable has no Dock icon and no App Switcher presence.
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
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 800)
        .commands {
            AgamonCommands()
        }
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// Menu bar commands wired to AppState actions.
struct AgamonCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {}
                .keyboardShortcut("t", modifiers: .command)
            Button("Split Horizontally") {}
                .keyboardShortcut("d", modifiers: .command)
            Button("Split Vertically") {}
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}
