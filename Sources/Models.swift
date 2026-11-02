import Foundation

enum Language: String, CaseIterable, Identifiable {
    case python, javascript

    var id: String { rawValue }
    var title: String { self == .python ? "Python" : "JavaScript" }
    var ext: String { self == .python ? "py" : "js" }
    var icon: String { self == .python ? "chevron.left.forwardslash.chevron.right" : "curlybraces" }
    var prompt: String { self == .python ? ">>>" : ">" }
    var runner: String { self == .python ? "python" : "node" }

    static func from(fileName: String) -> Language {
        fileName.lowercased().hasSuffix(".js") ? .javascript : .python
    }
}

struct CodeFile: Identifiable, Equatable {
    var name: String
    var content: String
    var id: String { name }
    var language: Language { Language.from(fileName: name) }
}

enum Templates {
    static func list(for language: Language) -> [(title: String, code: String)] {
        switch language {
        case .python:
            return [
                ("Hello World", "print(\"Hello, World!\")\n"),
                ("Loops", """
for i in range(1, 6):
    print(f"Number {i}: square = {i * i}")

total = sum(range(1, 101))
print("Sum 1..100 =", total)
"""),
                ("Functions & classes", """
def fib(n):
    a, b = 0, 1
    for _ in range(n):
        yield a
        a, b = b, a + b

print(list(fib(12)))


class Dog:
    def __init__(self, name):
        self.name = name

    def speak(self):
        return f"{self.name} says Woof!"


print(Dog("Rex").speak())
"""),
                ("User input", """
name = input("What is your name? ")
age = int(input("How old are you? "))
print(f"Hello {name}! Next year you will be {age + 1}.")
""")
            ]
        case .javascript:
            return [
                ("Hello World", "console.log(\"Hello, World!\");\n"),
                ("Loops", """
for (let i = 1; i <= 5; i++) {
  console.log(`Number ${i}: square = ${i * i}`);
}

const total = Array.from({ length: 100 }, (_, i) => i + 1).reduce((a, b) => a + b, 0);
console.log("Sum 1..100 =", total);
"""),
                ("Functions & async", """
function fib(n) {
  const out = [];
  let a = 0, b = 1;
  for (let i = 0; i < n; i++) {
    out.push(a);
    [a, b] = [b, a + b];
  }
  return out;
}

console.log(fib(12));

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  console.log("Waiting...");
  await wait(500);
  console.log("Done!");
}

main();
"""),
                ("User input", """
const name = prompt("What is your name?");
const age = parseInt(prompt("How old are you?"));
console.log(`Hello ${name}! Next year you will be ${age + 1}.`);
""")
            ]
        }
    }
}

final class ProjectStore: ObservableObject {
    static let directory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @Published var files: [CodeFile] = []
    @Published var currentName: String = ""
    private var pendingSaves: [String: DispatchWorkItem] = [:]

    init() {
        reload()
        if files.isEmpty {
            create(baseName: "main", language: .javascript, content: Templates.list(for: .javascript)[0].code)
            create(baseName: "main", language: .python, content: Templates.list(for: .python)[0].code)
        }
        if !files.contains(where: { $0.name == currentName }) {
            currentName = files.first(where: { $0.name == "main.py" })?.name ?? files[0].name
        }
    }

    var current: CodeFile? { files.first(where: { $0.name == currentName }) }

    func url(for name: String) -> URL {
        Self.directory.appendingPathComponent(name)
    }

    func reload() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path)) ?? []
        files = names
            .filter { $0.hasSuffix(".py") || $0.hasSuffix(".js") }
            .sorted()
            .compactMap { n in
                guard let text = try? String(contentsOf: url(for: n), encoding: .utf8) else { return nil }
                return CodeFile(name: n, content: text)
            }
    }

    @discardableResult
    func create(baseName: String, language: Language, content: String) -> String {
        var base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        base = base.components(separatedBy: bad).joined(separator: "_")
        if base.isEmpty { base = "script" }
        if base.lowercased().hasSuffix("." + language.ext) {
            base = String(base.dropLast(language.ext.count + 1))
        }
        var name = "\(base).\(language.ext)"
        var i = 2
        while files.contains(where: { $0.name == name }) {
            name = "\(base)\(i).\(language.ext)"
            i += 1
        }
        files.append(CodeFile(name: name, content: content))
        files.sort { $0.name < $1.name }
        try? content.write(to: url(for: name), atomically: true, encoding: .utf8)
        currentName = name
        return name
    }

    func updateCurrent(_ text: String) {
        guard let i = files.firstIndex(where: { $0.name == currentName }),
              files[i].content != text else { return }
        files[i].content = text
        scheduleSave(currentName)
    }

    private func scheduleSave(_ name: String) {
        pendingSaves[name]?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow(name) }
        pendingSaves[name] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func saveNow(_ name: String) {
        pendingSaves[name]?.cancel()
        pendingSaves[name] = nil
        guard let f = files.first(where: { $0.name == name }) else { return }
        try? f.content.write(to: url(for: name), atomically: true, encoding: .utf8)
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
        files.removeAll(where: { $0.name == name })
        if files.isEmpty {
            create(baseName: "main", language: .python, content: Templates.list(for: .python)[0].code)
        } else if currentName == name {
            currentName = files[0].name
        }
    }
}
