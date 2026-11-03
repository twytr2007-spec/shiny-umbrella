import Foundation

enum Highlighter {
    struct Rule {
        let regex: NSRegularExpression
        let role: Theme.Role?
        let classify: ((String) -> Theme.Role)?
    }

    struct Interpolation {
        let open: NSRange
        let close: NSRange
        let inner: NSRange
    }

    struct StringInfo {
        var items: [Interpolation] = []
        var prefixes: [NSRange] = []
    }

    private static func rule(_ pattern: String, _ role: Theme.Role) -> Rule {
        Rule(regex: try! NSRegularExpression(pattern: pattern, options: []), role: role, classify: nil)
    }

    private static func combined(_ regex: NSRegularExpression, _ classify: @escaping (String) -> Theme.Role) -> Rule {
        Rule(regex: regex, role: nil, classify: classify)
    }

    private static let pyStringRegex = try! NSRegularExpression(
        pattern: ##"(?:[rRbBfFuU]{0,2}(?:"""[\s\S]*?"""|'''[\s\S]*?'''|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'))|#.*"##,
        options: [])

    private static let jsStringRegex = try! NSRegularExpression(
        pattern: ##""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\[\s\S]|[^`\\])*`|//.*|/\*[\s\S]*?\*/"##,
        options: [])

    private static func pyClassify(_ s: String) -> Theme.Role {
        s.hasPrefix("#") ? .comment : .string
    }

    private static func jsClassify(_ s: String) -> Theme.Role {
        (s.hasPrefix("//") || s.hasPrefix("/*")) ? .comment : .string
    }

    static let python: [Rule] = [
        rule(##"\b[A-Za-z_][A-Za-z0-9_]*(?=\()"##, .function),
        rule(##"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"##, .number),
        rule(##"\b(?:print|input|len|range|int|str|float|list|dict|set|tuple|bool|open|type|isinstance|enumerate|zip|map|filter|sum|min|max|abs|sorted|reversed|round|any|all|super|self|cls|object|repr|format|iter|next)\b"##, .builtin),
        rule(##"\b(?:False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield|match|case)\b"##, .keyword),
        rule(##"(?<=def )[A-Za-z_][A-Za-z0-9_]*"##, .function),
        rule(##"(?<=class )[A-Za-z_][A-Za-z0-9_]*"##, .builtin),
        combined(pyStringRegex, { pyClassify($0) })
    ]

    static let javascript: [Rule] = [
        rule(##"\b[A-Za-z_$][A-Za-z0-9_$]*(?=\()"##, .function),
        rule(##"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"##, .number),
        rule(##"\b(?:true|false|null|undefined|NaN|Infinity)\b"##, .number),
        rule(##"\b(?:console|Math|JSON|Object|Array|String|Number|Boolean|Date|Promise|Map|Set|Symbol|Error|RegExp|parseInt|parseFloat|setTimeout|setInterval|clearTimeout|clearInterval|prompt|alert|process|require)\b"##, .builtin),
        rule(##"\b(?:break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|function|if|import|in|instanceof|let|new|return|super|switch|this|throw|try|typeof|var|void|while|with|yield|async|await|of|static|get|set)\b"##, .keyword),
        rule(##"(?<=function )[A-Za-z_$][A-Za-z0-9_$]*"##, .function),
        rule(##"(?<=class )[A-Za-z_$][A-Za-z0-9_$]*"##, .builtin),
        combined(jsStringRegex, { jsClassify($0) })
    ]

    static func rules(for language: Language) -> [Rule] {
        language == .python ? python : javascript
    }

    /// Finds `{expr}` inside Python f-strings and `${expr}` inside JavaScript template literals.
    static func interpolations(in text: NSString, language: Language) -> StringInfo {
        var info = StringInfo()
        let isPython = language == .python
        let regex = isPython ? pyStringRegex : jsStringRegex
        let all = NSRange(location: 0, length: text.length)

        regex.enumerateMatches(in: text as String, options: [], range: all) { match, _, _ in
            guard let m = match else { return }
            let r = m.range
            let s = text.substring(with: r)
            let role: Theme.Role = isPython ? pyClassify(s) : jsClassify(s)
            if role != .string { return }
            let u = Array(s.utf16)
            var contentStart = 0
            var contentEnd = u.count

            if isPython {
                var p = 0
                while p < u.count && ((u[p] >= 65 && u[p] <= 90) || (u[p] >= 97 && u[p] <= 122)) { p += 1 }
                guard p < u.count else { return }
                let prefix = (s as NSString).substring(to: p).lowercased()
                if p > 0 { info.prefixes.append(NSRange(location: r.location, length: p)) }
                if !prefix.contains("f") { return }
                let quote = u[p]
                let triple = u.count >= p + 6 && u[p + 1] == quote && u[p + 2] == quote
                let qlen = triple ? 3 : 1
                contentStart = p + qlen
                contentEnd = u.count - qlen
            } else {
                guard u.count >= 2, u[0] == 96 else { return }
                contentStart = 1
                contentEnd = u.count - 1
            }
            if contentEnd < contentStart { return }
            let end = contentEnd

            func closingBrace(from start: Int) -> Int? {
                var depth = 1
                var j = start
                while j < end {
                    if u[j] == 123 {
                        depth += 1
                    } else if u[j] == 125 {
                        depth -= 1
                        if depth == 0 { return j }
                    }
                    j += 1
                }
                return nil
            }

            var i = contentStart
            while i < end {
                let c = u[i]
                if isPython {
                    if c == 123 {
                        if i + 1 < end && u[i + 1] == 123 {
                            i += 2
                        } else if let close = closingBrace(from: i + 1) {
                            info.items.append(Interpolation(
                                open: NSRange(location: r.location + i, length: 1),
                                close: NSRange(location: r.location + close, length: 1),
                                inner: NSRange(location: r.location + i + 1, length: close - i - 1)))
                            i = close + 1
                        } else {
                            i += 1
                        }
                    } else if c == 125 && i + 1 < end && u[i + 1] == 125 {
                        i += 2
                    } else {
                        i += 1
                    }
                } else {
                    if c == 92 {
                        i += 2
                    } else if c == 36 && i + 1 < end && u[i + 1] == 123, let close = closingBrace(from: i + 2) {
                        info.items.append(Interpolation(
                            open: NSRange(location: r.location + i, length: 2),
                            close: NSRange(location: r.location + close, length: 1),
                            inner: NSRange(location: r.location + i + 2, length: close - i - 2)))
                        i = close + 1
                    } else {
                        i += 1
                    }
                }
            }
        }
        return info
    }
}
