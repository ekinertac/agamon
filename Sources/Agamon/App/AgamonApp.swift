// App entry point. Declares the SwiftUI App scene and injects AppState into the environment.
// Uses .hiddenTitleBar (no unified toolbar) so content starts below the traffic-light zone.
// This prevents column backgrounds/dividers from bleeding into the title bar area.
// AppDelegate sets activation policy and window background color to match Theme.Color.background.
//
// Multi-window: WindowGroup(id: "main") lets openWindow(id: "main") spawn fresh windows.
// Each window owns its AppState via WindowContainerView — projects, tabs, and focus are
// fully independent per window. settingsAppState is a dedicated instance for the Settings
// panel; changes persist to UserDefaults and are picked up by new windows on init.
//
// Auto-update: SPUStandardUpdaterController (Sparkle 2) lives on AgamonApp so its lifetime
// matches the process. SUFeedURL and SUPublicEDKey are declared in packaging/Info.plist.
// Related: ContentView.swift (root layout), AppState.swift (shared state), appcast.xml.

import SwiftUI
import AppKit
import Sparkle

let agamonVersion = "0.3.3"

@main
struct AgamonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Dedicated AppState for the Settings panel — not tied to any window.
    @State private var settingsAppState = AppState()
    // Sparkle 2 updater — lifetime matches the process. startingUpdater:true begins
    // background update checks immediately per SUAutomaticallyUpdate / SUScheduledCheckInterval.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup(id: "main") {
            WindowContainerView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            AgamonCommands()
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.updater.checkForUpdates()
                }
            }
        }

        Settings {
            SettingsView()
                .environment(settingsAppState)
                .environment(\.uiFontOffset, settingsAppState.uiFontSizeOffset)
        }
        .windowResizability(.contentMinSize)

        Window("About Agamon", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

// Owns a fresh AppState per window. Using @State here ensures each window instance
// created by openWindow(id: "main") gets its own independent AppState.
//
// load() is gated to the primary window so new windows start empty and don't
// conflict with the primary window's terminal sessions or pane UUIDs.
//
// startModifierMonitor() is called for every window; each monitor gates itself on
// event.window == hostWindow so modifier hints, click focus, and keyboard shortcuts
// are always scoped to the correct window and never bleed into inactive windows.
//
// hostWindow is set via WindowAnchorView (an NSViewRepresentable) rather than
// NSApp.keyWindow in onAppear — the latter can be nil or stale at the time onAppear
// fires, which would make every monitor guard silently fail.
struct WindowContainerView: View {
    @State private var appState = AppState()
    private static var primaryWindowClaimed = false

    var body: some View {
        ContentView()
            .environment(appState)
            .background(
                WindowAnchorView { [weak appState] window in
                    guard let appState else { return }
                    appState.hostWindow = window
                    appState.startModifierMonitor()
                    if !WindowContainerView.primaryWindowClaimed {
                        WindowContainerView.primaryWindowClaimed = true
                        appState.load()
                    }
                }
                .frame(width: 0, height: 0)
            )
    }
}

// Zero-size AppKit view whose sole job is to reliably capture the NSWindow it
// belongs to. view.window is always correct once the view is in the hierarchy;
// NSApp.keyWindow at onAppear time can be nil if the window hasn't been made key yet.
private struct WindowAnchorView: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Sets .regular activation policy so the app appears in Dock and App Switcher.
// A raw SPM executable defaults to .prohibited (background-only) without this.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        // Dynamic color so the title-bar zone matches the content background
        // in both light and dark mode without needing an appearance observer.
        let bg = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(r: 26,  g: 26,  b: 26)
                : NSColor(r: 248, g: 248, b: 248)
        }
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
    @Environment(\.openWindow) var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Agamon") { openWindow(id: "about") }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: .command)
            Divider()
            Button("Open Project...") { appState?.openProject() }
                .keyboardShortcut("o", modifiers: .command)
            Button("New Tab") {
                if let id = appState?.selectedProjectID { appState?.addTab(to: id) }
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(appState?.selectedProjectID == nil)
        }

        CommandMenu("View") {
            Button("Increase Terminal/Editor Font") { appState?.increaseFontSize() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Decrease Terminal/Editor Font") { appState?.decreaseFontSize() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Terminal/Editor Font")    { appState?.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Increase UI Font Size") { appState?.increaseUIFontSize() }
                .keyboardShortcut("+", modifiers: [.command, .shift])
            Button("Decrease UI Font Size") { appState?.decreaseUIFontSize() }
                .keyboardShortcut("-", modifiers: [.command, .shift])
            Button("Reset UI Font Size")    { appState?.resetUIFontSize() }
                .keyboardShortcut("0", modifiers: [.command, .shift])
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

            Button("Zoom Pane") {
                if appState?.editorFocused == true { appState?.toggleEditorZoom() }
                else { appState?.togglePaneZoom() }
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(appState?.selectedTab == nil && appState?.editorFocused != true)

            Divider()

            Button("Toggle File Panel") { appState?.toggleFilePanel() }
                .keyboardShortcut("e", modifiers: .command)

            Divider()

            Button("Find...") { appState?.openFind() }
                .keyboardShortcut("f", modifiers: .command)

            Button("Command Center") { appState?.openCommandCenter() }
                .keyboardShortcut("p", modifiers: .command)
        }
    }
}
