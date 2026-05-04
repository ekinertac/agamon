// Horizontal tab bar directly above the terminal pane area.
// Uses a plain HStack rather than ScrollView — macOS SwiftUI ScrollView swallows
// mouse events on its children, preventing tap/button interactions from firing.
// Tab selection uses Button(.plain) rather than onTapGesture for the same reason.
//
// Modifier hints: holding Cmd reveals ⌘1-9 on tabs and ⌘T on the new-tab button.
// Holding Cmd+Shift reveals ⌘⇧[ / ⌘⇧] hints on the first and last tab.
// Related: WorkTab.swift (model), SplitContainerView.swift (renders the selected tab's panes),
//          AppState.swift (addTab, removeTab, renameTab).

import SwiftUI

struct TabBarView: View {
    @Environment(AppState.self) private var appState
    let project: Project

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(project.tabs.enumerated()), id: \.element.id) { idx, tab in
                    TabItemView(
                        tab: tab,
                        projectID: project.id,
                        isSelected: tab.id == appState.selectedTabID,
                        index: idx
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            Rectangle().fill(Theme.Color.border).frame(width: 1).frame(maxHeight: .infinity)

            Button {
                appState.addTab(to: project.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .opacity(appState.showsCmdShortcuts ? 0 : 1)
                    .frame(width: Theme.TabBar.height, height: Theme.TabBar.height)
            }
            .buttonStyle(.plain)
            .overlay { if appState.showsCmdShortcuts { ShortcutBadge(label: "⌘T") } }
            .help("New Tab  ⌘T")
            .animation(.easeInOut(duration: 0.12), value: appState.showsCmdShortcuts)

            Rectangle().fill(Theme.Color.border).frame(width: 1).frame(maxHeight: .infinity)

            panelToggles
        }
        .frame(height: Theme.TabBar.height)
        .background(Theme.Color.surface)
    }

    private var panelToggles: some View {
        HStack(spacing: 0) {
            panelToggleButton(
                icon: "rectangle.leadinghalf.inset.filled",
                active: appState.editorPanelVisible,
                help: "Toggle Editor  ⌘⇧E"
            ) {
                withAnimation(.easeOut(duration: 0.12)) { appState.toggleEditorPanel() }
            }
            panelToggleButton(
                icon: "rectangle.trailinghalf.inset.filled",
                active: appState.filePanelVisible,
                help: "Toggle File Panel  ⌘E"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) { appState.toggleFilePanel() }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private func panelToggleButton(icon: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(active ? Theme.Color.accent : Theme.Color.textTertiary)
                .frame(width: Theme.TabBar.height - 4, height: Theme.TabBar.height)
        }
        .buttonStyle(.plain)
        .help(help)
        .animation(.easeInOut(duration: 0.12), value: active)
    }
}

// MARK: - Tab Item

struct TabItemView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.uiFontOffset) private var fontOffset
    let tab: WorkTab
    let projectID: UUID
    let isSelected: Bool
    let index: Int

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editName = ""

    var body: some View {
        Button(action: { appState.selectedTabID = tab.id }) {
            HStack(spacing: Theme.Spacing.xs) {
                if isEditing {
                    TextField("", text: $editName)
                        .textFieldStyle(.plain)
                        .font(.system(size: Theme.FontSize.sm + fontOffset))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .frame(minWidth: 60)
                        .onSubmit { commitRename() }
                        .onExitCommand { isEditing = false }
                } else {
                    Text(tab.name)
                        .font(.system(size: Theme.FontSize.sm + fontOffset, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected || isHovered ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                        .lineLimit(1)
                        .onTapGesture(count: 2) { startEdit() }
                }

                // Reserve trailing space for the shortcut badge or close button overlay
                if isHovered || isSelected || (appState.showsCmdShortcuts && index < 9) {
                    Spacer().frame(width: 20)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minWidth: Theme.TabBar.tabMinWidth, maxWidth: Theme.TabBar.tabMaxWidth)
            .frame(height: Theme.TabBar.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected
            ? Theme.Color.background
            : (isHovered ? Theme.Color.surfaceElevated : Color.clear)
        )
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle().fill(Theme.Color.accent).frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            trailingOverlay
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: appState.showsCmdShortcuts)
        .animation(.easeInOut(duration: 0.1),  value: isHovered)
        .animation(.easeInOut(duration: 0.1),  value: isSelected)
    }

    @ViewBuilder
    private var trailingOverlay: some View {
        if appState.showsCmdShortcuts && index < 9 {
            // Cmd held: show shortcut number badge
            ShortcutBadge(label: "⌘\(index + 1)")
                .padding(.trailing, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        } else if isHovered || isSelected {
            // Normal state: close button
            Button {
                appState.removeTab(tab.id, from: projectID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .transition(.opacity)
        } else {
            // Separator between non-selected, non-hovered tabs
            Rectangle()
                .fill(Theme.Color.border)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
    }

    private func startEdit() {
        editName = tab.name
        isEditing = true
    }

    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            appState.renameTab(tab.id, in: projectID, to: trimmed)
        }
        isEditing = false
    }
}
