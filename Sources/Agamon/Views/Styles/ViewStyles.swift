// Reusable SwiftUI styles built on Theme tokens.
// Every interactive control in the app should use one of these — never style inline.
// Adding a new control variant: add a style here, not inline in the view.
// Related: Theme.swift (tokens), used throughout Views/.

import SwiftUI

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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed
                             ? Theme.Color.textPrimary
                             : Theme.Color.textSecondary)
            .padding(Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(configuration.isPressed
                          ? Theme.Color.surfaceElevated
                          : SwiftUI.Color.clear)
            )
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
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
}
