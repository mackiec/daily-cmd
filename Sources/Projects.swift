import AppKit

struct Project: Identifiable {
    let url: URL
    let lastSession: Date?
    let modified: Date
    var todos: [Todo] = []
    var refs: [Ref] = []

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var openTodos: [Todo] { todos.filter { !$0.done } }
    var activity: Date { max(lastSession ?? .distantPast, modified) }
}

enum Projects {
    static var home: URL { Env.home }

    static func scan() -> [Project] {
        let fm = FileManager.default, prefs = Prefs.shared
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let entries = try? fm.contentsOfDirectory(at: prefs.projectsRoot, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }
        return entries.compactMap { url -> Project? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isDirectory == true else { return nil }
            let dir = Notes.dir(for: url)
            return Project(url: url, lastSession: lastSession(url, prefs.agent), modified: v.contentModificationDate ?? .distantPast,
                           todos: Notes.todos(in: dir), refs: Notes.refs(in: dir))
        }
        .sorted { $0.activity > $1.activity }
    }

    // newest file in the agent's session folder for this project (nil for agents that don't keep one)
    static func lastSession(_ url: URL, _ agent: Agent) -> Date? {
        guard let dir = agent.sessionDir(for: url),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        return files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }

    // Both scripts take the shell line as their argument, so it never needs AppleScript escaping.
    // When the app wasn't running, they wait for the window it opens on launch and reuse it.
    private static func script(_ t: TerminalApp) -> String {
        switch t {
        case .iterm: return """
            on run argv
              set cmdText to item 1 of argv
              set wasRunning to application "iTerm" is running
              tell application "iTerm"
                activate
                if not wasRunning then
                  repeat 30 times
                    if (count of windows) > 0 then exit repeat
                    delay 0.1
                  end repeat
                end if
                if (count of windows) = 0 then
                  create window with default profile
                else if wasRunning then
                  tell current window to create tab with default profile
                end if
                tell current session of current window to write text cmdText
              end tell
            end run
            """
        case .terminal: return """
            on run argv
              set cmdText to item 1 of argv
              set wasRunning to application "Terminal" is running
              tell application "Terminal"
                activate
                if not wasRunning then
                  repeat 30 times
                    if (count of windows) > 0 then exit repeat
                    delay 0.1
                  end repeat
                end if
                if (not wasRunning) and (count of windows) > 0 then
                  do script cmdText in window 1
                else
                  do script cmdText
                end if
              end tell
            end run
            """
        }
    }

    // Opens the project in the chosen terminal and starts the chosen agent there (or just a shell).
    // Calls back with an error message (on the main queue) if it failed.
    static func open(_ p: Project, continueSession: Bool, onError: @escaping (String) -> Void) {
        let prefs = Prefs.shared, term = prefs.terminal
        let quoted = "'" + p.url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        var line = "cd \(quoted)"
        if let c = prefs.agent.command {
            line += " && " + c + (continueSession ? prefs.agent.continueFlag.map { " " + $0 } ?? "" : "")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script(term), line]
        let err = Pipe()
        proc.standardError = err
        proc.standardOutput = FileHandle.nullDevice
        proc.terminationHandler = { pr in
            guard pr.terminationStatus != 0 else { return }
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let text = msg.contains("-1743")
                ? "cmd isn't allowed to control \(term.name). Allow it in System Settings → Privacy & Security → Automation."
                : "Couldn't open \(term.name): \(msg.trimmingCharacters(in: .whitespacesAndNewlines))"
            DispatchQueue.main.async { onError(text) }
        }
        do { try proc.run() } catch { onError("Couldn't run osascript: \(error.localizedDescription)") }
    }

    static func reveal(_ p: Project) { NSWorkspace.shared.activateFileViewerSelecting([p.url]) }

    static func copyPath(_ p: Project) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(p.url.path, forType: .string)
    }
}

func ago(_ d: Date, now: Date = .now) -> String {
    let m = Int(max(0, now.timeIntervalSince(d)) / 60)
    if m < 1 { return "just now" }
    if m < 60 { return "\(m)m ago" }
    let h = m / 60
    if h < 24 { return "\(h)h ago" }
    let days = h / 24
    if days < 14 { return "\(days)d ago" }
    if days < 60 { return "\(days / 7)w ago" }
    return "\(days / 30)mo ago"
}
