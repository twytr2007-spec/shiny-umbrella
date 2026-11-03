import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = ProjectStore()
    @ObservedObject private var term = Terminal.shared
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("themeID") private var themeID = "dark"
    @AppStorage("fontSize") private var fontSize = 15.0
    @AppStorage("showLineNumbers") private var showLineNumbers = true
    @AppStorage("autoClose") private var autoClose = true
    @AppStorage("tabWidth") private var tabWidth = 4
    @AppStorage("panelFraction") private var panelFraction = 0.36

    @State private var controller = EditorController()
    @State private var cursorLine = 1
    @State private var cursorCol = 1
    @State private var termMode = 1
    @State private var dragStart: Double?
    @State private var showFiles = false
    @State private var showNew = false
    @State private var showSettings = false
    @State private var keyboardVisible = false

    private var theme: Theme { Theme.byID(themeID) }
    private var language: Language { store.current?.language ?? .python }

    private func panelHeight(_ total: CGFloat) -> CGFloat {
        switch termMode {
        case 0: return 38
        case 2: return total * 0.75
        default: return total * CGFloat(panelFraction)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            tabStrip
            GeometryReader { geo in
                VStack(spacing: 0) {
                    CodeEditor(
                        text: Binding(
                            get: { store.current?.content ?? "" },
                            set: { store.updateCurrent($0) }
                        ),
                        cursorLine: $cursorLine,
                        cursorCol: $cursorCol,
                        language: language,
                        theme: theme,
                        fontSize: CGFloat(fontSize),
                        showLineNumbers: showLineNumbers,
                        autoClose: autoClose,
                        tabWidth: tabWidth,
                        controller: controller
                    )
                    .id(store.currentName)
                    .frame(maxHeight: .infinity)
                    panelDivider(total: geo.size.height)
                    TerminalView(
                        term: term,
                        theme: theme,
                        fontSize: fontSize - 2,
                        language: language,
                        mode: $termMode
                    )
                    .frame(height: panelHeight(geo.size.height))
                }
            }
            statusBar
        }
        .background(theme.bgColor.ignoresSafeArea())
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .tint(theme.accentColor)
        .onChange(of: scenePhase) { _ in store.saveAll() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .sheet(isPresented: $showFiles) {
            FilesSheet(store: store, theme: theme)
        }
        .sheet(isPresented: $showNew) {
            NewFileSheet(store: store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                themeID: $themeID,
                fontSize: $fontSize,
                showLineNumbers: $showLineNumbers,
                autoClose: $autoClose,
                tabWidth: $tabWidth
            )
        }
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(spacing: 14) {
            Button { showFiles = true } label: {
                Image(systemName: "sidebar.left").font(.system(size: 18))
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: language.icon).font(.system(size: 12))
                Text(store.current?.name ?? "")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
            }
            .foregroundColor(theme.textColor)
            Spacer()
            Button { controller.find() } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 17))
            }
            Button { runOrStop() } label: {
                Image(systemName: term.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 30)
                    .background(term.isRunning ? Color(hex: 0xC93C37) : Color(hex: 0x2EA043))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .keyboardShortcut("r", modifiers: .command)
            optionsMenu
        }
        .foregroundColor(theme.commentColor)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(theme.tabBarColor)
    }

    private var optionsMenu: some View {
        Menu {
            Button { showNew = true } label: { Label("New file", systemImage: "doc.badge.plus") }
            Button { controller.find() } label: { Label("Find and replace", systemImage: "magnifyingglass") }
                .keyboardShortcut("f", modifiers: .command)
            Button { controller.toggleComment() } label: { Label("Toggle comment", systemImage: "text.quote") }
                .keyboardShortcut("/", modifiers: .command)
            Button { runSelection() } label: { Label("Run selection", systemImage: "play.square") }
            Button { controller.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
            Button { controller.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            if let name = store.current?.name {
                ShareLink(item: store.url(for: name)) {
                    Label("Share file", systemImage: "square.and.arrow.up")
                }
            }
            Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold))
                .frame(width: 28, height: 30)
        }
    }

    // MARK: Tabs

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(store.openTabs, id: \.self) { name in
                    tab(name)
                }
                Button { showNew = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 38, height: 36)
                }
                .foregroundColor(theme.commentColor)
            }
        }
        .frame(height: 36)
        .background(theme.tabBarColor)
    }

    private func tab(_ name: String) -> some View {
        let active = name == store.currentName
        let lang = Language.from(fileName: name)
        return HStack(spacing: 6) {
            Image(systemName: lang.icon)
                .font(.system(size: 11))
                .foregroundColor(lang == .python ? theme.keywordColor : theme.stringColor)
            Text(name)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(active ? theme.textColor : theme.commentColor)
            if store.openTabs.count > 1 {
                Button { store.closeTab(name) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(theme.commentColor)
                        .frame(width: 18, height: 18)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(active ? theme.bgColor : theme.tabInactiveColor)
        .overlay(alignment: .top) {
            Rectangle().fill(active ? theme.accentColor : Color.clear).frame(height: 2)
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme.borderColor).frame(width: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.open(name) }
    }

    // MARK: Resizable panel

    private func panelDivider(total: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(theme.borderColor).frame(height: 1)
            Capsule().fill(theme.commentColor.opacity(0.6)).frame(width: 36, height: 4)
        }
        .frame(height: 14)
        .background(theme.panelColor)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if dragStart == nil { dragStart = termMode == 1 ? panelFraction : (termMode == 2 ? 0.75 : 0.1) }
                    guard total > 0, let start = dragStart else { return }
                    termMode = 1
                    panelFraction = min(0.8, max(0.12, start - Double(value.translation.height / total)))
                }
                .onEnded { _ in dragStart = nil }
        )
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 14) {
            Text(language.title)
            Text("Ln \(cursorLine), Col \(cursorCol)")
            Text("Spaces: \(tabWidth)")
            Text("UTF-8")
            Spacer()
            if term.isRunning {
                HStack(spacing: 4) {
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                    Text("Running")
                }
            } else {
                Text(store.current?.name ?? "")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(theme.statusColor.ignoresSafeArea(edges: statusEdges))
    }

    private var statusEdges: Edge.Set {
        let none: Edge.Set = []
        return keyboardVisible ? none : .bottom
    }

    // MARK: Actions

    private func runOrStop() {
        if term.isRunning {
            term.stop()
            return
        }
        guard let file = store.current else { return }
        store.saveNow(file.name)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        controller.dismissKeyboard()
        if termMode == 0 { termMode = 1 }
        term.run(code: file.content, language: file.language, fileName: file.name)
    }

    private func runSelection() {
        guard !term.isRunning, let file = store.current, let code = controller.selectedText() else { return }
        controller.dismissKeyboard()
        if termMode == 0 { termMode = 1 }
        term.run(code: code, language: file.language, fileName: file.name + " (selection)")
    }
}

