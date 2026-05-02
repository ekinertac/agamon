// Syntax highlighter for the file editor — theme-aware, palette-driven.
//
// Token types map to fixed ANSI palette slots so the editor shares the terminal's
// color personality. Slot assignments follow the semantic convention used by most
// well-designed terminal themes (Catppuccin, Dracula, Nord, etc.):
//
//   8  → dim gray     → comments
//   2  → green        → strings
//   4  → blue/purple  → declaration keywords (let, var, func, class …)
//  12  → bright blue  → control-flow keywords (if, for, return …)
//   5  → pink/magenta → constants (true, false, nil, self, None …)
//   3  → yellow       → type names / capitalized identifiers
//   6  → cyan         → function definitions (name after func/def/fn)
//  11  → bright yel   → function call sites / method references
//  13  → bright mag   → decorators / attributes (@, #[…])
//   9  → bright red   → numbers
//
// Rule priority: later rules overwrite earlier ones, so comments win over
// keywords (which might appear inside a comment) and strings win over keywords.
//
// Related: FileEditorView.swift (Coordinator calls apply after every storage change),
//          TerminalTheme.swift (provides nsColorPalette used here).

import AppKit

// MARK: - Language

enum SyntaxLanguage {
    case swift, python, javascript, typescript, json, yaml, shell, ruby, go, rust, markdown

    static func detect(fileExtension ext: String) -> SyntaxLanguage? {
        switch ext.lowercased() {
        case "swift":                      return .swift
        case "py":                         return .python
        case "js", "jsx", "mjs", "cjs":   return .javascript
        case "ts", "tsx":                  return .typescript
        case "json", "jsonc":              return .json
        case "yaml", "yml":                return .yaml
        case "sh", "bash", "zsh", "fish", "command": return .shell
        case "rb":                         return .ruby
        case "go":                         return .go
        case "rs":                         return .rust
        case "md", "markdown":             return .markdown
        default:                           return nil
        }
    }
}

// MARK: - Token

// Semantic role of a matched text span. Maps to a palette slot in SyntaxPalette.
enum SyntaxToken {
    case comment, string
    case keyword, controlFlow
    case constant         // true / false / nil / self / None / undefined
    case typeName         // capitalized identifier
    case funcDef          // function name at definition site
    case funcCall         // function/method name at call site
    case decorator        // @attr, #[derive], preprocessor
    case number
}

// MARK: - Palette

// Resolves SyntaxToken → NSColor using a terminal theme's 16-color palette.
struct SyntaxPalette {
    let comment:     NSColor
    let string:      NSColor
    let keyword:     NSColor
    let controlFlow: NSColor
    let constant:    NSColor
    let typeName:    NSColor
    let funcDef:     NSColor
    let funcCall:    NSColor
    let decorator:   NSColor
    let number:      NSColor
    let base:        NSColor  // normal text fallback

    init(nsColors p: [NSColor], foreground: NSColor) {
        let safe: (Int) -> NSColor = { i in i < p.count ? p[i] : foreground }
        comment     = safe(8)
        string      = safe(2)
        keyword     = safe(4)
        controlFlow = safe(12)
        constant    = safe(5)
        typeName    = safe(3)
        funcDef     = safe(6)
        funcCall    = safe(11)
        decorator   = safe(13)
        number      = safe(9)
        base        = foreground
    }

    func color(for token: SyntaxToken) -> NSColor {
        switch token {
        case .comment:     return comment
        case .string:      return string
        case .keyword:     return keyword
        case .controlFlow: return controlFlow
        case .constant:    return constant
        case .typeName:    return typeName
        case .funcDef:     return funcDef
        case .funcCall:    return funcCall
        case .decorator:   return decorator
        case .number:      return number
        }
    }
}

// MARK: - Rule

private struct SyntaxRule {
    let regex: NSRegularExpression
    let token: SyntaxToken
    let captureGroup: Int
}

// MARK: - SyntaxHighlighter

struct SyntaxHighlighter {
    private static var ruleCache: [String: [SyntaxRule]] = [:]

