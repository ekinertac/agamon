// Settings window — ⌘, registered automatically by the Settings scene in AgamonApp.
// Two tabs: Appearance (dimming, font, theme) and Terminal (shell).
// Uses Form.formStyle(.grouped) for proper macOS HIG appearance throughout.
// The theme picker has a fixed 500px height so it scrolls independently within
// the Form's own scroll — both can coexist when the inner list has a known size.
// Related: AppState.swift (owns all settings state), TerminalPaneView.swift (consumes them),
//          AgamonApp.swift (declares the Settings scene + windowResizability).

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush.fill") }
            TerminalSettingsView()
                .tabItem { Label("Terminal", systemImage: "terminal.fill") }
        }
        .frame(minWidth: 480, minHeight: 680)
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

            Section("Font") {
                LabeledContent("Family") {
                    TextField("e.g. JetBrainsMono Nerd Font Mono",
                              text: $appState.terminalFontFamily)
                        .frame(width: 240)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Size") {
                    Stepper(value: $appState.terminalFontSize, in: 8...32, step: 1) {
                        Text("\(Int(appState.terminalFontSize)) pt")
                            .font(.system(size: Theme.FontSize.xs, design: .monospaced))
                    }
                }
            }

            Section("Theme") {
                ThemePickerSection(
                    darkTheme: $appState.selectedDarkThemeName,
                    lightTheme: $appState.selectedLightThemeName
                )
                // Fixed height: Form knows the total content size so both the outer
                // Form scroll and the inner theme list scroll work independently.
                .frame(height: 500)
                .listRowInsets(EdgeInsets())

                HStack {
                    Text("Drop Ghostty-format theme files into your themes folder and restart.")
                        .font(.system(size: Theme.FontSize.xs))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Spacer()
                    Button("Open Folder") { NSWorkspace.shared.open(TerminalTheme.userThemesDir) }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Theme picker

// Searchable list with keyboard navigation and separate dark/light bindings.
// A segmented control at the top switches which binding is active. Cursor is
// independent from the committed selection so ↑↓ applies the theme live for
// preview. Typing in the search field resets cursor to 0.
struct ThemePickerSection: View {
    @Binding var darkTheme: String
    @Binding var lightTheme: String
    @Environment(\.colorScheme) private var colorScheme

    @State private var editingDark: Bool = true
    @State private var query: String = ""
    @State private var cursorIndex: Int = 0
    @FocusState private var listFocused: Bool

    private var selection: Binding<String> { editingDark ? $darkTheme : $lightTheme }
    private var currentName: String { editingDark ? darkTheme : lightTheme }

    private var filtered: [String] {
        query.isEmpty ? TerminalTheme.orderedNames
            : TerminalTheme.orderedNames.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Dark / Light segment
            Picker("", selection: $editingDark) {
                Text("Dark").tag(true)
                Text("Light").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Color.textTertiary)
                    .font(.system(size: Theme.FontSize.sm))
                TextField("Search themes…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.FontSize.sm))
                    .onChange(of: query) { cursorIndex = 0 }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Color.textTertiary)
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
                        ForEach(Array(filtered.enumerated()), id: \.element) { idx, name in
                            ThemeRow(
                                name: name,
                                isSelected: currentName == name,
                                isCursor: idx == cursorIndex
                            )
                            .id(name)
                            .onTapGesture {
                                cursorIndex = idx
                                selection.wrappedValue = name
                            }
                        }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onKeyPress(.upArrow) {
                    guard cursorIndex > 0 else { return .handled }
                    cursorIndex -= 1
                    let name = filtered[cursorIndex]
                    selection.wrappedValue = name
                    proxy.scrollTo(name, anchor: .center)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard cursorIndex < filtered.count - 1 else { return .handled }
                    cursorIndex += 1
                    let name = filtered[cursorIndex]
                    selection.wrappedValue = name
                    proxy.scrollTo(name, anchor: .center)
                    return .handled
                }
                .onAppear {
                    editingDark = (colorScheme == .dark)
                    syncCursor(proxy: proxy)
                    listFocused = true
                }
                .onChange(of: editingDark) { syncCursor(proxy: proxy) }
                .onChange(of: query) {
                    if let first = filtered.first { proxy.scrollTo(first, anchor: .top) }
                }
            }
        }
        .background(Theme.Color.surfaceElevated.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func syncCursor(proxy: ScrollViewProxy?) {
        query = ""
        if let idx = TerminalTheme.orderedNames.firstIndex(of: currentName) {
            cursorIndex = idx
            proxy?.scrollTo(currentName, anchor: .center)
        }
    }
}

struct ThemeRow: View {
    let name: String
    let isSelected: Bool
    var isCursor: Bool = false
    @State private var hovered = false

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: Theme.FontSize.sm))
                .foregroundStyle(isSelected || isCursor ? Theme.Color.textPrimary : Theme.Color.textSecondary)
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
            isCursor   ? Theme.Color.accent.opacity(0.15) :
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
