// Read-only NSTextView that renders `git diff HEAD -- <file>` with per-line coloring.
// Opened from DiffListView when the user taps a file in the Diff tab.
// Line coloring: + lines green, - lines red, @@ hunk headers blue, file headers dim.
// Colors are semantic constants, not theme palette slots — green always means addition
// regardless of which terminal color theme is active.
// Related: DiffListView.swift (triggers AppState.openDiff which routes here),
//          EditorPanelView.swift (detects agamon-diff:// scheme and shows this view),
//          AppState.openDiff (builds the virtual URL pushed to openFiles).

import SwiftUI
import AppKit

// MARK: - DiffEditorView

struct DiffEditorView: View {
    let fileURL:  URL
    let rootPath: String

    @State private var content = NSAttributedString()

    var body: some View {
        DiffTextView(content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { load() }
            .onChange(of: fileURL) { load() }
    }

    private func load() {
        let path = fileURL.path
        let root = rootPath
        Task.detached(priority: .userInitiated) {
            let raw  = gitOutput(["diff", "HEAD", "--", path], in: root)
            let text = raw.isEmpty ? "(no diff \u{2014} file may be untracked or unchanged)" : raw
            // Build NSAttributedString on the main thread — it is not Sendable.
            await MainActor.run { content = DiffRenderer.render(text) }
        }
    }
}

// MARK: - DiffTextView

// NSScrollView/NSTextView wrapper. Read-only; usesFindBar enables Cmd+F inline search.
struct DiffTextView: NSViewRepresentable {
    let content: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.autohidesScrollers    = true
        scrollView.scrollerStyle         = .overlay
        scrollView.drawsBackground       = true
        scrollView.backgroundColor       = NSColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)

        let size = scrollView.contentSize
        let tv   = NSTextView(frame: NSRect(origin: .zero, size: size))
        tv.minSize                  = NSSize(width: 0, height: size.height)
        tv.maxSize                  = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                             height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable    = true
        tv.isHorizontallyResizable  = false
        tv.autoresizingMask         = [.width]
        tv.textContainer?.containerSize       = NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.isRichText               = true
        tv.isEditable               = false
        tv.isSelectable             = true
        tv.backgroundColor          = NSColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
        tv.textContainerInset       = NSSize(width: Theme.Spacing.md, height: Theme.Spacing.md)
        tv.usesFindBar              = true
        tv.isIncrementalSearchingEnabled = true

        scrollView.documentView = tv
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv      = scrollView.documentView as? NSTextView,
              let storage = tv.textStorage else { return }
        storage.setAttributedString(content)
    }
}

// MARK: - DiffRenderer

struct DiffRenderer {
    private static let baseFont = NSFont.monospacedSystemFont(ofSize: Theme.FontSize.sm, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: Theme.FontSize.sm, weight: .semibold)

    private static let addColor  = NSColor(red: 0.40, green: 0.78, blue: 0.42, alpha: 1)
    private static let delColor  = NSColor(red: 0.93, green: 0.36, blue: 0.36, alpha: 1)
    private static let hunkColor = NSColor(red: 0.29, green: 0.62, blue: 1.00, alpha: 1)
    private static let dimColor  = NSColor(white: 0.38, alpha: 1)
    private static let baseColor = NSColor(white: 0.72, alpha: 1)

    static func render(_ diff: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for line in diff.components(separatedBy: "\n") {
            let (color, font) = style(for: line)
            result.append(NSAttributedString(string: line + "\n",
                                             attributes: [.foregroundColor: color, .font: font]))
        }
        return result
    }

    private static func style(for line: String) -> (NSColor, NSFont) {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return (addColor,  baseFont) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return (delColor,  baseFont) }
        if line.hasPrefix("@@")                          { return (hunkColor, boldFont) }
        if line.hasPrefix("diff ")  || line.hasPrefix("index ") ||
           line.hasPrefix("---")    || line.hasPrefix("+++")    { return (dimColor, boldFont) }
        return (baseColor, baseFont)
    }
}
