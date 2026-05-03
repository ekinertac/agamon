// Lightweight inline editor for files the agent produces.
// Wraps NSTextView (AppKit) because SwiftUI's TextEditor lacks: monospace font control,
// disabling smart quotes/dashes, and proper dark background without fighting system appearance.
// Cmd+S saves. isDirty is lifted to the parent (EditorPanelView) so the dirty state persists
// across tab switches without re-loading or losing unsaved edits.
// Related: EditorPanelView.swift (hosts this, owns content + dirty state, renders the tab bar),
//          FileTreeView.swift (double-click triggers appState.openFile which shows this).

import SwiftUI
import AppKit

struct FileEditorView: View {
    let url: URL
    @Binding var content: String
    @Binding var isDirty: Bool
    var loadError: String? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var saveError: String?

    private var activeTheme: TerminalTheme? {
        let name = colorScheme == .dark ? appState.selectedDarkThemeName : appState.selectedLightThemeName
        return TerminalTheme.all[name] ?? TerminalTheme.all.values.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar: only visible when there's something to show
            if isDirty || saveError != nil || loadError != nil {
                statusBar
                Rectangle().fill(Theme.Color.border).frame(height: 1)
            }
            EditorTextView(
                text: $content,
                onChange: { isDirty = true },
                focusRequestID: appState.editorFocusRequestID,
                fileExtension: url.pathExtension,
                lineWrap: appState.editorLineWrap,
                themePalette: activeTheme?.rawPalette ?? [],
                themeForeground: activeTheme?.foreground ?? NSColor(white: 0.85, alpha: 1),
                themeBackground: activeTheme?.background ?? NSColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1),
                onFocusChange: { focused in appState.editorFocused = focused }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Hidden button so Cmd+S fires even when the explicit Save button isn't rendered
        .background {
            Button("") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
        }
        .onChange(of: url) { saveError = nil }
    }

    private var statusBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let error = saveError ?? loadError {
                Text(error)
                    .font(.system(size: Theme.FontSize.xs))
                    .foregroundStyle(Theme.Color.danger)
                    .lineLimit(1)
            } else {
                Text("Unsaved changes")
                    .font(.system(size: Theme.FontSize.xs))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
            if isDirty {
                Button("Save") { save() }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface)
    }

