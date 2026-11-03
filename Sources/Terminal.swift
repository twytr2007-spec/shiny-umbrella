import Foundation
import JavaScriptCore
import SwiftUI

final class Terminal: ObservableObject {
    static let shared = Terminal()

    enum Kind { case out, err, input, info, result }

    struct Seg {
        var kind: Kind
        var text: String
    }

    @Published private(set) var segs: [Seg] = []
    @Published private(set) var version = 0
    @Published private(set) var isRunning = false
    @Published private(set) var waitingForInput = false

    private let lock = NSLock()
    private var pending: [Seg] = []
    private var flushScheduled = false
    private var totalChars = 0
    private var activeToken = 0
    private var inputValue: String?
    private let inputSemaphore = DispatchSemaphore(value: 0)
    private var stopRequested = false
    private var currentLanguage: Language = .python
    private var startTime = Date()

    // MARK: Output (thread-safe)

    func emit(_ kind: Kind, _ text: String) {
        guard !text.isEmpty else { return }
        lock.lock()
        pending.append(Seg(kind: kind, text: text))
        let schedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        if schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.flush()
            }
        }
    }

    private func flush() {
        lock.lock()
        let items = pending
        pending = []
        flushScheduled = false
        lock.unlock()
        for s in items {
            if let last = segs.last, last.kind == s.kind {
                segs[segs.count - 1].text += s.text
            } else {
                segs.append(s)
            }
            totalChars += s.text.count
        }
        while totalChars > 120_000 && segs.count > 1 {
            totalChars -= segs[0].text.count
            segs.removeFirst()
        }
        if segs.count == 1 && totalChars > 120_000 {
            segs[0].text = String(segs[0].text.suffix(100_000))
            totalChars = segs[0].text.count
        }
        version += 1
    }

    func clear() {
        lock.lock()
        pending = []
        lock.unlock()
        segs = []
        totalChars = 0
        version += 1
    }

    func isActive(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeToken == token
    }

    // MARK: Running

    private func beginRun(language: Language) -> Int {
        isRunning = true
        stopRequested = false
        currentLanguage = language
        startTime = Date()
        lock.lock()
        activeToken += 1
        let token = activeToken
        lock.unlock()
        return token
    }

    private func finish(token: Int, silent: Bool) {
        guard isActive(token) else { return }
        isRunning = false
        waitingForInput = false
        if stopRequested {
            emit(.info, "\n■ Stopped\n")
        } else if !silent {
            emit(.info, String(format: "\n✓ Finished in %.2fs\n", Date().timeIntervalSince(startTime)))
        }
        stopRequested = false
    }

    func run(code: String, language: Language, fileName: String) {
        guard !isRunning else { return }
        let token = beginRun(language: language)
        emit(.info, "\n$ \(language.runner) \(fileName)\n")
        launch(token: token, silent: false) {
            switch language {
            case .python:
                if let error = PythonEngine.shared.prepare() {
                    self.emit(.err, error + "\n")
                } else {
                    PythonEngine.shared.run(code: code, fileName: fileName)
                }
            case .javascript:
                JSEngine.run(code: code, term: self, token: token)
            }
        }
    }

    private func runREPL(_ line: String, language: Language) {
        let token = beginRun(language: language)
        emit(.input, "\(language.prompt) \(line)\n")
        launch(token: token, silent: true) {
            switch language {
            case .python:
                if let error = PythonEngine.shared.prepare() {
                    self.emit(.err, error + "\n")
                } else {
                    PythonEngine.shared.repl(line)
                }
            case .javascript:
                JSEngine.repl(line, term: self, token: token)
            }
        }
    }

    private func runShell(_ line: String) {
        let token = beginRun(language: .javascript)
        emit(.input, "$ \(line)\n")
        launch(token: token, silent: false) {
            PackageManager.handle(line, term: self)
        }
    }

    private func launch(token: Int, silent: Bool, work: @escaping () -> Void) {
        let thread = Thread { [weak self] in
            work()
            DispatchQueue.main.async { self?.finish(token: token, silent: silent) }
        }
        thread.stackSize = 32 * 1024 * 1024
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func stop() {
        guard isRunning else { return }
        stopRequested = true
        if waitingForInput {
            waitingForInput = false
            lock.lock()
            inputValue = nil
            lock.unlock()
            inputSemaphore.signal()
        }
        if currentLanguage == .python {
            PythonEngine.shared.interrupt()
        } else {
            lock.lock()
            activeToken += 1
            lock.unlock()
            isRunning = false
            stopRequested = false
            emit(.info, "\n■ Stopped\n")
        }
    }

    // MARK: Input

    /// Called from the worker thread. Blocks until the user submits a line (or stop is pressed).
    func readInput(prompt: String) -> String? {
        if !prompt.isEmpty { emit(.out, prompt) }
        DispatchQueue.main.async { self.waitingForInput = true }
        inputSemaphore.wait()
        lock.lock()
        let value = inputValue
        inputValue = nil
        lock.unlock()
        return value
    }

    func submit(_ text: String, language: Language) {
        if waitingForInput {
            waitingForInput = false
            emit(.input, text + "\n")
            lock.lock()
            inputValue = text
            lock.unlock()
            inputSemaphore.signal()
        } else if !isRunning {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return }
            if trimmed == "clear" || trimmed == "cls" {
                clear()
                return
            }
            if PackageManager.isCommand(trimmed) {
                runShell(trimmed)
                return
            }
            runREPL(text, language: language)
        }
    }
}

