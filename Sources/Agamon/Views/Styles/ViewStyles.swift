// Reusable SwiftUI styles built on Theme tokens.
// Every interactive control in the app should use one of these — never style inline.
// Adding a new control variant: add a style here, not inline in the view.
// Related: Theme.swift (tokens), used throughout Views/.

import SwiftUI
import AppKit

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? Theme.FontSize.xs : Theme.FontSize.sm, weight: .medium))
            .foregroundStyle(SwiftUI.Color.white)
            .padding(.horizontal, compact ? Theme.Spacing.sm : Theme.Spacing.md)
            .padding(.vertical,   compact ? Theme.Spacing.xs : Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(configuration.isPressed
                          ? Theme.Color.accent.opacity(0.75)
                          : Theme.Color.accent)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Theme.FontSize.sm, weight: .regular))
            .foregroundStyle(configuration.isPressed
                             ? Theme.Color.textPrimary
                             : Theme.Color.textSecondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(configuration.isPressed
                          ? Theme.Color.surfaceElevated
                          : SwiftUI.Color.clear)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed || isHovered
                             ? Theme.Color.textPrimary
                             : Theme.Color.textSecondary)
            .padding(Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(configuration.isPressed
                          ? Theme.Color.surfaceElevated
                          : (isHovered ? Theme.Color.surfaceElevated.opacity(0.7) : SwiftUI.Color.clear))
            )
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Shortcut Badge

// Shown when a modifier key is held — reveals the keyboard shortcut for a UI element.
// Splits the label into modifier symbol(s) and key character and renders them as
// two adjacent "key cap" pills (e.g. "⌘" + "1"), matching macOS shortcut conventions.
struct ShortcutBadge: View {
    let label: String

    // Everything before the last character = modifiers (⌘, ⌃, ⌥, ⇧, combinations).
    // Last character = the key itself.
    private var modifiers: String { String(label.dropLast()) }
    private var key: String       { String(label.last ?? "?") }

    var body: some View {
        HStack(spacing: 2) {
            if !modifiers.isEmpty { keyCap(modifiers) }
            keyCap(key)
        }
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.FontSize.badge, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.Color.accent)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.Color.accentMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Modifier Helpers

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: Theme.FontSize.xs, weight: .semibold))
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

extension View {
    func sectionHeader() -> some View {
        modifier(SectionHeaderStyle())
    }

    func resizeCursor(vertical: Bool = false) -> some View {
        self.onHover { inside in
            if inside { (vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() }
            else { NSCursor.pop() }
        }
    }
}
