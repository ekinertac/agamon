// Single source of truth for all design tokens: colors, spacing, radii, typography, layout constants.
// Every view reads from here — never hardcode values inline.
// Adding a new visual concept: add it here first, then use the token everywhere.
// Related: ViewStyles.swift (custom ButtonStyle/etc built on these tokens).

import SwiftUI
import AppKit

enum Theme {

    // MARK: - Color

    enum Color {
        // Returns a SwiftUI Color backed by a dynamic NSColor provider.
        // The block re-fires whenever macOS appearance changes, so every view using
        // these tokens automatically re-renders in light and dark mode.
        private static func adaptive(light: NSColor, dark: NSColor) -> SwiftUI.Color {
            SwiftUI.Color(NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
        }

        // Base surfaces — light: neutral grays / dark: near-black
        static let background      = adaptive(light: .init(r: 248, g: 248, b: 248),
                                               dark:  .init(r: 26,  g: 26,  b: 26))
        static let surface         = adaptive(light: .init(r: 238, g: 238, b: 238),
                                               dark:  .init(r: 36,  g: 36,  b: 36))
        static let surfaceElevated = adaptive(light: .init(r: 226, g: 226, b: 226),
                                               dark:  .init(r: 44,  g: 44,  b: 44))

        // Borders — inverted opacity source (black in light, white in dark)
        static let border          = adaptive(light: NSColor.black.withAlphaComponent(0.08),
                                               dark:  NSColor.white.withAlphaComponent(0.07))
        static let borderFocus     = adaptive(light: NSColor.black.withAlphaComponent(0.22),
                                               dark:  NSColor.white.withAlphaComponent(0.20))

        // Text hierarchy
        static let textPrimary     = adaptive(light: .init(r: 26,  g: 26,  b: 26),
                                               dark:  .init(r: 255, g: 255, b: 255))
        static let textSecondary   = adaptive(light: NSColor.black.withAlphaComponent(0.55),
                                               dark:  NSColor.white.withAlphaComponent(0.55))
        static let textTertiary    = adaptive(light: NSColor.black.withAlphaComponent(0.28),
                                               dark:  NSColor.white.withAlphaComponent(0.28))

        // Accent — follows System Settings → Appearance → Accent Color.
        static let accent          = SwiftUI.Color.accentColor
        static let accentMuted     = SwiftUI.Color.accentColor.opacity(0.15)

        // Semantic
        static let danger          = SwiftUI.Color(r: 255, g: 94,  b: 94)
        static let success         = SwiftUI.Color(r: 72,  g: 199, b: 116)
        static let warning         = SwiftUI.Color(r: 255, g: 184, b: 76)
    }

    // MARK: - Spacing (4pt grid)

    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    // MARK: - Typography

    enum FontSize {
        static let xs:    CGFloat = 14
        static let sm:    CGFloat = 15
        static let md:    CGFloat = 16
        static let lg:    CGFloat = 18
        static let xl:    CGFloat = 22
        static let badge: CGFloat = xs - 3  // shortcut hint badges, always smaller than body text
    }

    // MARK: - Layout Constants

    enum Sidebar {
        static let width:    CGFloat = 220
        static let minWidth: CGFloat = 180
        static let maxWidth: CGFloat = 300
    }

    enum EditorPanel {
        static let width:    CGFloat = 420
        static let minWidth: CGFloat = 280
        static let maxWidth: CGFloat = 640
    }

    enum FilePanel {
        static let width:    CGFloat = 240
        static let minWidth: CGFloat = 180
        static let maxWidth: CGFloat = 360
    }

    enum TabBar {
        static let height:       CGFloat = 36
        static let tabMinWidth:  CGFloat = 80
        static let tabMaxWidth:  CGFloat = 200
    }

    enum Panel {
        // Shared header height for EditorPanel and FilePanel — matches TabBar.height
        // so all column headers form a single visual row across the title bar zone.
        static let headerHeight: CGFloat = 36
    }
}

// MARK: - UI Font Offset Environment Key

// Injected at ContentView root from appState.uiFontSizeOffset.
// Every view that renders Theme.FontSize.* text adds this offset so UI text
// scales globally without touching terminal or editor content.
private struct UIFontOffsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
extension EnvironmentValues {
    var uiFontOffset: CGFloat {
        get { self[UIFontOffsetKey.self] }
        set { self[UIFontOffsetKey.self] = newValue }
    }
}

// MARK: - Helpers

extension SwiftUI.Color {
    // Convenience init from 0-255 RGB integers.
    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.init(red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

extension NSColor {
    // Bridge SwiftUI Color → NSColor for AppKit/SwiftTerm use.
    static func fromTheme(_ color: SwiftUI.Color) -> NSColor {
        NSColor(color)
    }

    // Convenience init from 0-255 RGB integers, mirrors SwiftUI Color.init(r:g:b:).
    convenience init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.init(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}
