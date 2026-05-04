// About panel — shown via Agamon > About Agamon (CommandGroup replacing .appInfo).
// Declared as a Window scene in AgamonApp so it has its own window instance and
// can be opened with openWindow(id: "about") from menu commands.
// Icon is loaded from Bundle.module (Resources/AppIcon.icns) so it works in both
// development (swift run) and the packaged .app bundle. NSApp.applicationIconImage
// returns the generic folder icon during development because there is no .app wrapper.
// Related: AgamonApp.swift (Window scene + version constant), Shortcuts.swift (AgamonCommands).

import SwiftUI
import AppKit

private var appIcon: NSImage {
    if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
       let img = NSImage(contentsOf: url) { return img }
    return NSApp.applicationIconImage
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

            // App icon
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)

            Spacer().frame(height: 18)

            // Name
            Text("Agamon")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)

            Spacer().frame(height: 6)

            // Version
            Text("Version \(agamonVersion)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.Color.textTertiary)

            Spacer().frame(height: 14)

            // Tagline
            Text("A focused terminal for running agents")
                .font(.system(size: Theme.FontSize.sm))
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Links
            HStack(spacing: Theme.Spacing.lg) {
                Link("GitHub", destination: URL(string: "https://github.com/ekinertac/agamon")!)
                Link("Releases", destination: URL(string: "https://github.com/ekinertac/agamon/releases")!)
                Link("Issues", destination: URL(string: "https://github.com/ekinertac/agamon/issues")!)
            }
            .font(.system(size: Theme.FontSize.xs))

            Spacer().frame(height: 14)

            Text("© 2025 Agamon. Released under the MIT License.")
                .font(.system(size: Theme.FontSize.xs))
                .foregroundStyle(Theme.Color.textTertiary)

            Spacer().frame(height: 28)
        }
        .frame(width: 320, height: 340)
        .background(Theme.Color.surface)
        .preferredColorScheme(.dark)
    }
}
