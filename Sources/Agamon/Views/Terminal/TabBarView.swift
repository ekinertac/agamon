// Horizontal tab bar directly above the terminal pane area.
// Each tab maps to a WorkTab with its own PaneNode split tree.
// The bottom accent line on the selected tab is the only visual "selection" indicator —
// avoids the heavy backgrounds that make tab bars feel cluttered.
// Related: WorkTab.swift (model), SplitContainerView.swift (renders the selected tab's panes),
//          AppState.swift (addTab, removeTab, renameTab).

import SwiftUI

struct TabBarView: View {
    @Environment(AppState.self) private var appState
    let project: Project

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(project.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            projectID: project.id,
                            isSelected: tab.id == appState.selectedTabID
                        )
                    }
                }
            }

            // Separator before the + button
            Rectangle().fill(Theme.Color.border).frame(width: 1).frame(maxHeight: .infinity)

            Button {
                appState.addTab(to: project.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: Theme.TabBar.height, height: Theme.TabBar.height)
            }
            .buttonStyle(.plain)
            .help("New Tab  ⌘T")
        }
        .frame(height: Theme.TabBar.height)
        .background(Theme.Color.surface)
    }
}

// MARK: - Tab Item

struct TabItemView: View {
    @Environment(AppState.self) private var appState
    let tab: WorkTab
    let projectID: UUID
    let isSelected: Bool

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editName = ""

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if isEditing {
                TextField("", text: $editName)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.FontSize.sm))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .frame(minWidth: 60)
                    .onSubmit { commitRename() }
                    .onExitCommand { isEditing = false }
            } else {
                Text(tab.name)
                    .font(.system(size: Theme.FontSize.sm, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { startEdit() }
            }

            if isHovered || isSelected {
                Button {
                    appState.removeTab(tab.id, from: projectID)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minWidth: Theme.TabBar.tabMinWidth, maxWidth: Theme.TabBar.tabMaxWidth)
        .frame(height: Theme.TabBar.height)
        .background(
            isSelected
            ? Theme.Color.background
            : (isHovered ? Theme.Color.surfaceElevated : Color.clear)
        )
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Theme.Color.accent)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            // Separator between non-selected tabs
            if !isSelected {
                Rectangle().fill(Theme.Color.border).frame(width: 1).frame(maxHeight: .infinity)
            }
        }
        .onTapGesture {
            appState.selectedTabID = tab.id
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
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
