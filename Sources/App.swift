import SwiftUI
import AppKit

final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var projects: [Project] = []
    @Published var inbox = Bucket()
    @Published var toast: String?
    // pinned project paths, in the order they were pinned; they sit above everything else
    @Published private(set) var pinned = Env.defaults.stringArray(forKey: "pinned") ?? [] {
        didSet { Env.defaults.set(pinned, forKey: "pinned") }
    }
    private var toastClear: DispatchWorkItem?

    struct Bucket { var todos: [Todo] = []; var refs: [Ref] = [] }

    // Called every time the panel opens and after every change: agents may have edited the files since.
    func refresh() {
        projects = pinnedFirst(Projects.scan())
        inbox = Bucket(todos: Notes.todos(in: Scope.inbox.dir), refs: Notes.refs(in: Scope.inbox.dir))
    }

    func isPinned(_ p: Project) -> Bool { pinned.contains(p.id) }

    func togglePin(_ p: Project) {
        if let i = pinned.firstIndex(of: p.id) { pinned.remove(at: i) } else { pinned.append(p.id) }
        withAnimation(.easeOut(duration: 0.25)) { projects = pinnedFirst(projects.sorted { $0.activity > $1.activity }) }
    }

    // pinned projects in pin order, then the rest in their existing (activity) order
    private func pinnedFirst(_ ps: [Project]) -> [Project] {
        let top = pinned.compactMap { id in ps.first { $0.id == id } }
        return top + ps.filter { !pinned.contains($0.id) }
    }

    // Inbox first, then every project (pinned first, then most recent activity)
    var scopes: [Scope] { [.inbox] + projects.map { Scope(project: $0.url) } }
    func scope(id: String) -> Scope? { scopes.first { $0.id == id } }
    func todos(_ s: Scope) -> [Todo] { s.project == nil ? inbox.todos : projects.first { $0.url == s.project }?.todos ?? [] }
    func refs(_ s: Scope) -> [Ref] { s.project == nil ? inbox.refs : projects.first { $0.url == s.project }?.refs ?? [] }
    var openTodoCount: Int { scopes.reduce(0) { $0 + todos($1).filter { !$0.done }.count } }
    var refCount: Int { scopes.reduce(0) { $0 + refs($1).count } }

    func open(_ p: Project, fresh: Bool = false) {
        let canContinue = !fresh && p.lastSession != nil && Prefs.shared.agent.continueFlag != nil
        Projects.open(p, continueSession: canContinue) { [weak self] in self?.show($0) }
    }

    private func act(_ what: String, _ s: Scope, _ f: () throws -> Void) {
        do { try f() } catch { show("Couldn't \(what) in \(s.name): \(error.localizedDescription)") }
        withAnimation(.easeOut(duration: 0.2)) { refresh() }
    }

    // MARK: to-dos

    // Returns true if a to-do was added, so the field can clear.
    func addTodo(_ input: String, default fallback: Scope) -> Bool {
        let t = ScopeToken(input, projects: projects)
        let text = t.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return false }
        let s = t.scope ?? fallback
        act("save the to-do", s) { try Notes.addTodo(text, to: s) }
        return true
    }

    func setDone(_ t: Todo, _ done: Bool, in s: Scope) { act("update the to-do", s) { try Notes.setDone(t, done, in: s) } }
    func deleteTodo(_ t: Todo, in s: Scope) { act("delete the to-do", s) { try Notes.deleteTodo(t, in: s) } }
    func moveTodo(_ t: Todo, from a: Scope, to b: Scope) { act("move the to-do", b) { try Notes.moveTodo(t, from: a, to: b) } }

    // MARK: references

    // "https://… a note @project": the first link-like word is the link, the rest is its note.
    // Returns true if a reference was added, so the field can clear.
    func addRef(_ input: String, default fallback: Scope) -> Bool {
        let t = ScopeToken(input, projects: projects)
        var words = t.text.split(separator: " ").map(String.init)
        guard let i = words.firstIndex(where: { Links.parse($0) != nil }), let url = Links.parse(words[i]) else {
            if !t.text.trimmingCharacters(in: .whitespaces).isEmpty {
                show("That doesn't look like a link. Paste a full address, like https://nuevo.tokyo.")
            }
            return false
        }
        words.remove(at: i)
        let s = t.scope ?? fallback
        if refs(s).contains(where: { $0.url == url }) { show("That link is already saved in \(s.name)."); return true }
        let note = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let r = Ref(line: 0, title: Links.placeholder(url), url: url, added: Notes.today(), note: note.isEmpty ? nil : note)
        act("save the link", s) { try Notes.addRef(r, to: s) }
        Links.fetchTitle(url) { [weak self] title in
            guard let self, let title, let cur = self.refs(s).first(where: { $0.url == url }) else { return }
            self.act("save the page title", s) { try Notes.updateRef(cur, in: s) { $0.title = title } }
        }
        return true
    }

    func setNote(_ r: Ref, _ note: String, in s: Scope) {
        let n = note.trimmingCharacters(in: .whitespaces)
        act("save the note", s) { try Notes.updateRef(r, in: s) { $0.note = n.isEmpty ? nil : n } }
    }
    func deleteRef(_ r: Ref, in s: Scope) { act("delete the link", s) { try Notes.deleteRef(r, in: s) } }
    func moveRef(_ r: Ref, from a: Scope, to b: Scope) { act("move the link", b) { try Notes.moveRef(r, from: a, to: b) } }

    // MARK: drag and drop

    // Rows drag as "todo\n<scope id>\n<text>" or "ref\n<scope id>\n<url>"; dropping on a group moves them there.
    static func dragPayload(todo t: Todo, in s: Scope) -> String { "todo\n\(s.id)\n\(t.text)" }
    static func dragPayload(ref r: Ref, in s: Scope) -> String { "ref\n\(s.id)\n\(r.url.absoluteString)" }

    func drop(_ items: [String], on target: Scope) -> Bool {
        var moved = false
        for item in items {
            let parts = item.components(separatedBy: "\n")
            guard parts.count == 3, let from = scope(id: parts[1]), from != target else { continue }
            if parts[0] == "todo", let t = todos(from).first(where: { $0.text == parts[2] }) {
                moveTodo(t, from: from, to: target); moved = true
            } else if parts[0] == "ref", let r = refs(from).first(where: { $0.url.absoluteString == parts[2] }) {
                moveRef(r, from: from, to: target); moved = true
            }
        }
        return moved
    }

    func show(_ message: String) {
        toast = message
        toastClear?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastClear = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: w)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        Monitor.shared.start()
    }
}

struct CmdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var m = AppModel.shared
    @StateObject private var mon = Monitor.shared
    var body: some Scene {
        MenuBarExtra {
            Panel(m: m, mon: mon)
        } label: {
            MenuBarMark(mon: mon)
        }
        .menuBarExtraStyle(.window)
    }
}

// Adapted from baa by Selvi Arora (MIT). See NOTICE.
// Both the login service and a direct launch can start cmd. A process lock keeps
// those paths from creating two menu bar items.
enum GUIInstance {
    private static var lockFD: Int32 = -1

    static func claim() -> Bool {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/xyz.mackiec.cmd" + (Env.demo ? ".demo" : ""), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fputs("cmd: cannot create instance lock directory: \(error)\n", stderr)
            return false
        }
        let fd = Darwin.open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            perror("cmd: cannot open instance lock")
            return false
        }
        guard Darwin.lockf(fd, F_TLOCK, 0) == 0 else {
            Darwin.close(fd)
            return false
        }
        lockFD = fd // Hold the lock until this process exits.
        return true
    }
}

@main
struct Main {
    static func main() {
        guard GUIInstance.claim() else { return }
        CmdApp.main()
    }
}
