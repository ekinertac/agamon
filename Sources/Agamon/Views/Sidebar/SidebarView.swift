// Left sidebar listing all projects. Selection drives the entire terminal + file panel area.
// Uses LazyVStack + ScrollView instead of List to get full control over row appearance
// without fighting List's background and selection highlight system.
//
// Modifier hints: holding Ctrl reveals ⌃1-9 badges on project rows (project selection shortcut).
// Holding Cmd reveals ⌘O on the + button (open project shortcut).
// Related: ContentView.swift (hosts this), AppState.swift (projects + selection),
//          NewProjectSheet in ContentView.swift (creates projects).

import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.Color.border).frame(height: 1)
            projectList
            Spacer()
            footer
        }
        .background(Theme.Color.surface)
    }

    private var header: some View {
        HStack {
            Text("Projects").sectionHeader()
            Spacer()
            Button(action: appState.openProject) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .opacity(appState.showsCmdShortcuts ? 0 : 1)
                    .frame(minWidth: 20, minHeight: 20)
            }
            .buttonStyle(IconButtonStyle())
            .overlay { if appState.showsCmdShortcuts { ShortcutBadge(label: "⌘O") } }
            .animation(.easeInOut(duration: 0.12), value: appState.showsCmdShortcuts)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(appState.projects.enumerated()), id: \.element.id) { idx, project in
                    ProjectRow(
                        project: project,
                        isSelected: project.id == appState.selectedProjectID,
                        index: idx
                    )
                    .onTapGesture {
                        appState.selectProject(project.id)
                    }
                    .contextMenu {
                        Button("Rename") {}
                        Divider()
                        Button("Remove", role: .destructive) {
                            appState.removeProject(project.id)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.Color.border).frame(height: 1)
            HStack {
                Button {
                    // TODO: settings sheet
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(IconButtonStyle())
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: Project
    let isSelected: Bool
    let index: Int

    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: Theme.FontSize.sm, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                    .lineLimit(1)

                Text(URL(fileURLWithPath: project.rootPath).lastPathComponent)
                    .font(.system(size: Theme.FontSize.xs, design: .monospaced))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Ctrl held → show ⌃N shortcut hint; otherwise show selection dot
            if appState.showsCtrlShortcuts && index < 9 {
                ShortcutBadge(label: "⌃\(index + 1)")
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            } else if isSelected {
                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: 5, height: 5)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(
                    isSelected
                    ? Theme.Color.accentMuted
                    : (isHovered ? Theme.Color.surfaceElevated : Color.clear)
                )
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: appState.showsCtrlShortcuts)
        .animation(.easeInOut(duration: 0.1),  value: isHovered)
        .animation(.easeInOut(duration: 0.1),  value: isSelected)
    }
}
