import Foundation

enum Highlighter {
    struct Rule {
        let regex: NSRegularExpression
        let role: Theme.Role?
        let classify: ((String) -> Theme.Role)?
    }

    private static func rule(_ pattern: String, _ role: Theme.Role) -> Rule {
        Rule(regex: try! NSRegularExpression(pattern: pattern, options: []), role: role, classify: nil)
    }

    private static func combined(_ pattern: String, _ classify: @escaping (String) -> Theme.Role) -> Rule {
        Rule(regex: try! NSRegularExpression(pattern: pattern, options: []), role: nil, classify: classify)
    }

    static let python: [Rule] = [
        rule(##"\b[A-Za-z_][A-Za-z0-9_]*(?=\()"##, .function),
        rule(##"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"##, .number),
        rule(##"\b(?:print|input|len|range|int|str|float|list|dict|set|tuple|bool|open|type|isinstance|enumerate|zip|map|filter|sum|min|max|abs|sorted|reversed|round|any|all|super|self|cls|object|repr|format|iter|next)\b"##, .builtin),
        rule(##"\b(?:False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield|match|case)\b"##, .keyword),
        rule(##"(?<=def )[A-Za-z_][A-Za-z0-9_]*"##, .function),
        rule(##"(?<=class )[A-Za-z_][A-Za-z0-9_]*"##, .builtin),
        combined(##"(?:[rRbBfFuU]{0,2}(?:"""[\s\S]*?"""|'''[\s\S]*?'''|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'))|#.*"##,
                 { $0.hasPrefix("#") ? .comment : .string })
    ]

    static let javascript: [Rule] = [
        rule(##"\b[A-Za-z_$][A-Za-z0-9_$]*(?=\()"##, .function),
        rule(##"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"##, .number),
        rule(##"\b(?:true|false|null|undefined|NaN|Infinity)\b"##, .number),
        rule(##"\b(?:console|Math|JSON|Object|Array|String|Number|Boolean|Date|Promise|Map|Set|Symbol|Error|RegExp|parseInt|parseFloat|setTimeout|setInterval|clearTimeout|clearInterval|prompt|alert|process)\b"##, .builtin),
        rule(##"\b(?:break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|function|if|import|in|instanceof|let|new|return|super|switch|this|throw|try|typeof|var|void|while|with|yield|async|await|of|static|get|set)\b"##, .keyword),
        rule(##"(?<=function )[A-Za-z_$][A-Za-z0-9_$]*"##, .function),
        rule(##"(?<=class )[A-Za-z_$][A-Za-z0-9_$]*"##, .builtin),
        combined(##""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\[\s\S]|[^`\\])*`|//.*|/\*[\s\S]*?\*/"##,
                 { ($0.hasPrefix("//") || $0.hasPrefix("/*")) ? .comment : .string })
    ]

    static func rules(for language: Language) -> [Rule] {
        language == .python ? python : javascript
    }
}
