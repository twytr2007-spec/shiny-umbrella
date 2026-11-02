import SwiftUI

struct TerminalView: View {
    @ObservedObject var term: Terminal
    let theme: Theme
    let fontSize: Double
    let language: Language
    @Binding var mode: Int   // 0 = collapsed, 1 = normal, 2 = large

    @State private var input = ""
    @FocusState private var focused: Bool

    private func color(for kind: Terminal.Kind) -> Color {
        switch kind {
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
                Divider()
                inputBar
            }
        }
        .background(theme.panelColor)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(term.isRunning ? Color.green : theme.commentColor.opacity(0.6))
                .frame(width: 9, height: 9)
            Text("TERMINAL · \(language.title)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.commentColor)
            Spacer()
            Button { term.clear() } label: {
                Image(systemName: "trash")
            }
            Button { mode = (mode == 2) ? 1 : 2 } label: {
                Image(systemName: mode == 2 ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            Button { mode = (mode == 0) ? 1 : 0 } label: {
                Image(systemName: mode == 0 ? "chevron.up" : "chevron.down")
            }
        }
        .font(.system(size: 15))
        .foregroundColor(theme.commentColor)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(theme.panelColor)
    }

    private var output: some View {
        let combined = term.segs.reduce(Text("")) { (acc: Text, seg: Terminal.Seg) -> Text in
            acc + Text(seg.text).foregroundColor(color(for: seg.kind))
        }
        return Group {
            if term.segs.isEmpty {
                Text("Press ▶ to run your code, or type a command below.")
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
        return "Type a \(language.title) command"
    }

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
                .disabled(term.isRunning && !term.waitingForInput)
                .onSubmit { send() }
            Button { send() } label: {
                Image(systemName: "return")
                    .foregroundColor(theme.accentColor)
            }
            .disabled(term.isRunning && !term.waitingForInput)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onChange(of: term.waitingForInput) { waiting in
            if waiting { focused = true }
        }
    }

    private func send() {
        let text = input
        input = ""
        term.submit(text, language: language)
        focused = true
    }
}
