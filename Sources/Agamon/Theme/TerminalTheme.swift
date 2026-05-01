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
    let selectionBackground: NSColor?
    let palette: [SwiftTerm.Color]   // exactly 16 entries

    // MARK: - Parser

    static func parse(name: String = "Custom", _ source: String) -> TerminalTheme? {
        var bg: NSColor?
        var fg: NSColor?
        var cursor: NSColor?
        var selBg: NSColor?
        var paletteMap = [Int: NSColor]()

        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key   = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "background":            bg     = NSColor(ghosttyHex: value)
            case "foreground":            fg     = NSColor(ghosttyHex: value)
            case "cursor-color":          cursor = NSColor(ghosttyHex: value)
            case "selection-background":  selBg  = NSColor(ghosttyHex: value)
            case "palette":
                // "0=#rrggbb"
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
            selectionBackground: selBg,
            palette: swiftTermPalette
        )
    }

    // MARK: - Theme catalogue

    // Loaded once. Prefers Ghostty's bundle (463 themes); falls back to Swift-embedded
    // themes if Ghostty is not installed.
    static let all: [String: TerminalTheme] = loadAll()
    static let orderedNames: [String] = all.keys.sorted()

    private static func loadAll() -> [String: TerminalTheme] {
        guard let dir = Bundle.module.url(forResource: "Themes", withExtension: nil),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else {
            // Bundle resource missing — use embedded fallbacks
            var themes: [String: TerminalTheme] = [:]
            for (n, src) in bundledSources { if let t = parse(name: n, src) { themes[n] = t } }
            return themes
        }
        var themes: [String: TerminalTheme] = [:]
        for url in urls {
            let name = url.lastPathComponent
            if let src = try? String(contentsOf: url, encoding: .utf8),
               let t = parse(name: name, src) { themes[name] = t }
        }
        return themes
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

// MARK: - Bundled theme sources (Ghostty format)

private let bundledSources: [(String, String)] = [
    ("Catppuccin Mocha", """
background = #1e1e2e
foreground = #cdd6f4
cursor-color = #f5e0dc
selection-background = #585b70
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
"""),

    ("Dracula", """
background = #282a36
foreground = #f8f8f2
cursor-color = #f8f8f2
selection-background = #44475a
palette = 0=#21222c
palette = 1=#ff5555
palette = 2=#50fa7b
palette = 3=#f1fa8c
palette = 4=#bd93f9
palette = 5=#ff79c6
palette = 6=#8be9fd
palette = 7=#f8f8f2
palette = 8=#6272a4
palette = 9=#ff6e6e
palette = 10=#69ff94
palette = 11=#ffffa5
palette = 12=#d6acff
palette = 13=#ff92df
palette = 14=#a4ffff
palette = 15=#ffffff
"""),

    ("Tokyo Night", """
background = #1a1b26
foreground = #c0caf5
cursor-color = #c0caf5
selection-background = #364a82
palette = 0=#15161e
palette = 1=#f7768e
palette = 2=#9ece6a
palette = 3=#e0af68
palette = 4=#7aa2f7
palette = 5=#bb9af7
palette = 6=#7dcfff
palette = 7=#a9b1d6
palette = 8=#414868
palette = 9=#f7768e
palette = 10=#9ece6a
palette = 11=#e0af68
palette = 12=#7aa2f7
palette = 13=#bb9af7
palette = 14=#7dcfff
palette = 15=#c0caf5
"""),

    ("One Dark", """
background = #282c34
foreground = #abb2bf
cursor-color = #528bff
selection-background = #3e4451
palette = 0=#282c34
palette = 1=#e06c75
palette = 2=#98c379
palette = 3=#e5c07b
palette = 4=#61afef
palette = 5=#c678dd
palette = 6=#56b6c2
palette = 7=#abb2bf
palette = 8=#545862
palette = 9=#e06c75
palette = 10=#98c379
palette = 11=#e5c07b
palette = 12=#61afef
palette = 13=#c678dd
palette = 14=#56b6c2
palette = 15=#c8ccd4
"""),

    ("Nord", """
background = #2e3440
foreground = #d8dee9
cursor-color = #d8dee9
selection-background = #434c5e
palette = 0=#3b4252
palette = 1=#bf616a
palette = 2=#a3be8c
palette = 3=#ebcb8b
palette = 4=#81a1c1
palette = 5=#b48ead
palette = 6=#88c0d0
palette = 7=#e5e9f0
palette = 8=#4c566a
palette = 9=#bf616a
palette = 10=#a3be8c
palette = 11=#ebcb8b
palette = 12=#81a1c1
palette = 13=#b48ead
palette = 14=#8fbcbb
palette = 15=#eceff4
"""),

    ("Gruvbox Dark", """
background = #282828
foreground = #ebdbb2
cursor-color = #ebdbb2
selection-background = #3c3836
palette = 0=#282828
palette = 1=#cc241d
palette = 2=#98971a
palette = 3=#d79921
palette = 4=#458588
palette = 5=#b16286
palette = 6=#689d6a
palette = 7=#a89984
palette = 8=#928374
palette = 9=#fb4934
palette = 10=#b8bb26
palette = 11=#fabd2f
palette = 12=#83a598
palette = 13=#d3869b
palette = 14=#8ec07c
palette = 15=#ebdbb2
"""),

    ("Solarized Dark", """
background = #002b36
foreground = #839496
cursor-color = #839496
selection-background = #073642
palette = 0=#073642
palette = 1=#dc322f
palette = 2=#859900
palette = 3=#b58900
palette = 4=#268bd2
palette = 5=#d33682
palette = 6=#2aa198
palette = 7=#eee8d5
palette = 8=#002b36
palette = 9=#cb4b16
palette = 10=#586e75
palette = 11=#657b83
palette = 12=#839496
palette = 13=#6c71c4
palette = 14=#93a1a1
palette = 15=#fdf6e3
"""),
]
