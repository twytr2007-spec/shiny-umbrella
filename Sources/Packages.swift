import Foundation

/// Handles `pip install` and `npm install` typed into the terminal.
enum PackageManager {
    private static func folder(_ name: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var sitePackages: URL { folder("site-packages") }
    static var nodeModules: URL { folder("node_modules") }

    static func isCommand(_ line: String) -> Bool {
        guard let first = line.split(separator: " ").first else { return false }
        return first == "pip" || first == "pip3" || first == "npm"
    }

    static func handle(_ line: String, term: Terminal) {
        let parts = line.split(separator: " ").map(String.init)
        guard let tool = parts.first else { return }
        let sub = parts.count > 1 ? parts[1] : ""
        let args = parts.dropFirst(2).filter { !$0.hasPrefix("-") }
        let isNpm = tool == "npm"
        switch sub {
        case "install", "i", "add":
            if args.isEmpty {
                term.emit(.err, "Usage: \(tool) install <package> [<package> ...]\n")
                return
            }
            if isNpm { npmInstall(Array(args), term: term) } else { pipInstall(Array(args), term: term) }
        case "list", "ls":
            list(isNpm: isNpm, term: term)
        default:
            term.emit(.info, "Supported commands: \(tool) install <package>, \(tool) list\n")
        }
    }

    private static func list(isNpm: Bool, term: Terminal) {
        let fm = FileManager.default
        var names: [String]
        if isNpm {
            let items = (try? fm.contentsOfDirectory(atPath: nodeModules.path)) ?? []
            names = items.filter { !$0.hasPrefix(".") }.sorted()
        } else {
            let items = (try? fm.contentsOfDirectory(atPath: sitePackages.path)) ?? []
            names = items.filter { $0.hasSuffix(".dist-info") }.map { String($0.dropLast(10)) }.sorted()
        }
        term.emit(.out, names.isEmpty ? "(no packages installed)\n" : names.joined(separator: "\n") + "\n")
    }

    private static func fetch(_ url: URL) -> Data? {
        var result: Data?
        let sem = DispatchSemaphore(value: 0)
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { result = data }
            sem.signal()
        }.resume()
        sem.wait()
        return result
    }

    // MARK: pip (pure-Python wheels, installed at runtime)