// MARK: - Explorer

struct FilesSheet: View {
    @ObservedObject var store: ProjectStore
    let theme: Theme
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false
    @State private var showImporter = false
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("EXPLORER · PROJECTS") {
                    ForEach(store.files) { file in
                        Button {
                            store.open(file.name)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: file.language.icon)
                                    .foregroundColor(file.language == .python ? theme.keywordColor : theme.stringColor)
                                    .frame(width: 20)
                                Text(file.name).font(.system(.body, design: .monospaced))
                                Spacer()
                                if file.name == store.currentName {
                                    Image(systemName: "circle.fill").font(.system(size: 7)).foregroundColor(.accentColor)
                                }
                            }
                            .foregroundColor(.primary)
                        }
                        .contextMenu {
                            Button { newName = (file.name as NSString).deletingPathExtension; renaming = file.name } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button { store.duplicate(file.name) } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) { store.delete(file.name) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        let names = offsets.map { store.files[$0].name }
                        names.forEach { store.delete($0) }
                    }
                }
                Section {
                    Text("Press and hold a file to rename or duplicate it. Your files also appear in the Files app under Code IDE.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Explorer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew, onDismiss: { dismiss() }) {
                NewFileSheet(store: store)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pythonScript, .javaScript, .plainText],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    urls.forEach { store.importFile($0) }
                    dismiss()
                }
            }
            .alert("Rename file", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let old = renaming { store.rename(old, to: newName) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }
}

// MARK: - New file

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

// MARK: - Settings

struct SettingsSheet: View {
    @Binding var themeID: String
    @Binding var fontSize: Double
    @Binding var showLineNumbers: Bool
    @Binding var autoClose: Bool
    @Binding var tabWidth: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Color theme") {
                    ForEach(Theme.all) { t in
                        Button { themeID = t.id } label: {
                            HStack(spacing: 10) {
                                HStack(spacing: 3) {
                                    ForEach([t.keywordColor, t.stringColor, t.builtinColor, t.functionColor], id: \.self) { c in
                                        Circle().fill(c).frame(width: 10, height: 10)
                                    }
                                }
                                .padding(8)
                                .background(t.bgColor)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(t.name).foregroundColor(.primary)
                                Spacer()
                                if t.id == themeID {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
                Section("Editor") {
                    VStack(alignment: .leading) {
                        Text("Font size: \(Int(fontSize))")
                        Slider(value: $fontSize, in: 10...24, step: 1)
                    }
                    Toggle("Line numbers", isOn: $showLineNumbers)
                    Toggle("Auto-close brackets and quotes", isOn: $autoClose)
                    Picker("Indent size", selection: $tabWidth) {
                        Text("2").tag(2)
                        Text("4").tag(4)
                        Text("8").tag(8)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Packages") {
                    Text("In the terminal: pip install <package> (pure Python) or npm install <package>. Compiled Python packages go in requirements-ios.txt in your repository.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
