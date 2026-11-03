import SwiftUI
import UIKit

// MARK: - Layout manager that draws line numbers and the current-line highlight

final class GutterLayoutManager: NSLayoutManager {
    var showNumbers = true
    var numberFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    var numberColor = UIColor.gray
    var activeNumberColor = UIColor.white
    var highlightColor = UIColor.clear
    var caretLocation = -1

    private func lineNumber(at location: Int, in text: NSString) -> Int {
        if location < 0 { return -1 }
        let end = min(location, text.length)
        var n = 1
        var i = 0
        while i < end {
            if text.character(at: i) == 10 { n += 1 }
            i += 1
        }
        return n
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        if let storage = textStorage, caretLocation >= 0 {
            let text = storage.string as NSString
            let length = text.length
            var rect: CGRect?
            if length == 0 || (caretLocation >= length && text.character(at: length - 1) == 10) {
                let extra = extraLineFragmentRect
                if extra.height > 0 { rect = extra }
            } else {
                let loc = min(caretLocation, length - 1)
                let glyph = glyphIndexForCharacter(at: loc)
                rect = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            if let r = rect {
                highlightColor.setFill()
                UIBezierPath(rect: CGRect(x: 0, y: r.minY + origin.y, width: 20000, height: r.height)).fill()
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        if showNumbers { drawNumbers(glyphsToShow, origin) }
    }

    private func drawNumbers(_ glyphsToShow: NSRange, _ origin: CGPoint) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let length = text.length
        let rightEdge = origin.x - 8
        let caretLine = lineNumber(at: caretLocation, in: text)

        func draw(_ n: Int, _ rect: CGRect) {
            let str = "\(n)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: numberFont,
                .foregroundColor: (n == caretLine) ? activeNumberColor : numberColor
            ]
            let size = str.size(withAttributes: attrs)
            let y = origin.y + rect.minY + (rect.height - size.height) / 2
            str.draw(at: CGPoint(x: rightEdge - size.width, y: y), withAttributes: attrs)
        }

        var next = 1
        var first = true
        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, _, glyphRange, _ in
            let ci = self.characterIndexForGlyph(at: glyphRange.location)
            let isStart = ci == 0 || text.character(at: ci - 1) == 10
            if first {
                first = false
                var n = 0
                var i = 0
                while i < ci {
                    if text.character(at: i) == 10 { n += 1 }
                    i += 1
                }
                next = isStart ? n + 1 : n + 2
            }
            if isStart {
                draw(next, rect)
                next += 1
            }
        }

        let extra = extraLineFragmentRect
        if extra.height > 0 {
            var total = 1
            var i = 0
            while i < length {
                if text.character(at: i) == 10 { total += 1 }
                i += 1
            }
            draw(total, extra)
        }
    }
}

// MARK: - Controller used by the toolbar / menu

final class EditorController {
    weak var textView: UITextView?
    var language: Language = .python
    var tabWidth = 4

    func insert(_ text: String, back: Int = 0) {
        guard let tv = textView else { return }
        tv.insertText(text)
        if back > 0,
           let end = tv.selectedTextRange?.end,
           let pos = tv.position(from: end, offset: -back) {
            tv.selectedTextRange = tv.textRange(from: pos, to: pos)
        }
    }

    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }
    func dismissKeyboard() { textView?.resignFirstResponder() }

    func find() {
        guard let tv = textView else { return }
        tv.becomeFirstResponder()
        tv.findInteraction?.presentFindNavigator(showingReplace: true)
    }

    func selectedText() -> String? {
        guard let tv = textView, tv.selectedRange.length > 0 else { return nil }
        return (tv.text as NSString).substring(with: tv.selectedRange)
    }

    private func transformSelectedLines(_ transform: (String) -> String) {
        guard let tv = textView else { return }
        let ns = tv.text as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange)
        let block = ns.substring(with: lineRange)
        let hadTrailing = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailing { lines.removeLast() }
        var replacement = lines.map(transform).joined(separator: "\n")
        if hadTrailing { replacement += "\n" }
        tv.selectedRange = lineRange
        tv.insertText(replacement)
        let len = (replacement as NSString).length - (hadTrailing ? 1 : 0)
        tv.selectedRange = NSRange(location: lineRange.location, length: max(0, len))
    }

    func toggleComment() {
        guard let tv = textView else { return }
        let marker = language == .python ? "# " : "// "
        let bare = marker.trimmingCharacters(in: .whitespaces)
        let ns = tv.text as NSString
        let block = ns.substring(with: ns.lineRange(for: tv.selectedRange))
        let nonEmpty = block.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allCommented = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(bare) }
        transformSelectedLines { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            let indentCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let cut = line.index(line.startIndex, offsetBy: indentCount)
            let indentText = String(line[..<cut])
            var rest = String(line[cut...])
            if allCommented {
                if rest.hasPrefix(marker) {
                    rest.removeFirst(marker.count)
                } else if rest.hasPrefix(bare) {
                    rest.removeFirst(bare.count)
                }
                return indentText + rest
            }
            return indentText + marker + rest
        }
    }

    func indent() {
        guard let tv = textView else { return }
        let unit = String(repeating: " ", count: tabWidth)
        if tv.selectedRange.length == 0 {
            tv.insertText(unit)
        } else {
            transformSelectedLines { $0.isEmpty ? $0 : unit + $0 }
        }
    }

    func outdent() {
        let width = tabWidth
        transformSelectedLines { line in
            var removed = 0
            var result = line
            while removed < width, result.hasPrefix(" ") {
                result.removeFirst()
                removed += 1
            }
            return result
        }
    }
}