    private static func pipInstall(_ names: [String], term: Terminal) {
        if let err = PythonEngine.shared.prepare() {
            term.emit(.err, err + "\n")
            return
        }
        var queue = names
        var seen = Set<String>()
        var installed: [String] = []
        while !queue.isEmpty {
            let raw = queue.removeFirst()
            let key = raw.lowercased().replacingOccurrences(of: "_", with: "-")
            if seen.contains(key) { continue }
            seen.insert(key)
            term.emit(.info, "Collecting \(raw)\n")
            guard let url = URL(string: "https://pypi.org/pypi/\(raw)/json"),
                  let data = fetch(url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let info = json["info"] as? [String: Any],
                  let files = json["urls"] as? [[String: Any]] else {
                term.emit(.err, "ERROR: could not find '\(raw)' on PyPI (check the name and your internet connection)\n")
                continue
            }
            let version = info["version"] as? String ?? "?"
            guard let wheel = files.first(where: { ($0["filename"] as? String)?.hasSuffix("none-any.whl") == true }),
                  let fileName = wheel["filename"] as? String,
                  let wheelURLString = wheel["url"] as? String,
                  let wheelURL = URL(string: wheelURLString) else {
                term.emit(.err, "ERROR: \(raw) has no pure-Python wheel because it contains compiled code. Add it to requirements-ios.txt in your repo to bundle it at build time.\n")
                continue
            }
            term.emit(.info, "  Downloading \(fileName)\n")
            guard let wheelData = fetch(wheelURL) else {
                term.emit(.err, "ERROR: download failed for \(raw)\n")
                continue
            }
            let tmp = NSTemporaryDirectory() + fileName
            do {
                try wheelData.write(to: URL(fileURLWithPath: tmp))
            } catch {
                term.emit(.err, "ERROR: could not save \(fileName)\n")
                continue
            }
            let code = "import zipfile\nzipfile.ZipFile(r\"\(tmp)\").extractall(r\"\(sitePackages.path)\")\n"
            PythonEngine.shared.run(code: code, fileName: "pip")
            try? FileManager.default.removeItem(atPath: tmp)
            installed.append("\(raw)-\(version)")

            if let deps = info["requires_dist"] as? [String] {
                let skipMarkers = ["extra", "win32", "Windows", "cygwin", "python_version <", "python_version<"]
                for dep in deps {
                    let pieces = dep.components(separatedBy: ";")
                    let marker = pieces.count > 1 ? pieces[1] : ""
                    if skipMarkers.contains(where: { marker.contains($0) }) { continue }
                    let head = pieces[0].trimmingCharacters(in: .whitespaces)
                    let depName = String(head.prefix(while: { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }))
                    if !depName.isEmpty { queue.append(depName) }
                }
            }
        }
        if installed.isEmpty {
            term.emit(.err, "Nothing was installed.\n")
        } else {
            term.emit(.out, "Successfully installed " + installed.joined(separator: " ") + "\n")
        }
    }

    // MARK: npm (installed at runtime, loaded with require())

    private static func npmInstall(_ specs: [String], term: Terminal) {
        if let err = PythonEngine.shared.prepare() {
            term.emit(.err, err + "\n")
            return
        }
        var queue = specs
        var seen = Set<String>()
        var installed: [String] = []
        while !queue.isEmpty {
            let spec = queue.removeFirst()
            var name = spec
            var version = "latest"
            let start = spec.hasPrefix("@") ? spec.index(after: spec.startIndex) : spec.startIndex
            if let at = spec[start...].firstIndex(of: "@") {
                name = String(spec[..<at])
                version = String(spec[spec.index(after: at)...])
            }
            if seen.contains(name) { continue }
            seen.insert(name)
            term.emit(.info, "Fetching \(name)\n")
            let encoded = name.replacingOccurrences(of: "/", with: "%2F")
            guard let url = URL(string: "https://registry.npmjs.org/\(encoded)/\(version)"),
                  let data = fetch(url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dist = json["dist"] as? [String: Any],
                  let tarball = dist["tarball"] as? String,
                  let tarURL = URL(string: tarball),
                  let archive = fetch(tarURL) else {
                term.emit(.err, "ERROR: could not download '\(spec)' from the npm registry\n")
                continue
            }
            let resolved = json["version"] as? String ?? version
            let tmp = NSTemporaryDirectory() + "npm-\(UUID().uuidString).tgz"
            do {
                try archive.write(to: URL(fileURLWithPath: tmp))
            } catch {
                term.emit(.err, "ERROR: could not save the package archive\n")
                continue
            }
            let dest = nodeModules.appendingPathComponent(name).path
            let code = """
import tarfile, os, shutil
dest = r"\(dest)"
shutil.rmtree(dest, ignore_errors=True)
os.makedirs(dest, exist_ok=True)
with tarfile.open(r"\(tmp)") as t:
    for m in t.getmembers():
        parts = m.name.split("/", 1)
        if len(parts) < 2 or not parts[1] or ".." in parts[1].split("/"):
            continue
        m.name = parts[1]
        if m.isfile() or m.isdir():
            t.extract(m, dest, filter="data")

"""
            PythonEngine.shared.run(code: code, fileName: "npm")
            try? FileManager.default.removeItem(atPath: tmp)
            installed.append("\(name)@\(resolved)")
            if let deps = json["dependencies"] as? [String: String] {
                queue.append(contentsOf: deps.keys.sorted())
            }
        }
        if installed.isEmpty {
            term.emit(.err, "Nothing was installed.\n")
        } else {
            term.emit(.out, "Installed " + installed.joined(separator: " ") + "\nUse it with: const x = require(\"name\");\n")
        }
    }
}
