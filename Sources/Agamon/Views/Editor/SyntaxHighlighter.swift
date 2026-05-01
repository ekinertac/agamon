// Lightweight regex-based syntax highlighter for the file editor.
// Applies NSAttributedString color attributes to NSTextStorage in rule priority order:
// keywords/numbers/types first (lowest), then strings (override keywords inside strings),
// then comments (highest — override everything). Each rule overwrites prior attributes,
// so later rules win. Rules are compiled once and cached per language.
// Related: FileEditorView.swift (Coordinator calls highlight after every text-storage change).

import AppKit

// MARK: - Language

enum SyntaxLanguage {
    case swift, python, javascript, typescript, json, yaml, shell, ruby, go, rust, markdown

    static func detect(fileExtension ext: String) -> SyntaxLanguage? {
        switch ext.lowercased() {
        case "swift":                    return .swift
        case "py":                       return .python
        case "js", "jsx", "mjs", "cjs": return .javascript
        case "ts", "tsx":                return .typescript
        case "json", "jsonc":            return .json
        case "yaml", "yml":              return .yaml
        case "sh", "bash", "zsh", "fish", "command": return .shell
        case "rb":                       return .ruby
        case "go":                       return .go
        case "rs":                       return .rust
        case "md", "markdown":           return .markdown
        default:                         return nil
        }
    }
}

// MARK: - Colors

enum SyntaxColor {
    static let comment  = NSColor(red: 0.38, green: 0.38, blue: 0.38, alpha: 1) // #616161 dim gray
    static let keyword  = NSColor(red: 0.47, green: 0.47, blue: 0.73, alpha: 1) // #7878bb blue-purple
    static let string   = NSColor(red: 0.42, green: 0.63, blue: 0.42, alpha: 1) // #6ba06b muted green
    static let number   = NSColor(red: 0.78, green: 0.50, blue: 0.35, alpha: 1) // #c78059 muted orange
    static let typeName = NSColor(red: 0.37, green: 0.63, blue: 0.63, alpha: 1) // #5ea0a0 teal
    static let funcName = NSColor(red: 0.83, green: 0.69, blue: 0.38, alpha: 1) // #d4b061 amber
    static let preproc  = NSColor(red: 0.55, green: 0.55, blue: 0.35, alpha: 1) // #8d8d59 olive
}

// MARK: - Rule

private struct SyntaxRule {
    let regex: NSRegularExpression
    let color: NSColor
    let captureGroup: Int // 0 = full match
}

// MARK: - SyntaxHighlighter

