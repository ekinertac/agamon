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

    @Environment(AppState.self) private var appState
    @State private var content = NSAttributedString()

    var body: some View {
        DiffTextView(content: content,
                     onFocusChange: { focused in appState.editorFocused = focused })
            .onChange(of: appState.editorFontSize) { load() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { load() }
            .onChange(of: fileURL) { load() }
    }

    private func load() {
        // Use a path relative to rootPath so git resolves it correctly even when the
        // project root is a subdirectory of a larger git repository.
        let relPath: String = {
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            return fileURL.path.hasPrefix(prefix)
                ? String(fileURL.path.dropFirst(prefix.count))
                : fileURL.path
        }()
        let root     = rootPath
        let fontSize = appState.editorFontSize
        Task.detached(priority: .userInitiated) {
            let raw  = gitOutput(["diff", "HEAD", "--", relPath], in: root)
            let text = raw.isEmpty ? "(no diff \u{2014} file may be untracked or unchanged)" : raw
            // Build NSAttributedString on the main thread — it is not Sendable.
            await MainActor.run { content = DiffRenderer.render(text, fontSize: fontSize) }
        }
    }
}

// MARK: - AgamonDiffTextView

// Marker subclass identical in purpose to AgamonEditorTextView: the NSEvent monitor in
// AppState.startModifierMonitor() checks firstResponder type to decide whether Cmd+W
// should close an editor tab or a terminal pane. Using a plain NSTextView would be
// invisible to that check, causing Cmd+W to fall through to closeCurrentPane instead.
final class AgamonDiffTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let r = super.becomeFirstResponder()
        if r { onFocusChange?(true) }
        return r
    }

    override func resignFirstResponder() -> Bool {
        let r = super.resignFirstResponder()
        if r { onFocusChange?(false) }
        return r
    }
}

// MARK: - DiffTextView

// NSScrollView/AgamonDiffTextView wrapper. Read-only; usesFindBar enables Cmd+F inline search.
struct DiffTextView: NSViewRepresentable {
    let content: NSAttributedString
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.autohidesScrollers    = true
        scrollView.scrollerStyle         = .overlay
        scrollView.drawsBackground       = true
        scrollView.backgroundColor       = NSColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)

        let size = scrollView.contentSize
        let tv   = AgamonDiffTextView(frame: NSRect(origin: .zero, size: size))
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
        tv.onFocusChange            = onFocusChange

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
    private static let addColor  = NSColor(red: 0.40, green: 0.78, blue: 0.42, alpha: 1)
    private static let delColor  = NSColor(red: 0.93, green: 0.36, blue: 0.36, alpha: 1)
    private static let hunkColor = NSColor(red: 0.29, green: 0.62, blue: 1.00, alpha: 1)
    private static let dimColor  = NSColor(white: 0.38, alpha: 1)
    private static let baseColor = NSColor(white: 0.72, alpha: 1)

    static func render(_ diff: String, fontSize: CGFloat = Theme.FontSize.sm) -> NSAttributedString {
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let result = NSMutableAttributedString()
        for line in diff.components(separatedBy: "\n") {
            let (color, font) = style(for: line, baseFont: baseFont, boldFont: boldFont)
            result.append(NSAttributedString(string: line + "\n",
                                             attributes: [.foregroundColor: color, .font: font]))
        }
        return result
    }

    private static func style(for line: String, baseFont: NSFont, boldFont: NSFont) -> (NSColor, NSFont) {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return (addColor,  baseFont) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return (delColor,  baseFont) }
        if line.hasPrefix("@@")                          { return (hunkColor, boldFont) }
        if line.hasPrefix("diff ")  || line.hasPrefix("index ") ||
           line.hasPrefix("---")    || line.hasPrefix("+++")    { return (dimColor, boldFont) }
        return (baseColor, baseFont)
    }
}
