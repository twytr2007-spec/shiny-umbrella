import SwiftUI
import UIKit

struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    var language: Language
    var theme: Theme
    var fontSize: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        let c = context.coordinator
        c.textView = tv
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
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        tv.inputAccessoryView = c.makeAccessory()
        tv.text = text
        c.applyAppearance(tv)
        c.highlight(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if tv.text != text {
            tv.text = text
            c.highlight(tv)
        }
        let key = "\(theme.id)-\(language.rawValue)-\(fontSize)"
        if key != c.lastKey {
            c.applyAppearance(tv)
            c.highlight(tv)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor
        weak var textView: UITextView?
        var lastKey = ""

        init(_ parent: CodeEditor) { self.parent = parent }

        func applyAppearance(_ tv: UITextView) {
            lastKey = "\(parent.theme.id)-\(parent.language.rawValue)-\(parent.fontSize)"
            tv.tintColor = parent.theme.ui(parent.theme.accent)
            tv.keyboardAppearance = parent.theme.isDark ? .dark : .light
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            highlight(tv)
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            let ns = tv.text as NSString
            let lineStart = ns.lineRange(for: NSRange(location: range.location, length: 0)).location
            let before = ns.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
            var indent = String(before.prefix(while: { $0 == " " || $0 == "\t" }))
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":") || trimmed.hasSuffix("{") || trimmed.hasSuffix("(") || trimmed.hasSuffix("[") {
                indent += "    "
            }
            if indent.isEmpty { return true }
            tv.insertText("\n" + indent)
            return false
        }

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
        }

        // MARK: Symbol bar above the keyboard

        private struct Key {
            let label: String
            let insert: String
            let back: Int
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

            let keys: [Key] = [
                Key(label: "⇥", insert: "    ", back: 0),
                Key(label: "( )", insert: "()", back: 1),
                Key(label: "[ ]", insert: "[]", back: 1),
                Key(label: "{ }", insert: "{}", back: 1),
                Key(label: "\" \"", insert: "\"\"", back: 1),
                Key(label: "' '", insert: "''", back: 1),
                Key(label: ":", insert: ":", back: 0),
                Key(label: "=", insert: "=", back: 0),
                Key(label: ".", insert: ".", back: 0),
                Key(label: ",", insert: ",", back: 0),
                Key(label: "_", insert: "_", back: 0),
                Key(label: "#", insert: "#", back: 0),
                Key(label: "+", insert: "+", back: 0),
                Key(label: "-", insert: "-", back: 0),
                Key(label: "*", insert: "*", back: 0),
                Key(label: "/", insert: "/", back: 0),
                Key(label: "\\", insert: "\\", back: 0),
                Key(label: "<", insert: "<", back: 0),
                Key(label: ">", insert: ">", back: 0),
                Key(label: "!", insert: "!", back: 0),
                Key(label: "&", insert: "&", back: 0),
                Key(label: "|", insert: "|", back: 0),
                Key(label: "%", insert: "%", back: 0),
                Key(label: ";", insert: ";", back: 0)
            ]

            for key in keys {
                let button = UIButton(type: .system)
                button.setTitle(key.label, for: .normal)
                button.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .semibold)
                button.setTitleColor(.label, for: .normal)
                button.backgroundColor = UIColor.secondarySystemFill
                button.layer.cornerRadius = 6
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
                button.addAction(UIAction { [weak self] _ in
                    guard let tv = self?.textView else { return }
                    tv.insertText(key.insert)
                    if key.back > 0,
                       let end = tv.selectedTextRange?.end,
                       let pos = tv.position(from: end, offset: -key.back) {
                        tv.selectedTextRange = tv.textRange(from: pos, to: pos)
                    }
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }

            let hide = UIButton(type: .system)
            hide.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
            hide.backgroundColor = UIColor.secondarySystemFill
            hide.layer.cornerRadius = 6
            hide.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            hide.addAction(UIAction { [weak self] _ in
                self?.textView?.resignFirstResponder()
            }, for: .touchUpInside)
            stack.addArrangedSubview(hide)
            return bar
        }
    }
}
