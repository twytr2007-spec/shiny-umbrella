import SwiftUI

struct ContentView: View {
    @StateObject private var store = ProjectStore()
    @ObservedObject private var term = Terminal.shared
    @AppStorage("themeID") private var themeID = "dark"
    @AppStorage("fontSize") private var fontSize = 15.0
    @State private var showFiles = false
    @State private var showNew = false
    @State private var termMode = 1

    private var theme: Theme { Theme.byID(themeID) }

    private func terminalHeight(_ total: CGFloat) -> CGFloat {
        switch termMode {
        case 0: return 40
        case 2: return total * 0.72
        default: return total * 0.38
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    tabsBar
                    CodeEditor(
                        text: Binding(
                            get: { store.current?.content ?? "" },
                            set: { store.updateCurrent($0) }
                        ),
                        language: store.current?.language ?? .python,
                        theme: theme,
                        fontSize: CGFloat(fontSize)
                    )
                    .id(store.currentName)
                    Divider()
                    TerminalView(
                        term: term,
                        theme: theme,
                        fontSize: fontSize - 1,
                        language: store.current?.language ?? .python,
                        mode: $termMode
                    )
                    .frame(height: terminalHeight(geo.size.height))
                }
                .background(theme.bgColor)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.panelColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showFiles = true } label: {
                        Image(systemName: "folder")
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: store.current?.language.icon ?? "doc")
                        Text(store.current?.name ?? "")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    optionsMenu
                    Button { runOrStop() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: term.isRunning ? "stop.fill" : "play.fill")
                            Text(term.isRunning ? "Stop" : "Run")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(term.isRunning ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            }
            .sheet(isPresented: $showFiles) {
                FilesSheet(store: store)
            }
            .sheet(isPresented: $showNew) {
                NewFileSheet(store: store)
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private var tabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.files) { file in
                    Button {
                        store.saveNow(store.currentName)
                        store.currentName = file.name
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: file.language.icon).font(.system(size: 11))
                            Text(file.name).font(.system(size: 13, design: .monospaced))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(file.name == store.currentName ? theme.accentColor.opacity(0.25) : theme.panelColor)
                        .foregroundColor(file.name == store.currentName ? theme.accentColor : theme.commentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                Button { showNew = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .padding(8)
                        .background(theme.panelColor)
                        .foregroundColor(theme.commentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(theme.bgColor)
    }

    private var optionsMenu: some View {
        Menu {
            Button { showNew = true } label: {
                Label("New file", systemImage: "doc.badge.plus")
            }
            Picker("Theme", selection: $themeID) {
                ForEach(Theme.all) { t in
                    Text(t.name).tag(t.id)
                }
            }
            Button { fontSize = min(26, fontSize + 1) } label: {
                Label("Bigger text", systemImage: "textformat.size.larger")
            }
            Button { fontSize = max(10, fontSize - 1) } label: {
                Label("Smaller text", systemImage: "textformat.size.smaller")
            }
            if let name = store.current?.name {
                ShareLink(item: store.url(for: name)) {
                    Label("Share file", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func runOrStop() {
        if term.isRunning {
            term.stop()
            return
        }
        guard let file = store.current else { return }
        store.saveNow(file.name)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if termMode == 0 { termMode = 1 }
        term.run(code: file.content, language: file.language, fileName: file.name)
    }
}

struct FilesSheet: View {
    @ObservedObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.files) { file in
                    Button {
                        store.saveNow(store.currentName)
                        store.currentName = file.name
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: file.language.icon)
                            Text(file.name).font(.system(.body, design: .monospaced))
                            Spacer()
                            if file.name == store.currentName {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
                .onDelete { offsets in
                    let names = offsets.map { store.files[$0].name }
                    names.forEach { store.delete($0) }
                }
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew, onDismiss: { dismiss() }) {
                NewFileSheet(store: store)
            }
        }
    }
}

struct NewFileSheet: View {
    @ObservedObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var language: Language = .python
    @State private var name = ""
    @State private var templateIndex = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Language") {
                    Picker("Language", selection: $language) {
                        ForEach(Language.allCases) { l in
                            Text(l.title).tag(l)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: language) { _ in templateIndex = 0 }
                }
                Section("File name") {
                    HStack {
                        TextField("script", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        Text(".\(language.ext)").foregroundColor(.secondary)
                    }
                }
                Section("Template") {
                    Picker("Template", selection: $templateIndex) {
                        ForEach(Array(Templates.list(for: language).enumerated()), id: \.offset) { index, item in
                            Text(item.title).tag(index)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("New file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        let templates = Templates.list(for: language)
                        let code = templates[min(templateIndex, templates.count - 1)].code
                        store.create(baseName: name, language: language, content: code)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
