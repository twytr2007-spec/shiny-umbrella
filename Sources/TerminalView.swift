import SwiftUI
import UIKit

struct TerminalView: View {
    @ObservedObject var term: Terminal
    let theme: Theme
    let fontSize: Double
    let language: Language
    @Binding var mode: Int   // 0 = collapsed, 1 = normal, 2 = large

    @State private var input = ""
    @State private var history: [String] = []
    @State private var historyIndex = 0
    @FocusState private var focused: Bool

    private func color(for seg: Terminal.Seg) -> Color {
        if let fg = seg.fg { return Color(hex: fg) }
        switch seg.kind {
        case .out: return theme.textColor
        case .err: return theme.errorColor
        case .input: return theme.accentColor
        case .info: return theme.commentColor
        case .result: return theme.builtinColor
        }
    }

    private var mono: Font { .system(size: CGFloat(fontSize), design: .monospaced) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if mode != 0 {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            output
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(10)
                    }
                    .onChange(of: term.version) { _ in
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
                Rectangle().fill(theme.borderColor).frame(height: 1)
                inputBar
            }
        }
        .background(theme.bgColor)
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(spacing: 0) {
                Text("TERMINAL")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.textColor)
                    .padding(.top, 11)
                    .padding(.bottom, 8)
                Rectangle().fill(theme.accentColor).frame(height: 1.5)
            }
            .fixedSize()
            Text(language.title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.commentColor)
            if term.isRunning {
                ProgressView().scaleEffect(0.6)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = term.plainText()
            } label: { Image(systemName: "doc.on.doc") }
            Button { term.clear() } label: { Image(systemName: "trash") }
            Button { mode = (mode == 2) ? 1 : 2 } label: {
                Image(systemName: mode == 2 ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            Button { mode = (mode == 0) ? 1 : 0 } label: {
                Image(systemName: mode == 0 ? "chevron.up" : "chevron.down")
            }
        }
        .font(.system(size: 14))
        .foregroundColor(theme.commentColor)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(theme.panelColor)
    }

    private var output: some View {
        let combined = term.segs.reduce(Text("")) { (acc: Text, seg: Terminal.Seg) -> Text in
            var piece = Text(seg.text).foregroundColor(color(for: seg))
            if seg.bold { piece = piece.bold() }
            return acc + piece
        }
        return Group {
            if term.segs.isEmpty {
                Text("Press Run to execute your code, or type a command below.")
                    .foregroundColor(theme.commentColor)
            } else {
                combined
            }
        }
        .font(mono)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var promptLabel: String {
        if term.waitingForInput { return "›" }
        if term.isRunning { return "…" }
        return language.prompt
    }

    private var placeholder: String {
        if term.waitingForInput { return "Type input and press return" }
        if term.isRunning { return "Running…" }
        return "\(language.title) command, or: pip install / npm install"
    }

    private var inputDisabled: Bool { term.isRunning && !term.waitingForInput }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text(promptLabel)
                .font(.system(size: CGFloat(fontSize), weight: .bold, design: .monospaced))
                .foregroundColor(theme.accentColor)
            TextField(placeholder, text: $input)
                .font(mono)
                .foregroundColor(theme.textColor)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.send)
                .focused($focused)
                .disabled(inputDisabled)
                .onSubmit { send() }
            Button { stepHistory(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(history.isEmpty || inputDisabled)
            Button { stepHistory(1) } label: { Image(systemName: "chevron.down") }
                .disabled(history.isEmpty || inputDisabled)
            Button { send() } label: {
                Image(systemName: "return").foregroundColor(theme.accentColor)
            }
            .disabled(inputDisabled)
        }
        .font(.system(size: 14))
        .foregroundColor(theme.commentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(theme.panelColor)
        .onChange(of: term.waitingForInput) { waiting in
            if waiting { focused = true }
        }
    }

    private func stepHistory(_ delta: Int) {
        guard !history.isEmpty else { return }
        historyIndex = max(0, min(history.count, historyIndex + delta))
        input = historyIndex < history.count ? history[historyIndex] : ""
    }

    private func send() {
        let text = input
        input = ""
        if !term.waitingForInput, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            history.append(text)
        }
        historyIndex = history.count
        term.submit(text, language: language)
        focused = true
    }
}
