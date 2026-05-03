// Lightweight inline editor for files the agent produces.
// Wraps NSTextView (AppKit) because SwiftUI's TextEditor lacks: monospace font control,
// disabling smart quotes/dashes, and proper dark background without fighting system appearance.
// Cmd+S saves. Dirty state is shown as a dot in the tab (EditorPanelView) only — no save button.
// A slim bottom status bar shows the cursor position (line:col) and any load/save errors.
// isDirty is lifted to the parent (EditorPanelView) so dirty state persists across tab switches.
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
    @State private var cursorLine: Int = 1
    @State private var cursorCol: Int  = 1

    private var activeTheme: TerminalTheme? {
        let name = colorScheme == .dark ? appState.selectedDarkThemeName : appState.selectedLightThemeName
        return TerminalTheme.all[name] ?? TerminalTheme.all.values.first
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorTextView(
                text: $content,
                onChange: { isDirty = true },
                focusRequestID: appState.editorFocusRequestID,
                fileExtension: url.pathExtension,
                lineWrap: appState.editorLineWrap,
                themePalette: activeTheme?.rawPalette ?? [],
                themeForeground: activeTheme?.foreground ?? NSColor(white: 0.85, alpha: 1),
                themeBackground: activeTheme?.background ?? NSColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1),
                onFocusChange: { focused in appState.editorFocused = focused },
                onCursorChange: { line, col in cursorLine = line; cursorCol = col }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Theme.Color.border).frame(height: 1)
            statusBar
        }
        .background {
            Button("") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
        }
        .onChange(of: url) { saveError = nil; cursorLine = 1; cursorCol = 1 }
    }

    private var statusBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let error = saveError ?? loadError {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.danger)
                Text(error)
                    .font(.system(size: Theme.FontSize.xs))
                    .foregroundStyle(Theme.Color.danger)
                    .lineLimit(1)
            }
            Spacer()
            Text("Ln \(cursorLine), Col \(cursorCol)")
                .font(.system(size: Theme.FontSize.xs, design: .monospaced))
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 3)
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
// Houses all smart editing behaviours: Tab indent, Shift+Tab de-indent, auto-pairs,
// and paired-character smart backspace.
final class AgamonEditorTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    var fileExtension: String = ""

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

    // MARK: Tab / Shift-Tab indent

    // Single line / no selection: insert a real tab character.
    // Multi-line selection: add one tab at the start of every selected line (grouped undo).
    override func insertTab(_ sender: Any?) {
        guard let storage = textStorage, isEditable else { super.insertTab(sender); return }
        let sel    = selectedRange()
        let nsText = storage.string as NSString

        let selText = sel.length > 0 ? nsText.substring(with: sel) : ""
        guard selText.contains("\n") else { super.insertTab(sender); return }

        // Snapshot all line-start positions BEFORE modifying the string.
        // Inserting back-to-front keeps earlier positions valid and avoids the
        // "live NSString shifts under us" bug where pos = NSMaxRange(lr) re-reads
        // the same line after the tab is inserted.
        let linesRange = nsText.lineRange(for: sel)
        var lineStarts: [Int] = []
        var pos = linesRange.location
        while pos < NSMaxRange(linesRange) {
            let lr = nsText.lineRange(for: NSRange(location: pos, length: 0))
            lineStarts.append(lr.location)
            if lr.length == 0 { break }
            pos = NSMaxRange(lr)
        }
        guard !lineStarts.isEmpty else { return }

        undoManager?.beginUndoGrouping()
        var insertedCount = 0
        for start in lineStarts.reversed() {
            let range = NSRange(location: start, length: 0)
            if shouldChangeText(in: range, replacementString: "\t") {
                storage.replaceCharacters(in: range, with: "\t")
                didChangeText()
                insertedCount += 1
            }
        }
        undoManager?.endUndoGrouping()

        let insertedBefore = lineStarts.filter { $0 < sel.location }.count
        setSelectedRange(NSRange(location: sel.location + insertedBefore,
                                 length: sel.length + insertedCount - insertedBefore))
    }

    // Remove one level of indentation (one tab or up to 4 spaces) from every line
    // that intersects the current selection. Uses shouldChangeText/didChangeText so
    // undo is registered automatically; all removals are grouped into one undo step.
    override func insertBacktab(_ sender: Any?) {
        guard let storage = textStorage, isEditable else { super.insertBacktab(sender); return }
        let sel        = selectedRange()
        let nsStr      = storage.string as NSString
        let linesRange = nsStr.lineRange(for: sel)
        var removals: [(start: Int, count: Int)] = []
        var pos = linesRange.location
        while pos < NSMaxRange(linesRange) {
            let lr   = nsStr.lineRange(for: NSRange(location: pos, length: 0))
            let line = nsStr.substring(with: lr)
            var n    = 0
            if line.hasPrefix("\t") {
                n = 1
            } else {
                for ch in line.unicodeScalars { guard ch == " " && n < 4 else { break }; n += 1 }
            }
            removals.append((start: lr.location, count: n))
            if lr.length == 0 { break }
            pos = NSMaxRange(lr)
        }
        guard removals.contains(where: { $0.count > 0 }) else { return }
        undoManager?.beginUndoGrouping()
        var offset = 0, removedBeforeCursor = 0, totalRemoved = 0
        for (start, count) in removals {
            guard count > 0 else { continue }
            let range = NSRange(location: start - offset, length: count)
            if shouldChangeText(in: range, replacementString: "") {
                storage.replaceCharacters(in: range, with: "")
                didChangeText()
                offset += count; totalRemoved += count
                if start < sel.location { removedBeforeCursor += min(start + count, sel.location) - start }
            }
        }
        undoManager?.endUndoGrouping()
        setSelectedRange(NSRange(location: max(linesRange.location, sel.location - removedBeforeCursor),
                                 length: max(0, sel.length - (totalRemoved - removedBeforeCursor))))
    }

    // MARK: Auto-pairs

    // Opening brackets always auto-close. Quotes auto-close unless the cursor is
    // adjacent to an alphanumeric character (e.g. typing ' inside a word).
    // Wraps any active selection in the pair instead of replacing it.
    private static let bracketPairs:  [String: String] = ["(": ")", "[": "]", "{": "}"]
    private static let quotePairs:    [String: String] = ["\"": "\"", "'": "'", "`": "`"]
    private static let allClosers:    Set<String>      = [")", "]", "}", "\"", "'", "`", ">"]
    private static let htmlExtensions: Set<String>     = ["html", "htm", "xml", "xhtml", "svg"]

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard isEditable,
              let str = (string as? String) ?? (string as? NSAttributedString)?.string,
              str.count == 1,
              let storage = textStorage else {
            super.insertText(string, replacementRange: replacementRange); return
        }

        let sel    = selectedRange()
        let nsText = storage.string as NSString

        // Skip over existing matching closer when cursor sits right before it
        if Self.allClosers.contains(str), sel.length == 0, sel.location < nsText.length,
           nsText.substring(with: NSRange(location: sel.location, length: 1)) == str,
           !Self.quotePairs.keys.contains(str) {   // brackets only — quotes need context
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }

        // HTML/XML: auto-close angle brackets
        if str == "<", Self.htmlExtensions.contains(fileExtension.lowercased()) {
            if sel.length > 0 {
                let inner = nsText.substring(with: sel)
                super.insertText("<" + inner + ">", replacementRange: replacementRange)
                setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
            } else {
                super.insertText("<>", replacementRange: replacementRange)
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            }
            return
        }

        // Bracket auto-pair
        if let closer = Self.bracketPairs[str] {
            if sel.length > 0 {
                let inner = nsText.substring(with: sel)
                super.insertText(str + inner + closer, replacementRange: replacementRange)
                setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
            } else {
                super.insertText(str + closer, replacementRange: replacementRange)
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            }
            return
        }

        // Quote auto-pair — skip if adjacent to word character
        if Self.quotePairs[str] != nil {
            let prevChar: Character? = sel.location > 0
                ? Character(UnicodeScalar(nsText.character(at: sel.location - 1))!)
                : nil
            let nextChar: Character? = sel.location < nsText.length
                ? Character(UnicodeScalar(nsText.character(at: sel.location))!)
                : nil

            if let next = nextChar, next.isLetter || next.isNumber {
                // Inside a word — plain insert
                super.insertText(string, replacementRange: replacementRange); return
            }
            // Skip over matching closing quote
            if sel.length == 0, let next = nextChar, String(next) == str {
                setSelectedRange(NSRange(location: sel.location + 1, length: 0)); return
            }
            // Don't double-close after a quote character
            if let prev = prevChar, String(prev) == str, sel.length == 0 {
                super.insertText(string, replacementRange: replacementRange); return
            }
            if sel.length > 0 {
                let inner = nsText.substring(with: sel)
                super.insertText(str + inner + str, replacementRange: replacementRange)
                setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
            } else {
                super.insertText(str + str, replacementRange: replacementRange)
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            }
            return
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    // Delete both characters when backspacing onto an empty auto-paired bracket/quote.
    override func deleteBackward(_ sender: Any?) {
        guard isEditable, let storage = textStorage else { super.deleteBackward(sender); return }
        let sel = selectedRange()
        guard sel.length == 0, sel.location > 0 else { super.deleteBackward(sender); return }
        let nsText  = storage.string as NSString
        let prevCh  = Character(UnicodeScalar(nsText.character(at: sel.location - 1))!)
        let allPairs: [Character: Character] = [
            "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`", "<": ">"
        ]
        if let closer = allPairs[prevCh], sel.location < nsText.length {
            let nextCh = Character(UnicodeScalar(nsText.character(at: sel.location))!)
            if nextCh == closer {
                let range = NSRange(location: sel.location - 1, length: 2)
                if shouldChangeText(in: range, replacementString: "") {
                    storage.replaceCharacters(in: range, with: "")
                    didChangeText()
                }
                return
            }
        }
        super.deleteBackward(sender)
    }
}

