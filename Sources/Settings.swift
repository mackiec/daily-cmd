import AppKit

// Where cmd keeps its settings and data. Normally the real home folder and the app's own defaults.
// Demo mode (CMD_DEMO=1, used for the README screenshots) switches to a separate settings store, a fake
// home folder (CMD_HOME), and made-up Mac health numbers, so no real data shows and nothing real is freed.
enum Env {
    static let demo = ProcessInfo.processInfo.environment["CMD_DEMO"] == "1"
    static let realHome = FileManager.default.homeDirectoryForCurrentUser
    static let home: URL = demo
        ? ProcessInfo.processInfo.environment["CMD_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? realHome
        : realHome
    static let defaults: UserDefaults = demo ? UserDefaults(suiteName: "xyz.mackiec.cmd.demo")! : .standard
}

// The coding agent a project opens with.
enum Agent: String, CaseIterable, Identifiable {
    case omp, claude, codex, shell
    var id: String { rawValue }

    var name: String {
        switch self { case .omp: "omp"; case .claude: "Claude Code"; case .codex: "Codex"; case .shell: "Just a shell" }
    }
    var command: String? {
        switch self { case .omp: "omp"; case .claude: "claude"; case .codex: "codex"; case .shell: nil }
    }
    // how to continue the last session in the current folder, for agents that keep sessions per folder
    var continueFlag: String? {
        switch self { case .omp, .claude: "-c"; case .codex, .shell: nil }
    }

    // The folder where this agent keeps a project's sessions; its newest file is the "last session" time.
    //   omp:    ~/.omp/agent/sessions/<path relative to ~, "/" as "-">   (~/Projects/x → -Projects-x)
    //   Claude: ~/.claude/projects/<full path, anything but letters and digits as "-">  (/Users/me/x → -Users-me-x)
    // Codex files its sessions by date, not by folder, so cmd can't tell which belong to a project.
    func sessionDir(for project: URL) -> URL? {
        switch self {
        case .omp:
            guard project.path.hasPrefix(Env.home.path + "/") else { return nil }
            let rel = project.path.dropFirst(Env.home.path.count)
            return Env.home.appendingPathComponent(".omp/agent/sessions/" + rel.replacingOccurrences(of: "/", with: "-"), isDirectory: true)
        case .claude:
            let name = String(project.path.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            return Env.home.appendingPathComponent(".claude/projects/" + name, isDirectory: true)
        case .codex, .shell:
            return nil
        }
    }

    // where command-line tools usually live; a menu bar app doesn't get your shell's PATH
    private static let searchPaths = [".local/bin", ".bun/bin", ".claude/local", ".npm-global/bin"].map { Env.realHome.appendingPathComponent($0).path }
        + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    var installed: Bool {
        guard let command else { return true }
        return Self.searchPaths.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + command) }
    }

    // the first one installed, else a plain shell
    static var detected: Agent { [.omp, .claude, .codex].first { $0.installed } ?? .shell }
}

// The terminal a project opens in. Both take AppleScript, so cmd can open a window or tab and type into it.
enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal, iterm
    var id: String { rawValue }
    var name: String { self == .terminal ? "Terminal" : "iTerm2" }
    var appleScriptName: String { self == .terminal ? "Terminal" : "iTerm" }
    var bundleID: String { self == .terminal ? "com.apple.Terminal" : "com.googlecode.iterm2" }
    var installed: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
    static var detected: TerminalApp { TerminalApp.iterm.installed ? .iterm : .terminal }
}

// Settings the first-run picker and the settings section edit. Saved as they change.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = Env.defaults

    @Published var projectsRoot: URL { didSet { d.set(projectsRoot.path, forKey: "projectsRoot") } }
    @Published var agent: Agent { didSet { d.set(agent.rawValue, forKey: "agent") } }
    @Published var terminal: TerminalApp { didSet { d.set(terminal.rawValue, forKey: "terminal") } }
    // add the "to-dos and links live in .cmd/" line to a project's AGENTS.md (creating it if needed)
    @Published var agentsPointer: Bool { didSet { d.set(agentsPointer, forKey: "agentsPointer") } }
    @Published var setupDone: Bool { didSet { d.set(setupDone, forKey: "setupDone") } }

    private init() {
        projectsRoot = d.string(forKey: "projectsRoot").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Prefs.folderCandidates().first ?? Env.home.appendingPathComponent("Projects", isDirectory: true)
        agent = Agent(rawValue: d.string(forKey: "agent") ?? "") ?? .detected
        terminal = TerminalApp(rawValue: d.string(forKey: "terminal") ?? "") ?? .detected
        agentsPointer = d.object(forKey: "agentsPointer") as? Bool ?? true
        setupDone = d.bool(forKey: "setupDone")
    }

    // common places people keep code, that exist on this Mac
    static func folderCandidates() -> [URL] {
        ["Projects", "Developer", "Code", "code", "src", "dev", "GitHub", "repos", "Sites"]
            .map { Env.home.appendingPathComponent($0, isDirectory: true) }
            .filter { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: $0.path, isDirectory: &d) && d.boolValue }
            .reduce(into: [URL]()) { out, u in if !out.contains(where: { $0.path.lowercased() == u.path.lowercased() }) { out.append(u) } }
    }
}
