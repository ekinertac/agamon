// Single source of truth for all design tokens: colors, spacing, radii, typography, layout constants.
// Every view reads from here — never hardcode values inline.
// Adding a new visual concept: add it here first, then use the token everywhere.
// Related: ViewStyles.swift (custom ButtonStyle/etc built on these tokens).

import SwiftUI
import AppKit

enum Theme {

    // MARK: - Color

    enum Color {
        // Base surfaces — darkest to lightest
        static let background      = SwiftUI.Color(r: 26,  g: 26,  b: 26)   // #1A1A1A  — terminal bg, main window
        static let surface         = SwiftUI.Color(r: 36,  g: 36,  b: 36)   // #242424  — sidebar, tab bar, panels
        static let surfaceElevated = SwiftUI.Color(r: 44,  g: 44,  b: 44)   // #2C2C2C  — hover states, raised cards

        // Borders — extremely subtle, dark UI doesn't need heavy lines
        static let border          = SwiftUI.Color.white.opacity(0.07)
        static let borderFocus     = SwiftUI.Color.white.opacity(0.20)

        // Text hierarchy
        static let textPrimary     = SwiftUI.Color.white
        static let textSecondary   = SwiftUI.Color.white.opacity(0.55)
        static let textTertiary    = SwiftUI.Color.white.opacity(0.28)

        // Accent — used sparingly: selected items, active indicators, primary buttons
        static let accent          = SwiftUI.Color(r: 74,  g: 158, b: 255)  // #4A9EFF
        static let accentMuted     = SwiftUI.Color(r: 74,  g: 158, b: 255).opacity(0.15)

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
        static let xs:  CGFloat = 11
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 13
        static let lg:  CGFloat = 15
        static let xl:  CGFloat = 18
    }

    // MARK: - Layout Constants

    enum Sidebar {
        static let width:    CGFloat = 220
        static let minWidth: CGFloat = 180
        static let maxWidth: CGFloat = 300
    }

    enum FilePanel {
        static let width:    CGFloat = 280
        static let minWidth: CGFloat = 220
        static let maxWidth: CGFloat = 420
    }

    enum TabBar {
        static let height:       CGFloat = 36
        static let tabMinWidth:  CGFloat = 80
        static let tabMaxWidth:  CGFloat = 200
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
}
