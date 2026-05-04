// Floating search bar overlaid at the top-right corner of a terminal pane.
// Shown when AppState.terminalSearchPaneID matches the pane's ID.
// Calls SwiftTerm's findNext/findPrevious/clearSearch on the cached AgamonTerminalView.
// Dismissed by: Escape (global ShortcutHandler → refocusActiveTerminal clears the ID),
// the close button, or Cmd+F toggle.
// Related: TerminalPaneView.swift (embeds this), AppState.terminalSearchPaneID,
//          TerminalPaneView.swift (owns the @State for the search query and focus).

import SwiftUI
import AppKit

struct TerminalSearchBar: View {
    @Binding var query: String
    @FocusState.Binding var isFocused: Bool
    var matchFound: Bool
    var onNext: () -> Void
    var onPrev: () -> Void
    var onClose: () -> Void

    @Environment(\.uiFontOffset) private var fontOffset

    var body: some View {
        HStack(spacing: 4) {
            TextField("Find in terminal…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.FontSize.sm + fontOffset, design: .monospaced))
                .foregroundStyle(matchFound || query.isEmpty ? Theme.Color.textPrimary : Theme.Color.danger)
                .frame(width: 190)
                .focused($isFocused)
                .onSubmit { onNext() }

            Divider()
                .frame(height: 14)
                .overlay(Theme.Color.border)

            Button(action: onPrev) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(SearchActionStyle())
            .help("Previous match (⇧↩)")

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(SearchActionStyle())
            .help("Next match (↩)")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(SearchActionStyle())
            .help("Close (⎋)")
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.Color.surface)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

// MARK: - SearchActionStyle

private struct SearchActionStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovering ? Theme.Color.textPrimary : Theme.Color.textSecondary)
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isPressed
                          ? Color.white.opacity(0.12)
                          : hovering ? Color.white.opacity(0.07) : Color.clear)
            )
            .onHover { hovering = $0 }
    }
}