    static func apply(to storage: NSTextStorage, language: SyntaxLanguage?,
                      palette: SyntaxPalette, baseFont: NSFont) {
        guard let language else { return }
        let rules = cachedRules(for: language)
        let text  = storage.string
        let full  = NSRange(location: 0, length: (text as NSString).length)

        storage.beginEditing()
        storage.addAttributes([.foregroundColor: palette.base, .font: baseFont], range: full)
        for rule in rules {
            rule.regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                let r = rule.captureGroup == 0 ? match.range : match.range(at: rule.captureGroup)
                guard r.location != NSNotFound, r.length > 0 else { return }
                storage.addAttribute(.foregroundColor, value: palette.color(for: rule.token), range: r)
            }
        }
        storage.endEditing()
    }

    // MARK: - Cache

    private static func cachedRules(for language: SyntaxLanguage) -> [SyntaxRule] {
        let key = "\(language)"
        if let hit = ruleCache[key] { return hit }
        let built = buildRules(for: language)
        ruleCache[key] = built
        return built
    }

    private static func r(_ pattern: String, _ token: SyntaxToken, group: Int = 0) -> SyntaxRule? {
        guard let rx = try? NSRegularExpression(pattern: pattern,
                                                 options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        return SyntaxRule(regex: rx, token: token, captureGroup: group)
    }

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

    // MARK: - Swift

    private static func swiftRules() -> [SyntaxRule] { [
        // Capitalized identifiers → type names (overridden by keywords below when exact match)
        r(#"\b[A-Z][A-Za-z0-9_]*\b"#, .typeName),
        // Numbers
        r(#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?\b|0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+"#, .number),
        // Attributes
        r(#"@\w+"#, .decorator),
        // Declaration + modifier keywords
        r(#"\b(?:let|var|func|class|struct|enum|protocol|extension|import|typealias|associatedtype|subscript|init|deinit|operator|static|final|private|public|internal|fileprivate|open|override|mutating|nonmutating|lazy|weak|unowned|inout|isolated|nonisolated|async|await|throws|rethrows|throw|try|catch|actor|some|any|indirect|convenience|required|dynamic|optional|prefix|postfix|infix|where)\b"#,
          .keyword),
        // Control flow
        r(#"\b(?:if|else|guard|switch|case|default|for|in|while|break|continue|return|defer|repeat|do|fallthrough|is|as)\b"#,
          .controlFlow),
        // Function call sites: word followed by (
        r(#"\b([a-z_]\w*)\s*(?=\()"#, .funcCall, group: 1),
        // Function definition name
        r(#"(?<=\bfunc\s)\w+"#, .funcDef),
        // Constants (win over keyword catch-all)
        r(#"\b(?:true|false|nil|self|super|Self|_)\b"#, .constant),
        // Strings
        r(#""(?:[^"\\]|\\.)*""#, .string),
        r(#""{3}[\s\S]*?"{3}"#, .string),
        // Comments last — highest priority
        r(#"\/\/[^\n]*"#, .comment),
        r(#"\/\*[\s\S]*?\*\/"#, .comment),
    ].compactMap { $0 } }

    // MARK: - Python

    private static func pythonRules() -> [SyntaxRule] { [
        r(#"\b[A-Z][A-Za-z0-9_]*\b"#, .typeName),
        r(#"\b\d[\d_]*(?:\.\d[\d_]*)?\b"#, .number),
        r(#"@\w+"#, .decorator),
        r(#"\b(?:def|class|import|from|as|lambda|yield|global|nonlocal|del|assert|with|raise|pass|async|await)\b"#,
          .keyword),
        r(#"\b(?:if|elif|else|for|while|break|continue|return|try|except|finally|in|not|and|or|is)\b"#,
          .controlFlow),
        r(#"\b([a-z_]\w*)\s*(?=\()"#, .funcCall, group: 1),
        r(#"(?<=\bdef\s)\w+"#, .funcDef),
        r(#"\b(?:True|False|None|self|cls|super)\b"#, .constant),
        r(#"(?:f|r|b|rb|fr)?'(?:[^'\\]|\\.)*'"#, .string),
        r(#"(?:f|r|b|rb|fr)?"(?:[^"\\]|\\.)*""#, .string),
        r(#"'{3}[\s\S]*?'{3}"#, .string),
        r(#""{3}[\s\S]*?"{3}"#, .string),
        r(#"#[^\n]*"#, .comment),
    ].compactMap { $0 } }

    // MARK: - JavaScript

    private static func jsRules() -> [SyntaxRule] { [
        r(#"\b[A-Z][A-Za-z0-9_]*\b"#, .typeName),
        r(#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?\b|0x[0-9a-fA-F]+\b"#, .number),
        r(#"@\w+"#, .decorator),
        r(#"\b(?:const|let|var|function|class|extends|import|export|from|async|await|static|get|set|typeof|instanceof|void|delete|new|of|yield|in|debugger)\b"#,
          .keyword),
        r(#"\b(?:if|else|switch|case|default|for|while|break|continue|return|throw|try|catch|finally|do)\b"#,
          .controlFlow),
        r(#"\b([a-z_$]\w*)\s*(?=\()"#, .funcCall, group: 1),
        r(#"(?<=\bfunction\s)\w+"#, .funcDef),
        r(#"\b(?:true|false|null|undefined|NaN|Infinity|this|super|arguments)\b"#, .constant),
        r(#"'(?:[^'\\]|\\.)*'"#, .string),
        r(#""(?:[^"\\]|\\.)*""#, .string),
        r(#"`(?:[^`\\]|\\.)*`"#, .string),
        r(#"\/\/[^\n]*"#, .comment),
        r(#"\/\*[\s\S]*?\*\/"#, .comment),
    ].compactMap { $0 } }

    // MARK: - TypeScript (superset of JS)

    private static func tsRules() -> [SyntaxRule] {
        var rules = jsRules().filter { rule in
            // Replace the JS keyword rule with TS superset below
            !rule.regex.pattern.contains("const|let|var|function|class|extends|import")
        }
        return rules + [
            r(#"\b(?:const|let|var|function|class|extends|implements|interface|type|enum|namespace|module|declare|abstract|import|export|from|async|await|static|get|set|typeof|instanceof|void|delete|new|of|yield|in|readonly|keyof|infer|never|unknown|any|as|is|satisfies|override|debugger)\b"#,
              .keyword),
        ].compactMap { $0 }
    }

    // MARK: - JSON

    private static func jsonRules() -> [SyntaxRule] { [
        r(#"\b(?:true|false|null)\b"#, .constant),
        r(#"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number),
        // Object keys
        r(#""(?:[^"\\]|\\.)*"(?=\s*:)"#, .funcDef),
        // String values
        r(#""(?:[^"\\]|\\.)*""#, .string),
    ].compactMap { $0 } }

    // MARK: - YAML

    private static func yamlRules() -> [SyntaxRule] { [
        r(#"\b(?:true|false|null|yes|no|on|off|~)\b"#, .constant),
        r(#"-?\d+(?:\.\d+)?\b"#, .number),
        // Keys at the start of a line
        r(#"^[ \t]*([\w\-\.]+)(?=\s*:)"#, .funcDef, group: 1),
        r(#"'(?:[^'\\]|\\.)*'"#, .string),
        r(#""(?:[^"\\]|\\.)*""#, .string),
        // Anchors and aliases
        r(#"[&*]\w+"#, .decorator),
        r(#"#[^\n]*"#, .comment),
    ].compactMap { $0 } }

    // MARK: - Shell

    private static func shellRules() -> [SyntaxRule] { [
        r(#"\b\d+\b"#, .number),
        r(#"\b(?:if|then|else|elif|fi|for|do|done|while|until|case|esac|in|select)\b"#,
          .controlFlow),
        r(#"\b(?:function|return|exit|local|export|readonly|source|declare|shift|set|unset|eval|exec|builtin|command)\b"#,
          .keyword),
        // Variables $VAR, ${VAR}, $1, $@, etc.
        r(#"\$\{[^}]+\}|\$[a-zA-Z_]\w*|\$[0-9@#?*!$\-]"#, .constant),
        r(#"'(?:[^'\\]|\\.)*'"#, .string),
        r(#""(?:[^"\\]|\\.)*""#, .string),
        r(#"`[^`]*`"#, .string),
        // Shebang
        r(#"^#!.*"#, .decorator),
        r(#"#[^\n]*"#, .comment),
    ].compactMap { $0 } }

    // MARK: - Ruby

    private static func rubyRules() -> [SyntaxRule] { [
        r(#"\b[A-Z][A-Za-z0-9_]*\b"#, .typeName),
        r(#"\b\d[\d_]*(?:\.\d[\d_]*)?\b"#, .number),
        r(#":\w+"#, .decorator),       // symbols
        r(#"@{1,2}\w+"#, .decorator),  // instance/class variables
        r(#"\b(?:def|class|module|end|include|extend|require|require_relative|attr_reader|attr_writer|attr_accessor|private|protected|public|lambda|proc|yield|raise|rescue|ensure|begin|alias|defined|freeze)\b"#,
          .keyword),
        r(#"\b(?:if|unless|elsif|else|then|case|when|while|until|for|do|break|next|return|retry|redo|in)\b"#,
          .controlFlow),
        r(#"\b([a-z_]\w*)\s*(?=\()"#, .funcCall, group: 1),
        r(#"(?<=\bdef\s)\w+"#, .funcDef),
        r(#"\b(?:true|false|nil|self|super)\b"#, .constant),
        r(#"'(?:[^'\\]|\\.)*'"#, .string),
        r(#""(?:[^"\\]|\\.)*""#, .string),
        r(#"#[^\n]*"#, .comment),
    ].compactMap { $0 } }

    // MARK: - Go

    private static func goRules() -> [SyntaxRule] { [
        r(#"\b[A-Z][A-Za-z0-9_]*\b"#, .typeName),
        r(#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?\b|0x[0-9a-fA-F]+\b"#, .number),
        r(#"\b(?:func|var|const|type|struct|interface|map|chan|package|import|go|defer|select|make|new|len|cap|append|copy|delete|close|panic|recover|int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|uintptr|float32|float64|complex64|complex128|string|bool|byte|rune|error|any)\b"#,
          .keyword),
        r(#"\b(?:if|else|switch|case|default|for|range|break|continue|return|goto|fallthrough)\b"#,
          .controlFlow),
        r(#"\b([a-z_]\w*)\s*(?=\()"#, .funcCall, group: 1),
        r(#"(?<=\bfunc\s)\w+"#, .funcDef),
        r(#"\b(?:true|false|nil|iota)\b"#, .constant),
        r(#"`[^`]*`"#, .string),
        r(#""(?:[^"\\]|\\.)*""#, .string),
        r(#"\/\/[^\n]*"#, .comment),
        r(#"\/\*[\s\S]*?\*\/"#, .comment),
    ].compactMap { $0 } }

    // MARK: - Rust

    private static func rustRules() -> [SyntaxRule] { [
        r(#"\b[A-Z][A-Za-z0-9_]*\b"#, .typeName),
        r(#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?\b|0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+"#,
          .number),
        // Proc macros and attributes
        r(#"#!?\[[\s\S]*?\]"#, .decorator),
        r(#"\b(?:fn|let|mut|const|static|type|struct|enum|trait|impl|use|pub|mod|crate|extern|unsafe|dyn|impl|where|async|await|move|ref|in|override|abstract|virtual|become|box|do|final|macro|yield|try)\b"#,
          .keyword),
        r(#"\b(?:if|else|match|while|loop|for|break|continue|return|where)\b"#,
          .controlFlow),
        r(#"\b([a-z_]\w*)\s*(?=\(|!)"#, .funcCall, group: 1),  // includes macros!
        r(#"(?<=\bfn\s)\w+"#, .funcDef),
        r(#"\b(?:true|false|None|Some|Ok|Err|self|super|Self)\b"#, .constant),
        r(#""(?:[^"\\]|\\.)*""#, .string),
        r(#"\/\/[^\n]*"#, .comment),
        r(#"\/\*[\s\S]*?\*\/"#, .comment),
    ].compactMap { $0 } }

    // MARK: - Markdown

    private static func markdownRules() -> [SyntaxRule] { [
        // Fenced code blocks
        r(#"```[\s\S]*?```|~~~[\s\S]*?~~~"#, .string),
        // Inline code
        r(#"`[^`\n]+`"#, .string),
        // Bold
        r(#"\*{2}[^\*\n]+\*{2}|_{2}[^_\n]+_{2}"#, .keyword),
        // Italic
        r(#"\*[^\*\n]+\*|_[^_\n]+_"#, .funcCall),
        // Links and images [text](url)
        r(#"!?\[([^\]]+)\]\([^\)]*\)"#, .constant),
        // Headings
        r(#"^#{1,6} [^\n]+"#, .funcDef),
        // Blockquotes
        r(#"^> [^\n]+"#, .comment),
        // Horizontal rules
        r(#"^[-*_]{3,}\s*$"#, .decorator),
    ].compactMap { $0 } }
}