// MARK: - SwiftUI wrapper

struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorLine: Int
    @Binding var cursorCol: Int
    var language: Language
    var theme: Theme
    var fontSize: CGFloat
    var showLineNumbers: Bool
    var autoClose: Bool
    var tabWidth: Int
    var controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let storage = NSTextStorage()
        let layout = GutterLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let tv = UITextView(frame: .zero, textContainer: container)
        let c = context.coordinator
        c.textView = tv
        c.layout = layout
        controller.textView = tv
        tv.delegate = c
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.spellCheckingType = .no
        tv.backgroundColor = .clear
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.isFindInteractionEnabled = true
        tv.inputAccessoryView = c.makeAccessory()
        tv.text = text
        c.applyAppearance(tv)
        c.highlight(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        controller.textView = tv
        controller.language = language
        controller.tabWidth = tabWidth
        if tv.text != text {
            tv.text = text
            c.highlight(tv)
        }
        if c.styleKey(self) != c.lastKey {
            c.applyAppearance(tv)
            c.highlight(tv)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor
        weak var textView: UITextView?
        var layout: GutterLayoutManager?
        var lastKey = ""
        private var currentInset: CGFloat = -1

        init(_ parent: CodeEditor) { self.parent = parent }

        func styleKey(_ p: CodeEditor) -> String {
            "\(p.theme.id)-\(p.language.rawValue)-\(p.fontSize)-\(p.showLineNumbers)-\(p.tabWidth)"
        }

        func applyAppearance(_ tv: UITextView) {
            let theme = parent.theme
            lastKey = styleKey(parent)
            tv.tintColor = theme.ui(theme.accent)
            tv.keyboardAppearance = theme.isDark ? .dark : .light
            if let l = layout {
                l.showNumbers = parent.showLineNumbers
                l.numberFont = UIFont.monospacedSystemFont(ofSize: max(10, parent.fontSize - 3), weight: .regular)
                l.numberColor = theme.ui(theme.comment).withAlphaComponent(0.8)
                l.activeNumberColor = theme.ui(theme.text)
                l.highlightColor = theme.ui(theme.text).withAlphaComponent(0.07)
            }
            currentInset = -1
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            highlight(tv)
            tv.setNeedsDisplay()
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            layout?.caretLocation = tv.selectedRange.length == 0 ? tv.selectedRange.location : -1
            tv.setNeedsDisplay()
            reportCursor(tv)
        }

        private func reportCursor(_ tv: UITextView) {
            let ns = tv.text as NSString
            let loc = min(tv.selectedRange.location, ns.length)
            var line = 1
            var lastNewline = -1
            var i = 0
            while i < loc {
                if ns.character(at: i) == 10 {
                    line += 1
                    lastNewline = i
                }
                i += 1
            }
            let col = loc - lastNewline
            DispatchQueue.main.async {
                if self.parent.cursorLine != line { self.parent.cursorLine = line }
                if self.parent.cursorCol != col { self.parent.cursorCol = col }
            }
        }

        // MARK: Typing helpers (auto indent, auto close)

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let ns = tv.text as NSString
            if text == "\n" { return handleReturn(tv, range, ns) }
            guard parent.autoClose, text.count == 1, range.length == 0 else { return true }

            func char(at index: Int) -> String {
                if index < 0 || index >= ns.length { return "" }
                return ns.substring(with: NSRange(location: index, length: 1))
            }
            let next = char(at: range.location)
            let prev = char(at: range.location - 1)
            let prev2 = char(at: range.location - 2)
            let closers = [")", "]", "}"]
            let isQuote = text == "\"" || text == "'"

            if (closers.contains(text) || isQuote) && next == text {
                tv.selectedRange = NSRange(location: range.location + 1, length: 0)
                return false
            }
            let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"]
            guard let close = pairs[text] else { return true }
            if isQuote {
                if prev.rangeOfCharacter(from: .alphanumerics) != nil { return true }
                if prev == text && prev2 == text { return true }
            }
            let nextIsSafe = next.isEmpty || next == "\n" || next == " " || next == "," || next == ":" || next == ";" || closers.contains(next)
            if nextIsSafe {
                tv.insertText(text + close)
                tv.selectedRange = NSRange(location: range.location + 1, length: 0)
                return false
            }
            return true
        }

        private func handleReturn(_ tv: UITextView, _ range: NSRange, _ ns: NSString) -> Bool {
            let lineStart = ns.lineRange(for: NSRange(location: range.location, length: 0)).location
            let before = ns.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
            var indent = String(before.prefix(while: { $0 == " " || $0 == "\t" }))
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            let unit = String(repeating: " ", count: parent.tabWidth)
            let next = range.location < ns.length ? ns.substring(with: NSRange(location: range.location, length: 1)) : ""

            let between = (trimmed.hasSuffix("{") && next == "}")
                || (trimmed.hasSuffix("(") && next == ")")
                || (trimmed.hasSuffix("[") && next == "]")
            if between {
                tv.insertText("\n" + indent + unit + "\n" + indent)
                tv.selectedRange = NSRange(location: range.location + 1 + indent.count + unit.count, length: 0)
                return false
            }
            let opens = (trimmed.hasSuffix(":") && parent.language == .python)
                || trimmed.hasSuffix("{") || trimmed.hasSuffix("(") || trimmed.hasSuffix("[")
            if opens { indent += unit }
            if indent.isEmpty { return true }
            tv.insertText("\n" + indent)
            return false
        }

        // MARK: Syntax highlighting

        func highlight(_ tv: UITextView) {
            guard tv.markedTextRange == nil else { return }
            let theme = parent.theme
            let font = UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            let base: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: theme.ui(theme.text),
                .paragraphStyle: style
            ]
            let storage = tv.textStorage
            let string = storage.string
            let ns = string as NSString
            let full = NSRange(location: 0, length: ns.length)

            storage.beginEditing()
            storage.setAttributes(base, range: full)
            for rule in Highlighter.rules(for: parent.language) {
                rule.regex.enumerateMatches(in: string, options: [], range: full) { match, _, _ in
                    guard let m = match else { return }
                    let role: Theme.Role
                    if let fixed = rule.role {
                        role = fixed
                    } else if let classify = rule.classify {
                        role = classify(ns.substring(with: m.range))
                    } else {
                        return
                    }
                    storage.addAttribute(.foregroundColor, value: theme.ui(theme.hex(for: role)), range: m.range)
                }
            }
            storage.endEditing()
            tv.typingAttributes = base

            var lines = 1
            var i = 0
            while i < ns.length {
                if ns.character(at: i) == 10 { lines += 1 }
                i += 1
            }
            let digits = max(3, String(lines).count)
            let inset: CGFloat = parent.showLineNumbers ? CGFloat(digits) * (parent.fontSize * 0.5) + 22 : 12
            if inset != currentInset {
                currentInset = inset
                tv.textContainerInset = UIEdgeInsets(top: 8, left: inset, bottom: 120, right: 8)
            }
        }

        // MARK: Symbol bar above the keyboard

        private func makeButton(title: String? = nil, image: String? = nil, wide: Bool = false, action: @escaping () -> Void) -> UIButton {
            let button = UIButton(type: .system)
            if let t = title {
                button.setTitle(t, for: .normal)
                button.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .semibold)
            }
            if let img = image {
                button.setImage(UIImage(systemName: img), for: .normal)
            }
            button.setTitleColor(.label, for: .normal)
            button.tintColor = .label
            button.backgroundColor = UIColor.secondarySystemFill
            button.layer.cornerRadius = 6
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: wide ? 46 : 38).isActive = true
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            return button
        }

        func makeAccessory() -> UIView {
            let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 44), inputViewStyle: .keyboard)
            let scroll = UIScrollView()
            scroll.showsHorizontalScrollIndicator = false
            scroll.translatesAutoresizingMaskIntoConstraints = false
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 6
            stack.alignment = .fill
            stack.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(scroll)
            scroll.addSubview(stack)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: bar.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
                stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 5),
                stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -5),
                stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -10)
            ])

            let ctl = parent.controller
            stack.addArrangedSubview(makeButton(image: "arrow.uturn.backward", wide: true) { ctl.undo() })
            stack.addArrangedSubview(makeButton(image: "arrow.uturn.forward", wide: true) { ctl.redo() })
            stack.addArrangedSubview(makeButton(image: "increase.indent", wide: true) { ctl.indent() })
            stack.addArrangedSubview(makeButton(image: "decrease.indent", wide: true) { ctl.outdent() })
            stack.addArrangedSubview(makeButton(image: "text.quote", wide: true) { ctl.toggleComment() })

            let keys: [(String, String, Int)] = [
                ("( )", "()", 1), ("[ ]", "[]", 1), ("{ }", "{}", 1), ("\" \"", "\"\"", 1), ("' '", "''", 1),
                (":", ":", 0), ("=", "=", 0), (".", ".", 0), (",", ",", 0), ("_", "_", 0), ("#", "#", 0),
                ("+", "+", 0), ("-", "-", 0), ("*", "*", 0), ("/", "/", 0), ("\\", "\\", 0),
                ("<", "<", 0), (">", ">", 0), ("!", "!", 0), ("&", "&", 0), ("|", "|", 0), ("%", "%", 0), (";", ";", 0)
            ]
            for key in keys {
                stack.addArrangedSubview(makeButton(title: key.0) { ctl.insert(key.1, back: key.2) })
            }
            stack.addArrangedSubview(makeButton(image: "keyboard.chevron.compact.down", wide: true) { ctl.dismissKeyboard() })
            return bar
        }
    }
}
