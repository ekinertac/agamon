// Terminal color theme — parsed from Ghostty's key=value .theme format.
// A theme is bg/fg/cursor + exactly 16 ANSI palette entries. The parser accepts
// the same syntax as Ghostty so any theme from the iTerm2-Color-Schemes ghostty
// directory (or ghostty-org/ghostty themes) drops in without modification.
//
// Usage: TerminalTheme.all["Dracula"] gives the parsed theme.
//        TerminalTheme.parse(string) parses an arbitrary Ghostty theme string.
//        Apply via TerminalNSViewWrapper.applyTheme(to:) in TerminalPaneView.swift.
//
// Related: TerminalPaneView.swift (applies theme to AgamonTerminalView),
//          AppState.swift (selectedThemeName + UserDefaults persistence),
//          SettingsView.swift (theme picker UI).

import AppKit
import SwiftTerm

struct TerminalTheme {
    let name: String
    let background: NSColor
    let foreground: NSColor
    let cursor: NSColor
    let cursorText: NSColor?         // cursor-text  → caretTextColor
    let selectionBackground: NSColor? // selection-background → selectedTextBackgroundColor
    // selection-foreground has no SwiftTerm API — parsed and discarded
    let palette: [SwiftTerm.Color]   // exactly 16 entries

    // MARK: - Parser

    static func parse(name: String = "Custom", _ source: String) -> TerminalTheme? {
        var bg: NSColor?
        var fg: NSColor?
        var cursor: NSColor?
        var cursorText: NSColor?
        var selBg: NSColor?
        var paletteMap = [Int: NSColor]()

        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key   = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "background":            bg         = NSColor(ghosttyHex: value)
            case "foreground":            fg         = NSColor(ghosttyHex: value)
            case "cursor-color":          cursor     = NSColor(ghosttyHex: value)
            case "cursor-text":           cursorText = NSColor(ghosttyHex: value)
            case "selection-background":  selBg      = NSColor(ghosttyHex: value)
            case "selection-foreground":  break  // no SwiftTerm API
            case "palette":
                if let inner = value.firstIndex(of: "=") {
                    let idx = value[value.startIndex..<inner].trimmingCharacters(in: .whitespaces)
                    let hex = value[value.index(after: inner)...].trimmingCharacters(in: .whitespaces)
                    if let i = Int(idx), let c = NSColor(ghosttyHex: hex) { paletteMap[i] = c }
                }
            default: break
            }
        }

        guard let background = bg, let foreground = fg else { return nil }

        let swiftTermPalette: [SwiftTerm.Color] = (0..<16).map { i in
            (paletteMap[i] ?? foreground).toSwiftTermColor()
        }

        return TerminalTheme(
            name: name,
            background: background,
            foreground: foreground,
            cursor: cursor ?? foreground,
            cursorText: cursorText,
            selectionBackground: selBg,
            palette: swiftTermPalette
        )
    }

    // MARK: - Theme catalogue

    // ~/.config/agamon/themes/ — created on first launch if absent.
    static let userThemesDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/agamon/themes")

    // Loaded once at startup. Bundled themes first, then user themes on top
    // (same name = user wins). Restart required to pick up new user files.
    static let all: [String: TerminalTheme] = loadAll()
    static let orderedNames: [String] = all.keys.sorted()

    private static func loadAll() -> [String: TerminalTheme] {
        var themes: [String: TerminalTheme] = [:]

        // 1. Bundled themes — plain-text files in Resources/Themes/ (Ghostty key=value format)
        if let dir = Bundle.module.url(forResource: "Themes", withExtension: nil),
           let urls = try? FileManager.default.contentsOfDirectory(
               at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for url in urls {
                let name = url.lastPathComponent
                if let src = try? String(contentsOf: url, encoding: .utf8),
                   let t = parse(name: name, src) { themes[name] = t }
            }
        }

        // 2. User themes — create the directory and overlay on top of bundled
        let isNew = !FileManager.default.fileExists(atPath: userThemesDir.path)
        try? FileManager.default.createDirectory(at: userThemesDir,
                                                  withIntermediateDirectories: true)
        if isNew { writeExampleTheme() }

        if let urls = try? FileManager.default.contentsOfDirectory(
            at: userThemesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for url in urls {
                let name = url.lastPathComponent
                if let src = try? String(contentsOf: url, encoding: .utf8),
                   let t = parse(name: name, src) { themes[name] = t }
            }
        }

        return themes
    }

    private static func writeExampleTheme() {
        let dest = userThemesDir.appendingPathComponent("My Theme")
        let content = """
# My Theme — Agamon terminal color theme
# Format is identical to Ghostty themes. Rename this file to change the theme name.
# Drop any Ghostty-format .theme file (or file with no extension) into this folder
# and restart Agamon to see it in the theme picker.

# Terminal background and default text color
background = #1e1e2e
foreground = #cdd6f4

# Cursor and selection
cursor-color = #f5e0dc
selection-background = #585b70

# ANSI palette — 0-7 normal, 8-15 bright variants
palette = 0=#45475a
palette = 1=#f38ba8
palette = 2=#a6e3a1
palette = 3=#f9e2af
palette = 4=#89b4fa
palette = 5=#f5c2e7
palette = 6=#94e2d5
palette = 7=#bac2de
palette = 8=#585b70
palette = 9=#f38ba8
palette = 10=#a6e3a1
palette = 11=#f9e2af
palette = 12=#89b4fa
palette = 13=#f5c2e7
palette = 14=#94e2d5
palette = 15=#a6adc8
"""
        try? content.write(to: dest, atomically: true, encoding: .utf8)
    }
}

// MARK: - NSColor helpers

private extension NSColor {
    convenience init?(ghosttyHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red:   CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8)  & 0xFF) / 255,
            blue:  CGFloat( v        & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension NSColor {
    func toSwiftTermColor() -> SwiftTerm.Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        (usingColorSpace(.sRGB) ?? self).getRed(&r, green: &g, blue: &b, alpha: nil)
        return SwiftTerm.Color(red: UInt16(r * 65535), green: UInt16(g * 65535), blue: UInt16(b * 65535))
    }
}
