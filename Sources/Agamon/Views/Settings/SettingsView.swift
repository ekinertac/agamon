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
            TextSettingsView()
                .tabItem { Label("Text", systemImage: "textformat") }
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
    @Environment(\.uiFontOffset) private var fontOffset

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
                                .font(.system(size: Theme.FontSize.xs + fontOffset, design: .monospaced))
                                .foregroundStyle(Theme.Color.textSecondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    Toggle("Only dim text (preserve background)", isOn: $appState.dimOnlyText)
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
                        .font(.system(size: Theme.FontSize.xs + fontOffset))
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

// MARK: - Text settings

struct TextSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.uiFontOffset) private var fontOffset

    // Available face names for the currently selected font family.
    private var availableWeights: [String] {
        guard !appState.terminalFontFamily.isEmpty,
              let members = NSFontManager.shared.availableMembers(
                  ofFontFamily: appState.terminalFontFamily)
        else { return ["Regular"] }
        return members.compactMap { $0[1] as? String }
    }

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Font Family") {
                FontPickerSection(selectedFamily: $appState.terminalFontFamily)
                    .frame(height: 400)
                    .listRowInsets(EdgeInsets())
            }

            Section("Editor") {
                Toggle("Line wrap", isOn: $appState.editorLineWrap)
            }

            Section("Terminal") {
                LabeledContent("Font Size") {
                    FontSizeField(value: $appState.terminalFontSize, range: 8...48)
                }
                LabeledContent("Weight") {
                    Picker("", selection: $appState.terminalFontWeight) {
                        ForEach(availableWeights, id: \.self) { face in
                            Text(face).tag(face)
                        }
                    }
                    .frame(width: 160)
                    .onChange(of: appState.terminalFontFamily) {
                        // Reset to Regular when switching font families
                        if !availableWeights.contains(appState.terminalFontWeight) {
                            appState.terminalFontWeight = availableWeights.first ?? "Regular"
                        }
                    }
                }
            }

            Section("Text Editor") {
                LabeledContent("Font Size") {
                    FontSizeField(value: $appState.editorFontSize, range: 8...48)
                }
            }

            Section("UI") {
                LabeledContent("Font Size Offset") {
                    FontSizeField(value: $appState.uiFontSizeOffset, range: -4...8)
                }
                Text("Adjusts all UI text (sidebar, tabs, file panel). Terminal and editor have their own size controls.")
                    .font(.system(size: Theme.FontSize.xs + fontOffset))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Font size field

// NSTextField + NSStepper in a single container — matches the standard macOS
// number-with-arrows spinner appearance. ↑/↓ on keyboard also work because
// NSStepper receives the key events when the text field is focused.
struct FontSizeField: NSViewRepresentable {
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat> = 8...32

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: Double(range.lowerBound))
        formatter.maximum = NSNumber(value: Double(range.upperBound))

        let tf = NSTextField()
        tf.formatter = formatter
        tf.alignment = .center
        tf.isBordered = true
        tf.bezelStyle = .roundedBezel
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.delegate = context.coordinator
        context.coordinator.textField = tf

        let stepper = NSStepper()
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.stepperChanged(_:))
        context.coordinator.stepper = stepper

        container.addSubview(tf)
        container.addSubview(stepper)
        container.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tf.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            tf.widthAnchor.constraint(equalToConstant: 52),

            stepper.leadingAnchor.constraint(equalTo: tf.trailingAnchor, constant: 2),
            stepper.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stepper.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            container.heightAnchor.constraint(equalToConstant: 22),
        ])

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.parent = self
        guard let tf = context.coordinator.textField,
              let stepper = context.coordinator.stepper else { return }
        if tf.currentEditor() == nil {
            tf.integerValue = Int(value)
        }
        stepper.doubleValue = Double(value)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FontSizeField
        weak var textField: NSTextField?
        weak var stepper: NSStepper?

        init(_ parent: FontSizeField) { self.parent = parent }

        @objc func stepperChanged(_ sender: NSStepper) {
            let v = CGFloat(sender.doubleValue)
            parent.value = v
            textField?.integerValue = Int(v)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            let raw = CGFloat(tf.doubleValue)
            let clamped = min(max(raw, parent.range.lowerBound), parent.range.upperBound)
            parent.value = clamped
            tf.integerValue = Int(clamped)
            stepper?.doubleValue = Double(clamped)
        }
    }
}

// MARK: - Font picker

// Lists only monospace font families (filtered via NSFontManager symbolic traits).
// Same searchable + keyboard-nav pattern as ThemePickerSection.
struct FontPickerSection: View {
    @Binding var selectedFamily: String
    @Environment(\.uiFontOffset) private var fontOffset
    @State private var query: String = ""
    @State private var cursorIndex: Int = 0
    @FocusState private var listFocused: Bool

    private static let families: [String] = {
        let mgr = NSFontManager.shared
        return mgr.availableFontFamilies.filter { family in
            guard let members = mgr.availableMembers(ofFontFamily: family),
                  let first = members.first,
                  let name = first[0] as? String,
                  let font = NSFont(name: name, size: 13) else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
    }()

    private var filtered: [String] {
        query.isEmpty ? Self.families
            : Self.families.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Color.textTertiary)
                    .font(.system(size: Theme.FontSize.sm + fontOffset))
                TextField("Search fonts…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.FontSize.sm + fontOffset))
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
                        ForEach(Array(filtered.enumerated()), id: \.element) { idx, family in
                            FontRow(
                                family: family,
                                isSelected: selectedFamily == family,
                                isCursor: idx == cursorIndex
                            )
                            .id(family)
                            .onTapGesture {
                                cursorIndex = idx
                                selectedFamily = family
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
                    selectedFamily = filtered[cursorIndex]
                    proxy.scrollTo(filtered[cursorIndex], anchor: .center)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard cursorIndex < filtered.count - 1 else { return .handled }
                    cursorIndex += 1
                    selectedFamily = filtered[cursorIndex]
                    proxy.scrollTo(filtered[cursorIndex], anchor: .center)
                    return .handled
                }
                .onAppear {
                    if let idx = Self.families.firstIndex(of: selectedFamily) {
                        cursorIndex = idx
                        proxy.scrollTo(selectedFamily, anchor: .center)
                    }
                    listFocused = true
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

struct FontRow: View {
    let family: String
    let isSelected: Bool
    var isCursor: Bool = false
    @Environment(\.uiFontOffset) private var fontOffset
    @State private var hovered = false

    var body: some View {
        HStack {
            Text(family)
                .font(.custom(family, size: Theme.FontSize.sm + fontOffset))
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

// MARK: - Theme picker

// Searchable list with keyboard navigation and separate dark/light bindings.
// A segmented control at the top switches which binding is active. Cursor is
// independent from the committed selection so ↑↓ applies the theme live for
// preview. Typing in the search field resets cursor to 0.
struct ThemePickerSection: View {
    @Binding var darkTheme: String
    @Binding var lightTheme: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.uiFontOffset) private var fontOffset

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
                    .font(.system(size: Theme.FontSize.sm + fontOffset))
                TextField("Search themes…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.FontSize.sm + fontOffset))
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
    @Environment(\.uiFontOffset) private var fontOffset
    @State private var hovered = false

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: Theme.FontSize.sm + fontOffset))
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
    @Environment(\.uiFontOffset) private var fontOffset

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
                    .font(.system(size: Theme.FontSize.xs + fontOffset))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, Theme.Spacing.md)
    }
}
