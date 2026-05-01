// Settings window opened by ⌘, (registered automatically by the Settings scene in AgamonApp).
// Two tabs: Appearance (dimming, font) and Terminal (shell).
// All settings are stored in UserDefaults and kept in sync through AppState's @Observable
// properties, so every terminal pane reacts to changes without a restart.
// Related: AppState.swift (owns all settings state), TerminalPaneView.swift (consumes them),
//          AgamonApp.swift (declares the Settings scene).

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush.fill") }
            TerminalSettingsView()
                .tabItem { Label("Terminal", systemImage: "terminal.fill") }
        }
        .frame(width: 460)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Inactive Pane Dimming") {
                Toggle("Dim inactive panes", isOn: $appState.dimInactivePanes)

                if appState.dimInactivePanes {
                    LabeledContent("Amount") {
                        HStack(spacing: Theme.Spacing.sm) {
                            Slider(value: $appState.inactivePaneDimAmount, in: 0.05...0.9)
                                .frame(width: 180)
                            Text("\(Int(appState.inactivePaneDimAmount * 100))%")
                                .font(.system(size: Theme.FontSize.xs, design: .monospaced))
                                .foregroundStyle(Theme.Color.textSecondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    Toggle("Only dim text (preserve background)", isOn: $appState.dimOnlyText)
                }
            }

            Section("Theme") {
                LabeledContent("Color scheme") {
                    Picker("", selection: $appState.selectedThemeName) {
                        ForEach(TerminalTheme.orderedNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .frame(width: 200)
                }
            }

            Section("Font") {
                LabeledContent("Family") {
                    TextField("e.g. JetBrainsMono Nerd Font Mono",
                              text: $appState.terminalFontFamily)
                        .frame(width: 240)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Size") {
                    HStack(spacing: Theme.Spacing.sm) {
                        Stepper(value: $appState.terminalFontSize, in: 8...32, step: 1) {
                            Text("\(Int(appState.terminalFontSize)) pt")
                                .font(.system(size: Theme.FontSize.xs, design: .monospaced))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, Theme.Spacing.md)
    }
}

// MARK: - Terminal

struct TerminalSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Shell") {
                LabeledContent("Path") {
                    TextField("/bin/zsh", text: $appState.shellPath)
                        .frame(width: 240)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Takes effect for new terminals. Existing sessions keep the shell they started with.")
                    .font(.system(size: Theme.FontSize.xs))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, Theme.Spacing.md)
    }
}
