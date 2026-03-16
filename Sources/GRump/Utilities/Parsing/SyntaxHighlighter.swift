import SwiftUI

// MARK: - Syntax Highlighter

/// A zero-dependency, regex-based syntax highlighter for code blocks.
/// Supports keywords, strings, comments, numbers, and type detection
/// for Swift, Python, JavaScript/TypeScript, Go, Rust, Java, C/C++, and shell.
struct SyntaxHighlighter {
    let language: String

    enum TokenKind {
        case plain
        case keyword
        case string
        case comment
        case number
        case type
        case decorator  // @attributes, #directives, decorators
    }

    struct Token {
        let text: String
        let kind: TokenKind
    }

    // MARK: - Public API

    func highlight(_ line: String) -> [Token] {
        guard !line.isEmpty else { return [Token(text: " ", kind: .plain)] }

        var tokens: [Token] = []
        var remaining = line[line.startIndex...]

        // Check for line comment prefix
        let commentPrefix = lineCommentPrefix
        if let prefix = commentPrefix, remaining.hasPrefix(prefix) {
            return [Token(text: String(remaining), kind: .comment)]
        }

        while !remaining.isEmpty {
            // String literals
            if remaining.first == "\"" || remaining.first == "'" {
                let quote = remaining.first!
                let stringToken = consumeString(from: &remaining, quote: quote)
                tokens.append(stringToken)
                continue
            }

            // Backtick strings (JS template literals)
            if remaining.first == "`" && isJSFamily {
                let stringToken = consumeString(from: &remaining, quote: "`")
                tokens.append(stringToken)
                continue
            }

            // Line comments (// or #)
            if let prefix = commentPrefix, remaining.hasPrefix(prefix) {
                tokens.append(Token(text: String(remaining), kind: .comment))
                remaining = remaining[remaining.endIndex...]
                continue
            }

            // Block comment start /* */
            if remaining.hasPrefix("/*") {
                if let endRange = remaining.range(of: "*/") {
                    let commentText = remaining[remaining.startIndex..<endRange.upperBound]
                    tokens.append(Token(text: String(commentText), kind: .comment))
                    remaining = remaining[endRange.upperBound...]
                } else {
                    // Rest of line is comment
                    tokens.append(Token(text: String(remaining), kind: .comment))
                    remaining = remaining[remaining.endIndex...]
                }
                continue
            }

            // Numbers
            if let digit = remaining.first, digit.isNumber || (digit == "." && remaining.count > 1 && remaining[remaining.index(after: remaining.startIndex)].isNumber) {
                let numToken = consumeNumber(from: &remaining)
                tokens.append(numToken)
                continue
            }

            // Words (identifiers / keywords)
            if let first = remaining.first, first.isLetter || first == "_" || first == "$" || first == "@" {
                let word = consumeWord(from: &remaining)
                let kind = classifyWord(word)
                tokens.append(Token(text: word, kind: kind))
                continue
            }

            // Other characters (operators, punctuation)
            let char = remaining[remaining.startIndex]
            tokens.append(Token(text: String(char), kind: .plain))
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        return tokens
    }

    // MARK: - Color Palette

    static func color(for kind: TokenKind, scheme: ColorScheme) -> Color {
        switch kind {
        case .plain:
            return scheme == .dark
                ? Color(red: 0.847, green: 0.820, blue: 1.000)
                : Color(red: 0.15, green: 0.15, blue: 0.20)
        case .keyword:
            return scheme == .dark
                ? Color(red: 0.776, green: 0.471, blue: 1.0)
                : Color(red: 0.55, green: 0.25, blue: 0.85)
        case .string:
            return scheme == .dark
                ? Color(red: 0.380, green: 0.820, blue: 0.557)
                : Color(red: 0.15, green: 0.55, blue: 0.30)
        case .comment:
            return scheme == .dark
                ? Color(red: 0.45, green: 0.45, blue: 0.55)
                : Color(red: 0.45, green: 0.50, blue: 0.55)
        case .number:
            return scheme == .dark
                ? Color(red: 0.835, green: 0.608, blue: 0.365)
                : Color(red: 0.70, green: 0.40, blue: 0.15)
        case .type:
            return scheme == .dark
                ? Color(red: 0.38, green: 0.73, blue: 0.96)
                : Color(red: 0.15, green: 0.45, blue: 0.75)
        case .decorator:
            return scheme == .dark
                ? Color(red: 0.95, green: 0.75, blue: 0.30)
                : Color(red: 0.70, green: 0.50, blue: 0.10)
        }
    }

    // MARK: - Consume Helpers

    private func consumeString(from remaining: inout Substring, quote: Character) -> Token {
        var result = String(remaining.first!)
        remaining = remaining[remaining.index(after: remaining.startIndex)...]

        while !remaining.isEmpty {
            let char = remaining[remaining.startIndex]
            result.append(char)
            remaining = remaining[remaining.index(after: remaining.startIndex)...]

            if char == "\\" && !remaining.isEmpty {
                // Escaped character
                result.append(remaining[remaining.startIndex])
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
                continue
            }

            if char == quote {
                break
            }
        }

        return Token(text: result, kind: .string)
    }

    private func consumeNumber(from remaining: inout Substring) -> Token {
        var result = ""
        var hasDot = false

        // Handle hex prefix 0x
        if remaining.hasPrefix("0x") || remaining.hasPrefix("0X") {
            result += String(remaining.prefix(2))
            remaining = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...]
            while !remaining.isEmpty, let ch = remaining.first, ch.isHexDigit || ch == "_" {
                result.append(ch)
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
            }
            return Token(text: result, kind: .number)
        }

        while !remaining.isEmpty {
            let ch = remaining[remaining.startIndex]
            if ch.isNumber || ch == "_" {
                result.append(ch)
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
            } else if ch == "." && !hasDot {
                hasDot = true
                result.append(ch)
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
            } else {
                break
            }
        }

        // Suffixes like f, d, L, etc.
        if let suffix = remaining.first, (suffix == "f" || suffix == "d" || suffix == "L" || suffix == "l") {
            result.append(suffix)
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        return Token(text: result, kind: .number)
    }

    private func consumeWord(from remaining: inout Substring) -> String {
        var word = ""
        while !remaining.isEmpty {
            let ch = remaining[remaining.startIndex]
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "$" || ch == "@" {
                word.append(ch)
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
            } else {
                break
            }
        }
        return word
    }

    private func classifyWord(_ word: String) -> TokenKind {
        // Decorators: @Something in Swift/Python/Java/TS
        if word.hasPrefix("@") && word.count > 1 { return .decorator }
        if keywords.contains(word) { return .keyword }
        if typeNames.contains(word) { return .type }
        // Heuristic: capitalized words that look like type names
        if let first = word.first, first.isUppercase && word.count > 1 && !keywords.contains(word) {
            return .type
        }
        return .plain
    }

    // MARK: - Language Configuration

    private var lineCommentPrefix: String? {
        switch lang {
        case .swift, .go, .rust, .java, .c, .js, .css: return "//"
        case .python, .shell, .ruby, .yaml, .dockerfile: return "#"
        case .sql: return "--"
        case .html: return nil // HTML uses <!-- --> block comments
        case .unknown: return nil
        }
    }

    private var isJSFamily: Bool {
        lang == .js
    }

    private enum Lang {
        case swift, python, js, go, rust, java, c, shell, ruby, sql, yaml, html, css, dockerfile, unknown
    }

    private var lang: Lang {
        switch language.lowercased() {
        case "swift": return .swift
        case "python", "py": return .python
        case "javascript", "js", "typescript", "ts", "jsx", "tsx": return .js
        case "go", "golang": return .go
        case "rust", "rs": return .rust
        case "java", "kotlin", "kt": return .java
        case "c", "cpp", "c++", "h", "hpp", "objc", "objective-c", "cs", "csharp": return .c
        case "bash", "sh", "zsh", "shell", "fish": return .shell
        case "ruby", "rb": return .ruby
        case "sql", "mysql", "postgresql", "postgres", "sqlite": return .sql
        case "yaml", "yml", "toml": return .yaml
        case "html", "xml", "svg", "jsx": return .html
        case "css", "scss", "sass", "less": return .css
        case "dockerfile", "docker": return .dockerfile
        default: return .unknown
        }
    }

    private var keywords: Set<String> {
        switch lang {
        case .swift:
            return ["func", "var", "let", "class", "struct", "enum", "protocol", "extension",
                    "import", "return", "if", "else", "guard", "switch", "case", "default",
                    "for", "while", "in", "self", "Self", "true", "false", "nil",
                    "private", "public", "internal", "fileprivate", "open", "static", "override",
                    "throws", "throw", "rethrows", "async", "await", "try", "catch", "do",
                    "break", "continue", "where", "typealias", "associatedtype", "some", "any",
                    "mutating", "nonmutating", "init", "deinit", "subscript", "convenience",
                    "required", "final", "lazy", "weak", "unowned", "inout", "defer",
                    "as", "is", "super", "get", "set", "willSet", "didSet"]
        case .python:
            return ["def", "class", "import", "from", "return", "if", "elif", "else",
                    "for", "while", "in", "try", "except", "finally", "with", "as",
                    "True", "False", "None", "self", "lambda", "yield", "async", "await",
                    "raise", "pass", "break", "continue", "and", "or", "not", "is",
                    "global", "nonlocal", "del", "assert", "print"]
        case .js:
            return ["function", "const", "let", "var", "class", "return", "if", "else",
                    "for", "while", "do", "import", "export", "from", "default", "as",
                    "async", "await", "try", "catch", "finally", "throw", "new", "this",
                    "true", "false", "null", "undefined", "typeof", "instanceof",
                    "interface", "type", "enum", "extends", "implements", "static",
                    "switch", "case", "break", "continue", "of", "in", "yield",
                    "void", "delete", "super", "readonly", "abstract", "private", "public",
                    "protected", "declare", "module", "namespace", "keyof"]
        case .go:
            return ["func", "var", "const", "type", "struct", "interface", "package", "import",
                    "return", "if", "else", "for", "range", "switch", "case", "default",
                    "break", "continue", "go", "defer", "select", "chan", "map",
                    "true", "false", "nil", "make", "new", "len", "cap", "append",
                    "fallthrough", "goto"]
        case .rust:
            return ["fn", "let", "mut", "const", "struct", "enum", "impl", "trait",
                    "use", "mod", "pub", "crate", "super", "self", "Self",
                    "return", "if", "else", "match", "for", "while", "loop",
                    "true", "false", "as", "in", "ref", "move", "async", "await",
                    "where", "type", "dyn", "unsafe", "extern", "static"]
        case .java:
            return ["class", "interface", "enum", "extends", "implements", "abstract",
                    "public", "private", "protected", "static", "final", "void",
                    "return", "if", "else", "for", "while", "do", "switch", "case",
                    "break", "continue", "default", "try", "catch", "finally", "throw",
                    "throws", "new", "this", "super", "import", "package",
                    "true", "false", "null", "instanceof", "synchronized", "volatile"]
        case .c:
            return ["auto", "break", "case", "char", "const", "continue", "default", "do",
                    "double", "else", "enum", "extern", "float", "for", "goto", "if",
                    "int", "long", "register", "return", "short", "signed", "sizeof",
                    "static", "struct", "switch", "typedef", "union", "unsigned", "void",
                    "volatile", "while", "include", "define", "ifdef", "ifndef", "endif",
                    "class", "namespace", "template", "typename", "virtual", "override",
                    "public", "private", "protected", "new", "delete", "using",
                    "true", "false", "nullptr", "NULL", "this"]
        case .shell:
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                    "case", "esac", "in", "function", "return", "exit", "echo", "printf",
                    "local", "export", "source", "alias", "unalias", "set", "unset",
                    "true", "false", "cd", "ls", "grep", "awk", "sed", "cat", "chmod",
                    "mkdir", "rm", "cp", "mv"]
        case .ruby:
            return ["def", "class", "module", "end", "if", "elsif", "else", "unless",
                    "while", "until", "for", "do", "begin", "rescue", "ensure",
                    "return", "yield", "raise", "require", "include", "extend",
                    "true", "false", "nil", "self", "super", "puts", "print",
                    "attr_reader", "attr_writer", "attr_accessor", "private", "public",
                    "protected", "lambda", "proc", "block_given?"]
        case .sql:
            return ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE",
                    "CREATE", "ALTER", "DROP", "TABLE", "INDEX", "VIEW", "DATABASE",
                    "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AS", "AND", "OR",
                    "NOT", "IN", "IS", "NULL", "LIKE", "BETWEEN", "EXISTS", "HAVING",
                    "GROUP", "BY", "ORDER", "ASC", "DESC", "LIMIT", "OFFSET", "UNION",
                    "SET", "VALUES", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT",
                    "UNIQUE", "DEFAULT", "CHECK", "CASCADE", "IF", "ELSE", "THEN", "END",
                    "CASE", "WHEN", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION",
                    "select", "from", "where", "insert", "into", "update", "delete",
                    "create", "alter", "drop", "table", "join", "left", "right", "inner",
                    "on", "as", "and", "or", "not", "in", "is", "null", "like", "between",
                    "group", "by", "order", "asc", "desc", "limit", "offset", "having",
                    "set", "values", "primary", "key", "foreign", "references", "unique",
                    "default", "exists", "union", "case", "when", "then", "end", "begin"]
        case .yaml:
            return ["true", "false", "null", "yes", "no", "on", "off"]
        case .html:
            return ["div", "span", "p", "a", "img", "h1", "h2", "h3", "h4", "h5", "h6",
                    "ul", "ol", "li", "table", "tr", "td", "th", "form", "input", "button",
                    "script", "style", "link", "meta", "head", "body", "html", "section",
                    "header", "footer", "nav", "main", "article", "aside",
                    "class", "id", "href", "src", "alt", "type", "name", "value", "placeholder"]
        case .css:
            return ["display", "position", "width", "height", "margin", "padding", "border",
                    "color", "background", "font", "text", "flex", "grid", "align", "justify",
                    "none", "block", "inline", "relative", "absolute", "fixed", "sticky",
                    "important", "inherit", "initial", "auto", "solid", "dashed",
                    "hover", "focus", "active", "before", "after", "first", "last", "nth"]
        case .dockerfile:
            return ["FROM", "RUN", "CMD", "ENTRYPOINT", "COPY", "ADD", "ENV", "ARG",
                    "EXPOSE", "VOLUME", "WORKDIR", "USER", "LABEL", "HEALTHCHECK",
                    "SHELL", "STOPSIGNAL", "ONBUILD", "AS"]
        case .unknown:
            return []
        }
    }

    private var typeNames: Set<String> {
        switch lang {
        case .swift:
            return ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary",
                    "Set", "Optional", "Result", "Error", "Any", "AnyObject", "Void",
                    "CGFloat", "CGPoint", "CGSize", "CGRect", "URL", "Data", "Date",
                    "View", "Color", "Text", "Image", "Button", "VStack", "HStack", "ZStack"]
        case .python:
            return ["int", "float", "str", "bool", "list", "dict", "set", "tuple",
                    "None", "Exception", "TypeError", "ValueError", "object", "range"]
        case .js:
            return ["String", "Number", "Boolean", "Array", "Object", "Map", "Set",
                    "Promise", "Date", "Error", "RegExp", "Symbol", "BigInt",
                    "HTMLElement", "React", "Component", "FC", "JSX", "Node"]
        case .go:
            return ["string", "int", "int8", "int16", "int32", "int64",
                    "uint", "uint8", "uint16", "uint32", "uint64",
                    "float32", "float64", "bool", "byte", "rune", "error",
                    "any", "comparable"]
        case .rust:
            return ["String", "str", "i8", "i16", "i32", "i64", "i128", "isize",
                    "u8", "u16", "u32", "u64", "u128", "usize",
                    "f32", "f64", "bool", "char", "Vec", "Box", "Option", "Result",
                    "Rc", "Arc", "HashMap", "HashSet"]
        case .java:
            return ["String", "int", "long", "double", "float", "boolean", "char", "byte",
                    "Integer", "Long", "Double", "Float", "Boolean", "Character",
                    "List", "Map", "Set", "ArrayList", "HashMap", "HashSet",
                    "Object", "Exception", "Thread", "Runnable"]
        case .c:
            return ["int", "char", "float", "double", "long", "short", "unsigned", "signed",
                    "void", "bool", "size_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t",
                    "int8_t", "int16_t", "int32_t", "int64_t", "string", "vector",
                    "map", "set", "pair", "shared_ptr", "unique_ptr"]
        case .shell:
            return []
        case .ruby:
            return ["Integer", "Float", "String", "Array", "Hash", "Symbol", "Regexp",
                    "Class", "Module", "Object", "NilClass", "TrueClass", "FalseClass"]
        case .sql:
            return ["INTEGER", "VARCHAR", "TEXT", "BOOLEAN", "TIMESTAMP", "DATE", "FLOAT",
                    "DECIMAL", "BIGINT", "SMALLINT", "SERIAL", "UUID", "JSONB", "JSON",
                    "integer", "varchar", "text", "boolean", "timestamp", "date", "float",
                    "decimal", "bigint", "smallint", "serial", "uuid", "jsonb", "json"]
        case .yaml, .html, .css, .dockerfile:
            return []
        case .unknown:
            return []
        }
    }
}
