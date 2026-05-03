// Typora-style in-place markdown renderer for the file editor.
// Raw markdown syntax stays visible but is styled to convey structure:
//   - # headers get larger/bolder fonts; the # prefix is dimmed
//   - **bold** / *italic* apply font traits; delimiters are dimmed
//   - `code` spans get the string palette color; backticks are dimmed
//   - [links](url) accent the link text; brackets and URL are dimmed
//   - > blockquotes, ``` fences, and ~~strikethrough~~ all styled
//
// Two-pass approach: block pass sets font sizes line-by-line, then the inline
// pass reads the existing font at each location and modifies it (so bold inside
// a heading inherits the heading's font size).
//
// Related: SyntaxHighlighter.swift (other languages), FileEditorView.swift
//          (Coordinator calls this when fileExtension is md/markdown).

import AppKit

struct MarkdownHighlighter {

    // Cached regexes — compiled once, reused for every highlight pass.
    private static let boldRegex       = try? NSRegularExpression(pattern: #"(\*\*|__)(.+?)\1"#)
    private static let italicStarRegex = try? NSRegularExpression(pattern: #"(?<!\*)\*(?!\*|\s)(.+?)(?<!\s)\*(?!\*)"#)
    private static let italicUndRegex  = try? NSRegularExpression(pattern: #"(?<!_)_(?!_|\s)(.+?)(?<!\s)_(?!_)"#)
    private static let codeRegex       = try? NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    private static let linkRegex       = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\([^\)\n]*\)"#)
    private static let strikeRegex     = try? NSRegularExpression(pattern: #"~~(.+?)~~"#)

    static func apply(to storage: NSTextStorage,
                      foreground: NSColor,
                      palette: SyntaxPalette,
                      baseFontSize: CGFloat) {
        let text = storage.string
        guard !text.isEmpty else { return }

        let baseFont = NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
        let dimColor = foreground.withAlphaComponent(0.28)
        let full     = NSRange(location: 0, length: (text as NSString).length)

        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: foreground], range: full)
        applyBlocks(to: storage, text: text, foreground: foreground,
                    dimColor: dimColor, palette: palette, baseFontSize: baseFontSize)
        applyInline(to: storage, text: text, foreground: foreground,
                    dimColor: dimColor, palette: palette, baseFontSize: baseFontSize)
        storage.endEditing()
    }

    // MARK: - Block pass (line-by-line)

    private static func applyBlocks(to storage: NSTextStorage, text: String,
                                     foreground: NSColor, dimColor: NSColor,
                                     palette: SyntaxPalette, baseFontSize: CGFloat) {
        let baseFont = NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
        let lines = text.components(separatedBy: "\n")
        var pos = 0
        var inFence = false

        for (i, line) in lines.enumerated() {
            let lineLen  = (line as NSString).length
            let lineRange = NSRange(location: pos, length: lineLen)
            let isLast   = i == lines.count - 1
            defer { pos += lineLen + (isLast ? 0 : 1) }
            guard lineLen > 0 else { continue }

            // Code fence boundary (``` or ~~~)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fenceFont = NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.92, weight: .regular)
                storage.addAttributes([.font: fenceFont, .foregroundColor: dimColor], range: lineRange)
                inFence.toggle()
                continue
            }
            if inFence {
                let codeFont = NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.92, weight: .regular)
                storage.addAttributes([.font: codeFont,
                                       .foregroundColor: foreground.withAlphaComponent(0.72)],
                                      range: lineRange)
                continue
            }

            // Headings: count leading #s followed by a space
            let hashes = line.prefix(while: { $0 == "#" }).count
            if hashes >= 1, hashes <= 6,
               line.count > hashes,
               line[line.index(line.startIndex, offsetBy: hashes)] == " " {
                let (scale, weight): (CGFloat, NSFont.Weight) = switch hashes {
                case 1:  (1.75, .bold)
                case 2:  (1.45, .bold)
                case 3:  (1.2,  .semibold)
                case 4:  (1.1,  .semibold)
                default: (1.0,  .medium)
                }
                let hFont = NSFont.monospacedSystemFont(ofSize: round(baseFontSize * scale), weight: weight)
                storage.addAttributes([.font: hFont, .foregroundColor: foreground], range: lineRange)
                // Dim the "# " prefix
                let prefixRange = NSRange(location: lineRange.location, length: min(hashes + 1, lineLen))
                storage.addAttributes([.font: baseFont, .foregroundColor: dimColor], range: prefixRange)
                continue
            }

            // Blockquote
            if line.hasPrefix("> ") || line == ">" {
                storage.addAttributes([.foregroundColor: palette.comment], range: lineRange)
                let prefixLen = line.hasPrefix("> ") ? 2 : 1
                let prefixRange = NSRange(location: lineRange.location, length: min(prefixLen, lineLen))
                storage.addAttributes([.foregroundColor: dimColor], range: prefixRange)
                continue
            }

            // Horizontal rule: 3+ of the same char (- * _) with optional spaces, nothing else
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.count >= 3, let ch = stripped.first,
               (ch == "-" || ch == "*" || ch == "_"),
               stripped.allSatisfy({ $0 == ch || $0 == " " }),
               stripped.filter({ $0 == ch }).count >= 3 {
                storage.addAttributes([.foregroundColor: dimColor], range: lineRange)
            }
        }
    }

    // MARK: - Inline pass

    private static func applyInline(to storage: NSTextStorage, text: String,
                                     foreground: NSColor, dimColor: NSColor,
                                     palette: SyntaxPalette, baseFontSize: CGFloat) {
        let full = NSRange(location: 0, length: (text as NSString).length)

        // Bold **text** / __text__ — inherit existing font size, apply bold weight
        boldRegex?.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let markerLen  = m.range(at: 1).length
            let innerRange = m.range(at: 2)
            guard innerRange.length > 0 else { return }
            let size = (storage.attribute(.font, at: innerRange.location, effectiveRange: nil) as? NSFont)?.pointSize ?? baseFontSize
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .bold), range: innerRange)
            dim(storage: storage, at: m.range.location, length: markerLen, color: dimColor)
            dim(storage: storage, at: m.range.location + m.range.length - markerLen, length: markerLen, color: dimColor)
        }

        // Italic *text* — inherit font size, apply italic trait
        for regex in [italicStarRegex, italicUndRegex] {
            regex?.enumerateMatches(in: text, range: full) { m, _, _ in
                guard let m else { return }
                let innerRange = m.range(at: 1)
                guard innerRange.length > 0 else { return }
                let base = (storage.attribute(.font, at: innerRange.location, effectiveRange: nil) as? NSFont) ?? NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
                if let italic = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) as NSFont? {
                    storage.addAttribute(.font, value: italic, range: innerRange)
                }
                dim(storage: storage, at: m.range.location, length: 1, color: dimColor)
                dim(storage: storage, at: m.range.location + m.range.length - 1, length: 1, color: dimColor)
            }
        }

        // Inline code `text` — string color, dim backticks
        codeRegex?.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let innerRange = m.range(at: 1)
            guard innerRange.length > 0 else { return }
            storage.addAttribute(.foregroundColor, value: palette.string, range: innerRange)
            dim(storage: storage, at: m.range.location, length: 1, color: dimColor)
            dim(storage: storage, at: m.range.location + m.range.length - 1, length: 1, color: dimColor)
        }

        // Link [text](url) — accent the text, dim bracket and URL
        linkRegex?.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let textRange = m.range(at: 1)
            guard textRange.length > 0 else { return }
            storage.addAttribute(.foregroundColor, value: palette.keyword, range: textRange)
            // Dim "[" before text
            dim(storage: storage, at: m.range.location, length: 1, color: dimColor)
            // Dim "](url)" after text
            let tailStart  = textRange.location + textRange.length
            let tailLength = m.range.location + m.range.length - tailStart
            if tailLength > 0 {
                storage.addAttributes([.foregroundColor: dimColor],
                                      range: NSRange(location: tailStart, length: tailLength))
            }
        }

        // Strikethrough ~~text~~
        strikeRegex?.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let innerRange = m.range(at: 1)
            guard innerRange.length > 0 else { return }
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .foregroundColor: foreground.withAlphaComponent(0.5)],
                                  range: innerRange)
            dim(storage: storage, at: m.range.location, length: 2, color: dimColor)
            dim(storage: storage, at: m.range.location + m.range.length - 2, length: 2, color: dimColor)
        }
    }

    // MARK: - Helpers

    private static func dim(storage: NSTextStorage, at location: Int, length: Int, color: NSColor) {
        guard length > 0, location >= 0,
              location + length <= (storage.string as NSString).length else { return }
        storage.addAttribute(.foregroundColor, value: color,
                             range: NSRange(location: location, length: length))
    }
}