    private func save() {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - AgamonEditorTextView

// Marker subclass used by the NSEvent keyDown monitor in AppState to distinguish
// the editor text view from terminals (AgamonTerminalView) and sheet text fields.
// Also reports first-responder changes via onFocusChange so AppState can gate
// the terminal search path in openFind() (Cmd+F) when the editor has keyboard focus.
final class AgamonEditorTextView: NSTextView {
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

    // Remove one level of indentation (one tab or up to 4 spaces) from every line
    // that intersects the current selection. Uses shouldChangeText/didChangeText so
    // undo is registered automatically; all removals are grouped into one undo step.
    override func insertBacktab(_ sender: Any?) {
        guard let storage = textStorage, isEditable else {
            super.insertBacktab(sender)
            return
        }

        let sel   = selectedRange()
        let nsStr = storage.string as NSString
        let linesRange = nsStr.lineRange(for: sel)

        // Collect (lineStart, charsToRemove) for every line in the selection range.
        var removals: [(start: Int, count: Int)] = []
        var pos = linesRange.location
        while pos < NSMaxRange(linesRange) {
            let lr   = nsStr.lineRange(for: NSRange(location: pos, length: 0))
            let line = nsStr.substring(with: lr)
            var n = 0
            if line.hasPrefix("\t") {
                n = 1
            } else {
                for ch in line.unicodeScalars {
                    guard ch == " " && n < 4 else { break }
                    n += 1
                }
            }
            removals.append((start: lr.location, count: n))
            if lr.length == 0 { break }
            pos = NSMaxRange(lr)
        }

        guard removals.contains(where: { $0.count > 0 }) else { return }

        // Apply forward, tracking cumulative offset so ranges stay valid after each deletion.
        undoManager?.beginUndoGrouping()
        var offset = 0
        var removedBeforeCursor = 0
        var totalRemoved = 0
        for (start, count) in removals {
            guard count > 0 else { continue }
            let loc   = start - offset
            let range = NSRange(location: loc, length: count)
            if shouldChangeText(in: range, replacementString: "") {
                storage.replaceCharacters(in: range, with: "")
                didChangeText()
                offset += count
                totalRemoved += count
                if start < sel.location {
                    removedBeforeCursor += min(start + count, sel.location) - start
                }
            }
        }
        undoManager?.endUndoGrouping()

        let newLoc = max(linesRange.location, sel.location - removedBeforeCursor)
        let newLen = max(0, sel.length - (totalRemoved - removedBeforeCursor))
        setSelectedRange(NSRange(location: newLoc, length: newLen))
    }
}

// MARK: - NSTextView wrapper

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    var onChange: () -> Void
    // Monotonic counter from AppState. Whenever it changes, updateNSView grabs first
    // responder. This works on first mount too because SwiftUI calls updateNSView with
    // the current value right after makeNSView, so a focus request posted before the
    // view existed (e.g. openFile() flips editorPanelVisible and bumps the token in
    // the same call) is still honored.
    var focusRequestID: Int
    var fileExtension: String
    var lineWrap: Bool = true
    var themePalette: [NSColor] = []
    var themeForeground: NSColor = NSColor(white: 0.85, alpha: 1)
    var themeBackground: NSColor = NSColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = themeBackground

        let contentSize = scrollView.contentSize
        let textView = AgamonEditorTextView(frame: NSRect(origin: .zero, size: contentSize))

        // NSTextView must be told to resize vertically and track the scroll view width,
        // otherwise it renders at zero height and nothing is visible.
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        applyLineWrap(lineWrap, to: textView, scrollView: scrollView)

        // isRichText must be true for NSTextStorage attribute changes to persist between keystrokes.
        // typingAttributes ensures new characters the user types get the base style, not a stale color.
        textView.isRichText = true
        // Native macOS inline find bar — Cmd+F is delivered to NSTextView via performKeyEquivalent
        // before SwiftUI's keyboardShortcut buttons see it, so no extra routing is needed.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        let editorFont = NSFont.monospacedSystemFont(ofSize: Theme.FontSize.sm, weight: .regular)
        let editorColor = NSColor(white: 0.85, alpha: 1)
        textView.font = editorFont
        textView.textColor = editorColor
        textView.backgroundColor = themeBackground
        textView.typingAttributes = [.font: editorFont, .foregroundColor: editorColor]
        textView.textContainerInset = NSSize(width: Theme.Spacing.md, height: Theme.Spacing.md)

        // Disable smart substitutions — they corrupt code
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        textView.onFocusChange = onFocusChange
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let prevParent = context.coordinator.parent
        context.coordinator.parent = self

        let paletteChanged = prevParent.themePalette.count != themePalette.count
            || zip(prevParent.themePalette, themePalette).contains(where: { $0 != $1 })

        if paletteChanged || prevParent.themeBackground != themeBackground {
            scrollView.backgroundColor = themeBackground
            textView.backgroundColor = themeBackground
        }

        if prevParent.lineWrap != lineWrap {
            applyLineWrap(lineWrap, to: textView, scrollView: scrollView)
        }
        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
        } else if paletteChanged {
            // Theme changed — re-highlight without replacing the string
            context.coordinator.applyHighlighting(to: textView)
        }
        if focusRequestID != context.coordinator.lastFocusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            // Defer to next runloop: on first mount the text view may not yet be in
            // a window, and makeFirstResponder is a no-op without a window.
            DispatchQueue.main.async { [weak textView] in
                guard let tv = textView else { return }
                tv.window?.makeFirstResponder(tv)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func applyLineWrap(_ wrap: Bool, to textView: NSTextView, scrollView: NSScrollView) {
        if wrap {
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(
                width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = false
        } else {
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: AgamonEditorTextView?
        // Last focus token consumed; updateNSView triggers makeFirstResponder when it changes.
        var lastFocusRequestID: Int = 0
        private var highlightWork: DispatchWorkItem?

        init(_ parent: EditorTextView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(openFindBar),
                name: .agamonOpenEditorFind, object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        // Called when AppState.openFind() detects editorFocused=true. SwiftUI's
        // ShortcutHandler consumes the Cmd+F key event before NSTextView.performKeyEquivalent
        // sees it, so we must explicitly invoke the find bar here.
        @objc private func openFindBar() {
            guard let tv = textView else { return }
            // NSMenuItem with tag = NSTextFinder.Action.showFindInterface (1) is the
            // documented way to trigger the inline find bar when usesFindBar = true.
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            tv.window?.makeFirstResponder(tv)
            tv.performFindPanelAction(item)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onChange()
            // Debounce: wait 80ms after the last keystroke before re-highlighting.
            // This prevents per-character regex runs on large files.
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.applyHighlighting(to: tv)
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }

        // Applies syntax colors to the text view's storage. Safe to call on main thread only.
        func applyHighlighting(to tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let lang     = SyntaxLanguage.detect(fileExtension: parent.fileExtension)
            let baseFont = NSFont.monospacedSystemFont(ofSize: Theme.FontSize.sm, weight: .regular)
            let palette  = SyntaxPalette(nsColors: parent.themePalette, foreground: parent.themeForeground)
            if lang == .markdown {
                MarkdownHighlighter.apply(to: storage, foreground: parent.themeForeground,
                                          palette: palette, baseFontSize: Theme.FontSize.sm)
            } else {
                SyntaxHighlighter.apply(to: storage, language: lang, palette: palette, baseFont: baseFont)
            }
            tv.typingAttributes = [.font: baseFont, .foregroundColor: palette.base]
        }
    }
}
