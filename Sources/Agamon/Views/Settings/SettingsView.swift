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
                ThemePickerSection()
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

// MARK: - Theme picker

// Searchable list for 463 bundled themes. Inline in the Form section so it
// fits naturally in the grouped settings layout without a sheet.
struct ThemePickerSection: View {
    @Environment(AppState.self) private var appState
    @State private var query: String = ""

    private var filtered: [String] {
        query.isEmpty ? TerminalTheme.orderedNames
            : TerminalTheme.orderedNames.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Color.textTertiary)
                    .font(.system(size: Theme.FontSize.sm))
                TextField("Search themes…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.FontSize.sm))
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered, id: \.self) { name in
                            ThemeRow(name: name, isSelected: appState.selectedThemeName == name)
                                .id(name)
                                .onTapGesture { appState.selectedThemeName = name }
                        }
                    }
                }
                .frame(height: 220)
                .onAppear {
                    proxy.scrollTo(appState.selectedThemeName, anchor: .center)
                }
                .onChange(of: query) {
                    if let first = filtered.first { proxy.scrollTo(first, anchor: .top) }
                }
            }
        }
        .background(Theme.Color.surfaceElevated.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ThemeRow: View {
    let name: String
    let isSelected: Bool
    @State private var hovered = false

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: Theme.FontSize.sm))
                .foregroundStyle(isSelected ? Theme.Color.textPrimary : Theme.Color.textSecondary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 28)
        .background(
            isSelected ? Theme.Color.accentMuted :
            hovered    ? Theme.Color.surfaceElevated : Color.clear
        )
        .onHover { hovered = $0 }
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
