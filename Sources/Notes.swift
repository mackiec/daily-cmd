import Foundation

// To-dos and references live in plain Markdown (see technical-constraints.md):
//   - [ ] text · 2026-11-26
//   - [x] text · 2026-11-20 → 2026-11-24
//   - [Title](https://url) · 2026-11-26
//     optional note
// Dates are optional. Lines cmd doesn't recognise are kept as they are.

// Where an item lives: the global Inbox (~/.cmd) or one project (<project>/.cmd).
struct Scope: Hashable, Identifiable {
    let project: URL?
    static let inbox = Scope(project: nil)

    var id: String { dir.path }
    var dir: URL { Notes.dir(for: project) }
    var name: String { project?.lastPathComponent ?? "Inbox" }
    var todoFile: URL { dir.appendingPathComponent("todo.md") }
    var refFile: URL { dir.appendingPathComponent("refs.md") }
}

struct Todo: Identifiable, Hashable {
    let line: Int
    var text: String
    var done: Bool
    var added: String?
    var finished: String?
    var id: Int { line }
    var finishedDate: Date? { finished.flatMap(Notes.day.date(from:)) }
}

struct Ref: Identifiable, Hashable {
    let line: Int
    var title: String
    var url: URL
    var added: String?
    var note: String?
    var id: Int { line }
}

enum Notes {
    static let inbox = Projects.home.appendingPathComponent(".cmd", isDirectory: true)
    static let pointer = "Open to-dos and saved references for this project live in `.cmd/todo.md` and `.cmd/refs.md` "
        + "(local only, not in git). Read them at the start of a session; add to them when asked."

    static func dir(for project: URL?) -> URL {
        project?.appendingPathComponent(".cmd", isDirectory: true) ?? inbox
    }

    static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func today() -> String { day.string(from: .now) }