struct SyntaxHighlighter {
    // Apply syntax highlighting to the given text storage in place.
    // baseColor/baseFont are reset first so stale attributes don't bleed.
    static func apply(to storage: NSTextStorage, language: SyntaxLanguage?,
                      baseColor: NSColor, baseFont: NSFont) {
        guard let language else { return }
        let rules = rules(for: language)
        let text  = storage.string
        let full  = NSRange(location: 0, length: (text as NSString).length)

        storage.beginEditing()
        storage.addAttributes([.foregroundColor: baseColor, .font: baseFont], range: full)
        for rule in rules {
            rule.regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                let r = rule.captureGroup == 0 ? match.range : match.range(at: rule.captureGroup)
                guard r.location != NSNotFound, r.length > 0 else { return }
                storage.addAttribute(.foregroundColor, value: rule.color, range: r)
            }
        }
        storage.endEditing()
    }

    // MARK: - Rule cache

    private static func rules(for language: SyntaxLanguage) -> [SyntaxRule] {
        let strKey = "\(language)"
        if let hit = rulesByName[strKey] { return hit }
        let built = buildRules(for: language)
        rulesByName[strKey] = built
        return built
    }

    private static var rulesByName: [String: [SyntaxRule]] = [:]

    private static func r(_ pattern: String, _ color: NSColor, group: Int = 0) -> SyntaxRule? {
        guard let rx = try? NSRegularExpression(pattern: pattern,
                                                 options: [.dotMatchesLineSeparators]) else { return nil }
        return SyntaxRule(regex: rx, color: color, captureGroup: group)
    }

    // MARK: - Language rule sets
    // Order matters: higher-priority rules come last (they overwrite earlier attributes).

    private static func buildRules(for language: SyntaxLanguage) -> [SyntaxRule] {
        switch language {
        case .swift:      return swiftRules()
        case .python:     return pythonRules()
        case .javascript: return jsRules()
        case .typescript: return tsRules()
        case .json:       return jsonRules()
        case .yaml:       return yamlRules()
        case .shell:      return shellRules()
        case .ruby:       return rubyRules()
        case .go:         return goRules()
        case .rust:       return rustRules()
        case .markdown:   return markdownRules()
        }
    }

    // MARK: Swift

    private static func swiftRules() -> [SyntaxRule] {
        [
            // Types (capital-start identifiers) — lowest priority
            r(#"\b[A-Z][A-Za-z0-9_]*\b"#, SyntaxColor.typeName),
            // Numbers
            r(#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?\b|0x[0-9a-fA-F_]+\b|0b[01_]+\b|0o[0-7_]+\b"#,
              SyntaxColor.number),
            // Attributes
            r(#"@\w+"#, SyntaxColor.preproc),
            // Keywords
            r(#"\b(?:let|var|func|class|struct|enum|protocol|extension|import|return|if|else|guard|switch|case|default|for|in|while|break|continue|true|false|nil|self|Self|super|static|final|private|public|internal|fileprivate|open|override|mutating|nonmutating|throws|rethrows|throw|try|catch|async|await|actor|isolated|nonisolated|some|any|where|typealias|associatedtype|subscript|init|deinit|lazy|weak|unowned|inout|defer|repeat|is|as|do|_)\b"#,
              SyntaxColor.keyword),
            // Function names after `func`
            r(#"(?<=func\s)\w+"#, SyntaxColor.funcName),
            // Strings (double-quoted, single-line; handles escapes)
            r(#""(?:[^"\\]|\\.)*""#, SyntaxColor.string),
            // Multi-line strings
            r(#""{3}.*?"{3}"#, SyntaxColor.string),
            // Line comments
            r(#"\/\/[^\n]*"#, SyntaxColor.comment),
            // Block comments
            r(#"\/\*.*?\*\/"#, SyntaxColor.comment),
        ].compactMap { $0 }
    }

    // MARK: Python

    private static func pythonRules() -> [SyntaxRule] {
        [
            r(#"\b[A-Z][A-Za-z0-9_]*\b"#, SyntaxColor.typeName),
            r(#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?\b"#, SyntaxColor.number),
            r(#"@\w+"#, SyntaxColor.preproc),
            r(#"\b(?:def|class|import|from|as|return|if|elif|else|for|while|break|continue|pass|True|False|None|and|or|not|in|is|lambda|with|try|except|finally|raise|yield|async|await|global|nonlocal|del|assert|print)\b"#,
              SyntaxColor.keyword),
            r(#"(?<=def\s)\w+"#, SyntaxColor.funcName),
            r(#"'(?:[^'\\]|\\.)*'"#, SyntaxColor.string),
            r(#""(?:[^"\\]|\\.)*""#, SyntaxColor.string),
            r(#"'{3}.*?'{3}"#, SyntaxColor.string),
            r(#""{3}.*?"{3}"#, SyntaxColor.string),
            r(#"#[^\n]*"#, SyntaxColor.comment),
        ].compactMap { $0 }
    }

    // MARK: JavaScript

    private static func jsRules() -> [SyntaxRule] {
        [
            r(#"\b[A-Z][A-Za-z0-9_]*\b"#, SyntaxColor.typeName),
            r(#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?\b|0x[0-9a-fA-F]+\b"#, SyntaxColor.number),
            r(#"\b(?:const|let|var|function|class|extends|import|export|from|return|if|else|switch|case|default|for|of|in|while|break|continue|true|false|null|undefined|this|super|new|delete|typeof|instanceof|void|throw|try|catch|finally|async|await|yield|static|get|set|do|debugger)\b"#,
              SyntaxColor.keyword),
            r(#"(?<=function\s)\w+"#, SyntaxColor.funcName),
            r(#"'(?:[^'\\]|\\.)*'"#, SyntaxColor.string),
            r(#""(?:[^"\\]|\\.)*""#, SyntaxColor.string),
            r(#"`(?:[^`\\]|\\.)*`"#, SyntaxColor.string),
            r(#"\/\/[^\n]*"#, SyntaxColor.comment),
            r(#"\/\*.*?\*\/"#, SyntaxColor.comment),
        ].compactMap { $0 }
    }

    // MARK: TypeScript (superset of JS keywords)

    private static func tsRules() -> [SyntaxRule] {
        var rules = jsRules()
        // Drop existing keyword rule (last .keyword entry) and replace with TS superset
        rules = rules.filter { rule in
            let src = rule.regex.pattern
            return !src.contains("const|let|var|function|class") // remove js keyword rule
        }
        return rules + [
            r(#"\b(?:const|let|var|function|class|extends|implements|interface|type|enum|namespace|module|declare|abstract|import|export|from|return|if|else|switch|case|default|for|of|in|while|break|continue|true|false|null|undefined|this|super|new|delete|typeof|instanceof|void|throw|try|catch|finally|async|await|yield|static|get|set|do|readonly|keyof|infer|never|unknown|any|as|is|satisfies)\b"#,
              SyntaxColor.keyword),
        ].compactMap { $0 }
    }

    // MARK: JSON

    private static func jsonRules() -> [SyntaxRule] {
        [
            r(#"\b(?:true|false|null)\b"#, SyntaxColor.keyword),
            r(#"\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, SyntaxColor.number),
            // Object keys (string before colon)
            r(#""(?:[^"\\]|\\.)*"(?=\s*:)"#, SyntaxColor.funcName),
            // String values
            r(#""(?:[^"\\]|\\.)*""#, SyntaxColor.string),
        ].compactMap { $0 }
    }

    // MARK: YAML

    private static func yamlRules() -> [SyntaxRule] {
        [
            r(#"\b(?:true|false|null|yes|no|on|off)\b"#, SyntaxColor.keyword),
            r(#"\b-?\d+(?:\.\d+)?\b"#, SyntaxColor.number),
            r(#"^[ \t]*[\w\-\.]+(?=\s*:)"#, SyntaxColor.funcName),
            r(#"'(?:[^'\\]|\\.)*'"#, SyntaxColor.string),
            r(#""(?:[^"\\]|\\.)*""#, SyntaxColor.string),
            r(#"#[^\n]*"#, SyntaxColor.comment),
        ].compactMap { $0 }
    }

    // MARK: Shell

    private static func shellRules() -> [SyntaxRule] {
        [
            r(#"\b\d+\b"#, SyntaxColor.number),
            r(#"\b(?:if|then|else|elif|fi|for|do|done|while|until|case|esac|in|function|return|exit|local|export|readonly|shift|set|unset|source|echo|printf|eval|exec|true|false)\b"#,
              SyntaxColor.keyword),
            r(#"\$[\w{][^}]*}?|\$[0-9@#?*!$-]"#, SyntaxColor.typeName),
            r(#"'(?:[^'\\]|\\.)*'"#, SyntaxColor.string),
            r(#""(?:[^"\\]|\\.)*""#, SyntaxColor.string),
            r(#"#[^\n]*"#, SyntaxColor.comment),
        ].compactMap { $0 }
    }

    // MARK: Ruby

    private static func rubyRules() -> [SyntaxRule] {
        [
            r(#"\b[A-Z][A-Za-z0-9_]*\b"#, SyntaxColor.typeName),
            r(#"\b\d[\d_]*(?:\.\d[\d_]*)?\b"#, SyntaxColor.number),
            r(#":\w+"#, SyntaxColor.preproc),
            r(#"\b(?:def|class|module|end|if|unless|elsif|else|then|case|when|while|until|for|do|begin|rescue|ensure|raise|return|yield|self|super|true|false|nil|and|or|not|in|require|require_relative|include|extend|attr_reader|attr_writer|attr_accessor|private|protected|public|lambda|proc)\b"#,
              SyntaxColor.keyword),
            r(#"(?<=def\s)\w+"#, SyntaxColor.funcName),
            r(#"'(?:[^'\\]|\\.)*'"#, SyntaxColor.string),
            r(#""(?:[^"\\]|\\.)*""#, SyntaxColor.string),
            r(#"#[^\n]*"#, SyntaxColor.comment),
        ].compactMap { $0 }
    }

    // MARK: Go

    private static func goRules() -> [SyntaxRule] {
        [
            r(#"\b[A-Z][A-Za-z0-9_]*\b"#, SyntaxColor.typeName),
            r(#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?\b|0x[0-9a-fA-F]+\b"#, SyntaxColor.number),
            r(#"\b(?:func|var|const|type|struct|interface|map|chan|go|return|if|else|switch|case|default|for|range|break|continue|select|defer|goto|fallthrough|import|package|make|new|len|cap|append|copy|delete|close|panic|recover|true|false|nil|iota|int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|complex64|complex128|string|bool|byte|rune|error|any)\b"#,
              SyntaxColor.keyword),
            r(#"(?<=func\s)\w+"#, SyntaxColor.funcName),
            r(#"`(?:[^`])*`"#, SyntaxColor.string),
            r(#""(?:[^"\\]|\\.)*""#, SyntaxColor.string),
            r(#"\/\/[^\n]*"#, SyntaxColor.comment),
            r(#"\/\*.*?\*\/"#, SyntaxColor.comment),
        ].compactMap { $0 }
    }

    // MARK: Rust

    private static func rustRules() -> [SyntaxRule] {
        [
            r(#"\b[A-Z][A-Za-z0-9_]*\b"#, SyntaxColor.typeName),
            r(#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?\b|0x[0-9a-fA-F_]+\b|0b[01_]+\b|0o[0-7_]+\b"#,
              SyntaxColor.number),
            r(#"#\[.*?\]"#, SyntaxColor.preproc),
            r(#"\b(?:fn|let|mut|const|static|type|struct|enum|trait|impl|for|use|pub|mod|crate|super|self|Self|return|if|else|match|while|loop|break|continue|where|move|async|await|dyn|ref|in|as|true|false|None|Some|Ok|Err|Box|Vec|String|Option|Result|i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str)\b"#,
              SyntaxColor.keyword),
            r(#"(?<=fn\s)\w+"#, SyntaxColor.funcName),
            r(#""(?:[^"\\]|\\.)*""#, SyntaxColor.string),
            r(#"\/\/[^\n]*"#, SyntaxColor.comment),
            r(#"\/\*.*?\*\/"#, SyntaxColor.comment),
        ].compactMap { $0 }
    }

    // MARK: Markdown

    private static func markdownRules() -> [SyntaxRule] {
        [
            // Inline code
            r(#"`[^`\n]+`"#, SyntaxColor.string),
            // Code blocks
            r(#"```.*?```"#, SyntaxColor.string),
            // Bold/italic markers (the markers themselves)
            r(#"\*{1,3}[^\*\n]+\*{1,3}|_{1,3}[^_\n]+_{1,3}"#, SyntaxColor.typeName),
            // Links
            r(#"\[([^\]]+)\]\([^\)]+\)"#, SyntaxColor.keyword),
            // Headings
            r(#"^#{1,6} [^\n]+"#, SyntaxColor.funcName),
            // Blockquotes
            r(#"^> [^\n]+"#, SyntaxColor.comment),
        ].compactMap { $0 }
    }
}