// MARK: - Python

private let pyOutCallback: ide_out_cb = { stream, text in
    guard let text = text else { return }
    Terminal.shared.emit(stream == 2 ? .err : .out, String(cString: text))
}

private let pyInCallback: ide_in_cb = { prompt in
    let p = prompt.map { String(cString: $0) } ?? ""
    guard let line = Terminal.shared.readInput(prompt: p) else { return nil }
    return strdup(line)
}

final class PythonEngine {
    static let shared = PythonEngine()
    private let lock = NSLock()
    private var initialized = false
    private var failure: String?

    /// Starts the interpreter once. Returns an error message on failure.
    func prepare() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if initialized { return nil }
        if let f = failure { return f }

        let bundle = Bundle.main.bundlePath
        let libRoot = bundle + "/python/lib"
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: libRoot)) ?? []
        guard let version = entries.first(where: { $0.hasPrefix("python3") }) else {
            failure = "Python runtime was not found inside the app (python/lib is missing)."
            return failure
        }
        let libdir = libRoot + "/" + version
        let exe = Bundle.main.executablePath ?? (bundle + "/CodeIDE")
        var errBuf = [CChar](repeating: 0, count: 1024)
        let cap = Int32(errBuf.count)
        let rc = ide_py_init(bundle + "/python", exe, libdir, PythonEngine.bootstrap(),
                             pyOutCallback, pyInCallback, &errBuf, cap)
        if rc != 0 {
            failure = "Python failed to start (code \(rc)): " + String(cString: errBuf)
            return failure
        }
        initialized = true
        return nil
    }

    func run(code: String, fileName: String) { ide_py_run(code, fileName) }
    func repl(_ line: String) { ide_py_repl(line) }
    func interrupt() { ide_py_interrupt() }

    static func bootstrap() -> String {
        let projects = ProjectStore.directory.path
        let site = PackageManager.sitePackages.path
        return #"""
import sys, os, builtins, traceback, linecache, importlib
import _ide_bridge

PROJECTS = r"\#(projects)"
try:
    os.makedirs(PROJECTS, exist_ok=True)
    os.chdir(PROJECTS)
except Exception:
    pass
if PROJECTS not in sys.path:
    sys.path.insert(0, PROJECTS)
SITE = r"\#(site)"
for _p in (SITE, os.path.join(os.path.dirname(os.__file__), "site-packages")):
    if _p not in sys.path:
        sys.path.append(_p)


class _Out:
    encoding = "utf-8"
    errors = "replace"

    def __init__(self, stream):
        self.stream = stream

    def write(self, text):
        text = str(text).replace("\x00", "")
        _ide_bridge.write(self.stream, text.encode("utf-8", "replace").decode("utf-8"))
        return len(text)

    def flush(self):
        pass

    def isatty(self):
        return False

    def writable(self):
        return True

    def fileno(self):
        raise OSError("no fileno")


class _In:
    encoding = "utf-8"

    def readline(self, size=-1):
        try:
            return _ide_bridge.read("") + "\n"
        except EOFError:
            return ""

    def read(self, size=-1):
        data = ""
        while True:
            line = self.readline()
            if not line:
                break
            data += line
        return data

    def isatty(self):
        return False

    def __iter__(self):
        return self

    def __next__(self):
        line = self.readline()
        if not line:
            raise StopIteration
        return line


sys.stdout = _Out(1)
sys.stderr = _Out(2)
sys.stdin = _In()


def _input(prompt=""):
    return _ide_bridge.read(str(prompt))


builtins.input = _input


def _report():
    etype, value, tb = sys.exc_info()
    if tb is not None and tb.tb_next is not None:
        tb = tb.tb_next
    traceback.print_exception(etype, value, tb)


def _ide_run(code, name):
    importlib.invalidate_caches()
    linecache.cache[name] = (len(code), None, code.splitlines(True), name)
    scope = {"__name__": "__main__", "__file__": name, "__builtins__": builtins}
    try:
        exec(compile(code, name, "exec"), scope)
    except SystemExit:
        pass
    except BaseException:
        _report()


_repl_scope = {"__name__": "__main__", "__builtins__": builtins}


def _ide_repl(line):
    importlib.invalidate_caches()
    try:
        exec(compile(line, "<stdin>", "single"), _repl_scope)
    except SystemExit:
        pass
    except BaseException:
        _report()
"""#
    }
}

// MARK: - JavaScript

enum JSEngine {
    private static var replContext: JSContext?

    private static let prelude = #"""
function __fmt(v) {
  if (typeof v === 'string') return v;
  if (v === undefined) return 'undefined';
  if (v === null) return 'null';
  if (typeof v === 'function') return '[Function: ' + (v.name || 'anonymous') + ']';
  if (typeof v === 'symbol') return v.toString();
  if (v instanceof Error) return v.stack ? (v.name + ': ' + v.message + '\n' + v.stack) : String(v);
  if (typeof v === 'object') {
    try {
      var rep = function (k, x) { return typeof x === 'function' ? '[Function]' : x; };
      var compact = JSON.stringify(v, rep);
      if (compact !== undefined && compact.length <= 72) return compact;
      return JSON.stringify(v, rep, 2);
    } catch (e) { return String(v); }
  }
  return String(v);
}
function __mk(kind) {
  return function () {
    var parts = [];
    for (var i = 0; i < arguments.length; i++) parts.push(__fmt(arguments[i]));
    __write(kind, parts.join(' ') + '\n');
  };
}
var console = { log: __mk('out'), info: __mk('out'), debug: __mk('out'), error: __mk('err'), warn: __mk('err'), trace: __mk('err') };
console.table = function (x) { console.log(x); };
function alert(m) { __write('out', String(m) + '\n'); }
function prompt(m) { return __prompt(m === undefined ? '' : String(m)); }
var process = { argv: [], env: {}, platform: 'ios', stdout: { write: function (s) { __write('out', String(s)); } } };
var __timers = [], __tid = 0;
function __add(fn, ms, every, args) {
  var id = ++__tid;
  __timers.push({ id: id, fn: fn, at: Date.now() + Math.max(0, ms || 0), every: every, args: args });
  return id;
}
function setTimeout(fn, ms) { return __add(fn, ms, undefined, Array.prototype.slice.call(arguments, 2)); }
function setInterval(fn, ms) { return __add(fn, ms, Math.max(1, ms || 0), Array.prototype.slice.call(arguments, 2)); }
function setImmediate(fn) { return __add(fn, 0, undefined, Array.prototype.slice.call(arguments, 1)); }
function clearTimeout(id) { __timers = __timers.filter(function (t) { return t.id !== id; }); }
var clearInterval = clearTimeout;
function __minIndex() {
  var m = 0;
  for (var i = 1; i < __timers.length; i++) { if (__timers[i].at < __timers[m].at) m = i; }
  return m;
}
function __next() {
  if (__timers.length === 0) return -1;
  return Math.max(0, __timers[__minIndex()].at - Date.now());
}
function __fire() {
  if (__timers.length === 0) return;
  var t = __timers.splice(__minIndex(), 1)[0];
  if (t.every !== undefined) { t.at = Date.now() + t.every; __timers.push(t); }
  try { t.fn.apply(null, t.args); } catch (e) { __write('err', 'Uncaught ' + String(e) + '\n'); }
}
var global = this;
var module = { exports: {} };
var exports = module.exports;
process.nextTick = function (fn) { var a = Array.prototype.slice.call(arguments, 1); setTimeout(function () { fn.apply(null, a); }, 0); };
var __NM = "__NM_PATH__";
var __modCache = {};
var __builtinCache = {};
var __builtins = {
  events: function () {
    function EventEmitter() { this._ev = {}; }
    EventEmitter.prototype.on = function (n, f) { (this._ev[n] = this._ev[n] || []).push(f); return this; };
    EventEmitter.prototype.addListener = EventEmitter.prototype.on;
    EventEmitter.prototype.off = function (n, f) { this._ev[n] = (this._ev[n] || []).filter(function (x) { return x !== f; }); return this; };
    EventEmitter.prototype.removeListener = EventEmitter.prototype.off;
    EventEmitter.prototype.once = function (n, f) { var self = this; function w() { self.off(n, w); f.apply(self, arguments); } return this.on(n, w); };
    EventEmitter.prototype.emit = function (n) { var a = Array.prototype.slice.call(arguments, 1); var l = (this._ev[n] || []).slice(); for (var i = 0; i < l.length; i++) l[i].apply(this, a); return l.length > 0; };
    EventEmitter.EventEmitter = EventEmitter;
    return EventEmitter;
  },
  util: function () {
    return {
      inspect: __fmt,
      format: function () { return Array.prototype.map.call(arguments, __fmt).join(' '); },
      inherits: function (c, s) { c.prototype = Object.create(s.prototype); c.prototype.constructor = c; }
    };
  }
};
function __dirnameOf(p) { var i = p.lastIndexOf('/'); return i <= 0 ? '/' : p.slice(0, i); }
function __norm(p) {
  var out = [], parts = p.split('/');
  for (var i = 0; i < parts.length; i++) {
    var s = parts[i];
    if (s === '' || s === '.') continue;
    if (s === '..') out.pop(); else out.push(s);
  }
  return '/' + out.join('/');
}
function __tryFile(p) {
  var c = [p, p + '.js', p + '.json', p + '/index.js'];
  for (var i = 0; i < c.length; i++) { if (__isFile(c[i])) return c[i]; }
  return null;
}
function __resolve(req, from) {
  var first = req.charAt(0);
  var base = (first === '.' || first === '/') ? __norm(first === '/' ? req : from + '/' + req) : __norm(__NM + '/' + req);
  var r = __tryFile(base);
  if (r) return r;
  var pj = __readFile(base + '/package.json');
  if (pj !== null) {
    try {
      var m = JSON.parse(pj).main;
      if (m) { r = __tryFile(__norm(base + '/' + m)); if (r) return r; }
    } catch (e) {}
  }
  return null;
}
function __makeRequire(from) {
  return function (name) {
    if (name.indexOf('node:') === 0) name = name.slice(5);
    if (Object.prototype.hasOwnProperty.call(__builtins, name)) {
      return __builtinCache[name] || (__builtinCache[name] = __builtins[name]());
    }
    var file = __resolve(name, from);
    if (!file) throw new Error("Cannot find module '" + name + "'. Install it with: npm install " + name);
    if (__modCache[file]) return __modCache[file].exports;
    var mod = { exports: {}, id: file, filename: file };
    __modCache[file] = mod;
    var src = __readFile(file);
    if (file.slice(-5) === '.json') { mod.exports = JSON.parse(src); return mod.exports; }
    var dir = __dirnameOf(file);
    var fn = new Function('exports', 'require', 'module', '__filename', '__dirname', src);
    fn.call(mod.exports, mod.exports, __makeRequire(dir), mod, file, dir);
    return mod.exports;
  };
}
var require = __makeRequire("__PROJ_PATH__");
"""#

    private static func makeContext(term: Terminal, token: Int?) -> JSContext {
        let ctx = JSContext()!
        let alive: () -> Bool = {
            if let t = token { return term.isActive(t) }
            return true
        }
        ctx.exceptionHandler = { _, exc in
            guard alive() else { return }
            let message = exc?.toString() ?? "Error"
            var line = ""
            if let l = exc?.objectForKeyedSubscript("line"), l.isNumber {
                line = " (line \(Int(l.toInt32())))"
            }
            term.emit(.err, "Uncaught " + message + line + "\n")
        }
        let write: @convention(block) (String, String) -> Void = { kind, text in
            guard alive() else { return }
            term.emit(kind == "err" ? .err : .out, text)
        }
        ctx.setObject(write, forKeyedSubscript: "__write" as NSString)
        let ask: @convention(block) (String) -> Any = { message in
            guard alive() else { return NSNull() }
            let shown = message.isEmpty ? "" : message + " "
            if let answer = term.readInput(prompt: shown) { return answer }
            return NSNull()
        }
        ctx.setObject(ask, forKeyedSubscript: "__prompt" as NSString)
        let readFile: @convention(block) (String) -> Any = { path in
            if let text = try? String(contentsOfFile: path, encoding: .utf8) { return text }
            return NSNull()
        }
        ctx.setObject(readFile, forKeyedSubscript: "__readFile" as NSString)
        let isFile: @convention(block) (String) -> Bool = { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
        }
        ctx.setObject(isFile, forKeyedSubscript: "__isFile" as NSString)
        let source = prelude
            .replacingOccurrences(of: "__NM_PATH__", with: PackageManager.nodeModules.path)
            .replacingOccurrences(of: "__PROJ_PATH__", with: ProjectStore.directory.path)
        ctx.evaluateScript(source)
        return ctx
    }

    private static func pump(_ ctx: JSContext, term: Terminal, token: Int) {
        while term.isActive(token) {
            let delay = ctx.evaluateScript("__next()")?.toDouble() ?? -1
            if delay.isNaN || delay < 0 { break }
            if delay > 0 {
                Thread.sleep(forTimeInterval: min(delay, 100) / 1000.0)
                if delay > 100 { continue }
            }
            ctx.evaluateScript("__fire()")
        }
    }

    static func run(code: String, term: Terminal, token: Int) {
        let ctx = makeContext(term: term, token: token)
        ctx.evaluateScript(code)
        pump(ctx, term: term, token: token)
    }

    static func repl(_ line: String, term: Terminal, token: Int) {
        if replContext == nil { replContext = makeContext(term: term, token: nil) }
        guard let ctx = replContext else { return }
        if let result = ctx.evaluateScript(line), !result.isUndefined {
            var text = ""
            if result.isString {
                text = "'" + (result.toString() ?? "") + "'"
            } else if let f = ctx.objectForKeyedSubscript("__fmt"),
                      let s = f.call(withArguments: [result])?.toString() {
                text = s
            }
            term.emit(.result, text + "\n")
        }
        pump(ctx, term: term, token: token)
    }
}