    private static let todoLine = try! NSRegularExpression(
        pattern: #"^- \[([ xX])\] (.*?)(?: · (\d{4}-\d{2}-\d{2}))?(?: → (\d{4}-\d{2}-\d{2}))?\s*$"#)
    private static let refLine = try! NSRegularExpression(
        pattern: #"^- \[(.+)\]\((\S+)\)(?: · (\d{4}-\d{2}-\d{2}))?\s*$"#)

    // MARK: reading

    private static func lines(_ file: URL) -> [String] {
        guard let s = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return s.components(separatedBy: "\n")
    }

    private static func groups(_ re: NSRegularExpression, _ line: String) -> [String?]? {
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }

    private static func todo(_ line: String, at i: Int) -> Todo? {
        guard let g = groups(todoLine, line), let mark = g[0], let text = g[1] else { return nil }
        return Todo(line: i, text: text, done: mark != " ", added: g[2], finished: g[3])
    }

    private static func ref(_ ls: [String], at i: Int) -> Ref? {
        guard let g = groups(refLine, ls[i]), let title = g[0], let raw = g[1], let url = URL(string: raw) else { return nil }
        return Ref(line: i, title: title, url: url, added: g[2], note: noteLine(ls, after: i))
    }

    private static func noteLine(_ ls: [String], after i: Int) -> String? {
        guard i + 1 < ls.count, ls[i + 1].hasPrefix("  ") else { return nil }
        let t = ls[i + 1].trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasPrefix("- ") ? nil : t
    }

    static func todos(in dir: URL) -> [Todo] {
        lines(dir.appendingPathComponent("todo.md")).enumerated().compactMap { todo($1, at: $0) }
    }

    static func refs(in dir: URL) -> [Ref] {
        let ls = lines(dir.appendingPathComponent("refs.md"))
        return ls.indices.compactMap { ref(ls, at: $0) }
    }

    // MARK: writing

    static func format(_ t: Todo) -> String {
        "- [\(t.done ? "x" : " ")] \(t.text)" + (t.added.map { " · \($0)" } ?? "") + (t.finished.map { " → \($0)" } ?? "")
    }

    static func format(_ r: Ref) -> [String] {
        let title = r.title.replacingOccurrences(of: "]", with: ")").replacingOccurrences(of: "[", with: "(")
        return ["- [\(title)](\(r.url.absoluteString))" + (r.added.map { " · \($0)" } ?? "")] + (r.note.map { ["  \($0)"] } ?? [])
    }

    private static func save(_ ls: [String], _ file: URL) throws {
        var ls = ls
        while ls.last?.isEmpty == true { ls.removeLast() }
        try (ls.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private static func append(_ new: [String], to file: URL, header: String) throws {
        var ls = lines(file)
        while ls.last?.isEmpty == true { ls.removeLast() }
        if ls.isEmpty { ls = [header] }
        try save(ls + new, file)
    }

    // The line may have moved since it was read (an agent edited the file): find it again by content.
    private static func locate(_ t: Todo, in ls: [String]) -> Int? {
        if t.line < ls.count, let cur = todo(ls[t.line], at: t.line), cur.text == t.text { return t.line }
        return ls.indices.first { todo(ls[$0], at: $0)?.text == t.text }
    }

    private static func locate(_ r: Ref, in ls: [String]) -> Int? {
        if r.line < ls.count, ref(ls, at: r.line)?.url == r.url { return r.line }
        return ls.indices.first { ref(ls, at: $0)?.url == r.url }
    }

    static func addTodo(_ text: String, to s: Scope) throws {
        try prepare(s)
        try append([format(Todo(line: 0, text: text, done: false, added: today()))], to: s.todoFile, header: "# To-do")
    }

    static func setDone(_ t: Todo, _ done: Bool, in s: Scope) throws {
        var ls = lines(s.todoFile)
        guard let i = locate(t, in: ls), var u = todo(ls[i], at: i) else { return }
        u.done = done
        u.finished = done ? today() : nil
        ls[i] = format(u)
        try save(ls, s.todoFile)
    }

    static func deleteTodo(_ t: Todo, in s: Scope) throws {
        var ls = lines(s.todoFile)
        guard let i = locate(t, in: ls) else { return }
        ls.remove(at: i)
        try save(ls, s.todoFile)
    }

    static func moveTodo(_ t: Todo, from a: Scope, to b: Scope) throws {
        guard a != b else { return }
        let ls = lines(a.todoFile)
        guard let i = locate(t, in: ls), let cur = todo(ls[i], at: i) else { return }
        try prepare(b)
        try append([format(cur)], to: b.todoFile, header: "# To-do")
        try deleteTodo(cur, in: a)
    }

    static func addRef(_ r: Ref, to s: Scope) throws {
        try prepare(s)
        try append(format(r), to: s.refFile, header: "# References")
    }

    // Rewrites one reference in place (title arrived, note edited), keeping its position.
    static func updateRef(_ r: Ref, in s: Scope, _ change: (inout Ref) -> Void) throws {
        var ls = lines(s.refFile)
        guard let i = locate(r, in: ls), var cur = ref(ls, at: i) else { return }
        let span = cur.note == nil ? 1 : 2
        change(&cur)
        ls.replaceSubrange(i..<(i + span), with: format(cur))
        try save(ls, s.refFile)
    }

    static func deleteRef(_ r: Ref, in s: Scope) throws {
        var ls = lines(s.refFile)
        guard let i = locate(r, in: ls), let cur = ref(ls, at: i) else { return }
        ls.removeSubrange(i..<(i + (cur.note == nil ? 1 : 2)))
        try save(ls, s.refFile)
    }

    static func moveRef(_ r: Ref, from a: Scope, to b: Scope) throws {
        guard a != b else { return }
        let ls = lines(a.refFile)
        guard let i = locate(r, in: ls), let cur = ref(ls, at: i) else { return }
        try addRef(cur, to: b)
        try deleteRef(cur, in: a)
    }

    // MARK: project setup

    // Before a project's first item: create .cmd/, keep it out of git (local-only exclude list),
    // and point agents at it from AGENTS.md (creating the file if there isn't one).
    // Safe to run every time: each step checks first.
    static func prepare(_ s: Scope) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: s.dir, withIntermediateDirectories: true)
        guard let p = s.project else { return }

        var isDir: ObjCBool = false
        let git = p.appendingPathComponent(".git")
        if fm.fileExists(atPath: git.path, isDirectory: &isDir), isDir.boolValue {
            let info = git.appendingPathComponent("info", isDirectory: true)
            try fm.createDirectory(at: info, withIntermediateDirectories: true)
            let exclude = info.appendingPathComponent("exclude")
            let cur = (try? String(contentsOf: exclude, encoding: .utf8)) ?? ""
            let listed = cur.split(separator: "\n").contains { [".cmd", ".cmd/", "/.cmd", "/.cmd/"].contains($0.trimmingCharacters(in: .whitespaces)) }
            if !listed {
                try (cur + (cur.isEmpty || cur.hasSuffix("\n") ? "" : "\n") + ".cmd/\n").write(to: exclude, atomically: false, encoding: .utf8)
            }
        }

        guard Prefs.shared.agentsPointer else { return }
        let agents = p.appendingPathComponent("AGENTS.md")
        if let cur = try? String(contentsOf: agents, encoding: .utf8) {
            if !cur.contains(".cmd/todo.md") {
                let sep = cur.isEmpty ? "" : cur.hasSuffix("\n\n") ? "" : cur.hasSuffix("\n") ? "\n" : "\n\n"
                // not atomic: an atomic write would replace a symlinked AGENTS.md with a plain file
                try (cur + sep + pointer + "\n").write(to: agents, atomically: false, encoding: .utf8)
            }
        } else {
            try (pointer + "\n").write(to: agents, atomically: true, encoding: .utf8)
        }
    }
}