// MARK: - Line number gutter

// NSRulerView subclass drawn in the scroll view's vertical ruler slot.
// Highlights the line containing the cursor; dims all other line numbers.
// Redraws on text-change and selection-change notifications so it stays in sync
// without any extra wiring from the SwiftUI layer.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let lineFont: NSFont
    private let dimColor:    NSColor = NSColor(white: 0.32, alpha: 1)
    private let activeColor: NSColor = NSColor(white: 0.60, alpha: 1)
    private let bgColor:     NSColor = NSColor(white: 0.10, alpha: 1)
    private let borderColor: NSColor = NSColor(white: 0.18, alpha: 1)

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.lineFont = NSFont.monospacedSystemFont(ofSize: Theme.FontSize.xs - 0.5, weight: .regular)
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        NotificationCenter.default.addObserver(
            self, selector: #selector(setNeedsRedraw),
            name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(setNeedsRedraw),
            name: NSTextView.didChangeSelectionNotification, object: textView)
    }
    required init(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func setNeedsRedraw() { needsDisplay = true }

    override var requiredThickness: CGFloat {
        let lines  = textView?.string.components(separatedBy: "\n").count ?? 1
        let digits = max(3, "\(lines)".count)
        return ceil(CGFloat(digits) * lineFont.maximumAdvancement.width + 14)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView,
              let lm = tv.layoutManager,
              let sv = scrollView else { return }

        bgColor.setFill();    bounds.fill()
        borderColor.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let contentOffsetY = sv.contentView.bounds.minY
        let insetY         = tv.textContainerInset.height
        let nsText         = tv.string as NSString
        let cursorLoc      = tv.selectedRange().location
        var lineNum        = 0

        lm.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)
        ) { [weak self] _, usedRect, _, glyphRange, _ in
            guard let self else { return }
            let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let isStart   = charRange.location == 0
                         || (charRange.location > 0 && nsText.character(at: charRange.location - 1) == 10)
            guard isStart else { return }
            lineNum += 1

            let lineY = usedRect.minY + insetY - contentOffsetY
            guard lineY + usedRect.height > rect.minY - 2,
                  lineY < rect.maxY + 2 else { return }

            // Use < for lines that end with a newline so the cursor sitting at
            // the start of the NEXT line doesn't highlight BOTH lines at once.
            // The last line (no trailing newline) uses <= to include end-of-file position.
            let lineEnd  = charRange.location + charRange.length
            let isActive = cursorLoc >= charRange.location
                        && (lineEnd < nsText.length ? cursorLoc < lineEnd : cursorLoc <= lineEnd)
            let color    = isActive ? self.activeColor : self.dimColor
            let label    = "\(lineNum)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: self.lineFont, .foregroundColor: color]
            let sz       = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: self.bounds.width - sz.width - 6,
                                   y: lineY + (usedRect.height - sz.height) / 2),
                       withAttributes: attrs)
        }

        // Extra fragment for the virtual line after a trailing newline
        if lm.extraLineFragmentTextContainer != nil {
            lineNum += 1
            let extraRect = lm.extraLineFragmentUsedRect
            let lineY     = extraRect.minY + insetY - contentOffsetY
            guard lineY + extraRect.height > rect.minY - 2, lineY < rect.maxY + 2 else { return }
            let isActive  = cursorLoc >= nsText.length
            let color     = isActive ? activeColor : dimColor
            let label     = "\(lineNum)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: lineFont, .foregroundColor: color]
            let sz        = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: bounds.width - sz.width - 6,
                                   y: lineY + (extraRect.height - sz.height) / 2),
                       withAttributes: attrs)
        }
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
    var onCursorChange: ((Int, Int) -> Void)? = nil

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
        let editorFont  = NSFont.monospacedSystemFont(ofSize: Theme.FontSize.sm, weight: .regular)
        let editorColor = NSColor(white: 0.85, alpha: 1)
        textView.font            = editorFont
        textView.textColor       = editorColor
        textView.backgroundColor = themeBackground
        textView.typingAttributes = [.font: editorFont, .foregroundColor: editorColor]
        textView.textContainerInset = NSSize(width: Theme.Spacing.md, height: Theme.Spacing.md)

        // Disable smart substitutions — they corrupt code
        textView.isAutomaticQuoteSubstitutionEnabled  = false
        textView.isAutomaticDashSubstitutionEnabled   = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled      = false

        textView.onFocusChange = onFocusChange
        textView.fileExtension = fileExtension
        textView.delegate      = context.coordinator
        context.coordinator.textView = textView
        scrollView.documentView = textView

        // Attach line number gutter
        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler  = true
        scrollView.rulersVisible     = true

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
            textView.backgroundColor   = themeBackground
        }

        if let tv = scrollView.documentView as? AgamonEditorTextView, tv.fileExtension != fileExtension {
            tv.fileExtension = fileExtension
        }
        if prevParent.lineWrap != lineWrap {
            applyLineWrap(lineWrap, to: textView, scrollView: scrollView)
            scrollView.verticalRulerView?.needsDisplay = true
        }
        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
            scrollView.verticalRulerView?.needsDisplay = true
        } else if paletteChanged {
            context.coordinator.applyHighlighting(to: textView)
        }
        if focusRequestID != context.coordinator.lastFocusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
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
        var lastFocusRequestID: Int = 0
        private var highlightWork: DispatchWorkItem?

        init(_ parent: EditorTextView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(openFindBar),
                name: .agamonOpenEditorFind, object: nil)
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        // Called when AppState.openFind() detects editorFocused=true. SwiftUI's
        // ShortcutHandler consumes the Cmd+F key event before NSTextView.performKeyEquivalent
        // sees it, so we must explicitly invoke the find bar here.
        @objc private func openFindBar() {
            guard let tv = textView else { return }
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            tv.window?.makeFirstResponder(tv)
            tv.performFindPanelAction(item)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onChange()
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.applyHighlighting(to: tv)
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }

        // Update the line:col counter whenever the insertion point moves.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            let loc    = min(tv.selectedRange().location, storage.length)
            let nsText = storage.string as NSString
            let lineRange = nsText.lineRange(for: NSRange(location: loc, length: 0))
            var line = 1
            var i    = 0
            while i < lineRange.location {
                if nsText.character(at: i) == 10 { line += 1 }
                i += 1
            }
            let col = loc - lineRange.location + 1
            parent.onCursorChange?(line, col)
        }

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
