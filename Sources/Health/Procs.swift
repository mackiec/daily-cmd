// Adapted from baa by Selvi Arora (MIT). See NOTICE.
import AppKit
import Darwin

struct Proc {
    let pid: Int, ppid: Int, uid: Int, rssKB: Int
    let elapsed: Double, cpu: Double, pcpu: Double
    let exe: String, cmd: String
    var label = ""
    var bytes = 0.0
    var base: String { (exe as NSString).lastPathComponent }
}

// same number Activity Monitor shows. unlike rss it includes memory macOS has compressed,
// which is exactly what idle leftovers turn into. only readable for your own processes
func footprint(_ pid: Int) -> Double? {
    var info = rusage_info_v4()
    let ok = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(Int32(pid), RUSAGE_INFO_V4, $0) }
    }
    return ok == 0 ? Double(info.ri_phys_footprint) : nil
}

// "[dd-][hh:]mm:ss[.cc]" -> seconds (works for both etime and cputime)
func secs(_ s: Substring) -> Double {
    var days = 0.0, rest = s
    if let d = s.firstIndex(of: "-") { days = Double(s[..<d]) ?? 0; rest = s[s.index(after: d)...] }
    return days * 86400 + rest.split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
}

let agentLabels: Set<String> = ["Claude Code", "Codex", "omp"]
let runtimeLabels: Set<String> = ["Node", "Python", "Bun", "Deno", "Ruby", "Java", "Headless browser", "Gradle", "Kotlin daemon"]
let shells: Set<String> = ["zsh", "-zsh", "bash", "-bash", "sh", "fish", "-fish", "login", "tmux", "screen"]

// how to pick an idle agent session back up later
func resumeHint(_ label: String) -> String {
    switch label {
    case "Codex": return "codex resume"
    case "omp": return "omp -c"
    default: return "claude --resume"
    }
}

func isHeadless(_ exe: String, _ cmd: String) -> Bool {
    ["ms-playwright", "puppeteer", "chrome-headless-shell", "Chrome for Testing"].contains { exe.contains($0) }
        || (cmd.contains("--headless") && (exe.contains("Chrom") || exe.contains("chrom")))
}

// outermost .app in the path, so every "Google Chrome Helper" rolls up into "Google Chrome"
func appName(_ exe: String) -> String? {
    guard let r = exe.range(of: ".app/") else { return nil }
    return exe[..<r.lowerBound].split(separator: "/").last.map(String.init)
}

func label(_ exe: String, _ cmd: String) -> String {
    let base = (exe as NSString).lastPathComponent
    if cmd.contains("GradleDaemon") { return "Gradle" }
    if cmd.contains("KotlinCompileDaemon") || cmd.contains("kotlin-daemon") { return "Kotlin daemon" }
    if base.hasPrefix("qemu-system") || base == "emulator" { return "Android emulator" }
    if exe.contains("launchd_sim") || exe.contains("/CoreSimulator/Devices/") || exe.contains("Simulator.app/Contents/MacOS/Simulator") { return "iOS Simulator" }
    if isHeadless(exe, cmd) { return "Headless browser" }
    if base.lowercased().hasPrefix("python") { return "Python" }
    if base == "claude" || exe.contains("/claude/versions/") { return "Claude Code" }
    if base == "codex" { return "Codex" }
    if base == "omp" { return "omp" }
    if let a = appName(exe) { return a }
    switch base {
    case "node": return "Node"
    case "bun": return "Bun"
    case "deno": return "Deno"
    case "ruby": return "Ruby"
    case "java": return "Java"
    case "ollama": return "Ollama"
    default: return base
    }
}

func readProcs() -> [Int: Proc] {
    var exe: [Int: String] = [:]
    for line in run("/bin/ps", ["-axww", "-o", "pid=,comm="]).out.split(separator: "\n") {
        let t = line.drop(while: { $0 == " " })
        guard let sp = t.firstIndex(of: " "), let pid = Int(t[..<sp]) else { continue }
        exe[pid] = String(t[sp...].drop(while: { $0 == " " }))
    }
    var out: [Int: Proc] = [:]
    for line in run("/bin/ps", ["-axww", "-o", "pid=,ppid=,uid=,rss=,etime=,time=,%cpu=,command="]).out.split(separator: "\n") {
        let f = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
        guard f.count == 8, let pid = Int(f[0]), let ppid = Int(f[1]), let uid = Int(f[2]), let rss = Int(f[3]) else { continue }
        let e = exe[pid] ?? String(f[7])
        var p = Proc(pid: pid, ppid: ppid, uid: uid, rssKB: rss, elapsed: secs(f[4]), cpu: secs(f[5]),
                     pcpu: Double(f[6]) ?? 0, exe: e, cmd: String(f[7]))
        p.label = label(e, p.cmd)
        p.bytes = footprint(pid) ?? Double(rss) * 1024
        out[pid] = p
    }
    return out
}

// short name for what a node/python process is actually running
func hint(_ p: Proc) -> String? {
    let toks = p.cmd.split(separator: " ").map(String.init)
    for w in ["vite", "next", "webpack", "jupyter", "uvicorn", "streamlit", "gunicorn", "flask", "expo", "metro"]
    where toks.contains(where: { ($0 as NSString).lastPathComponent == w || ($0 as NSString).lastPathComponent.hasPrefix(w + "-") }) { return w }
    if let i = toks.firstIndex(of: "-m"), i + 1 < toks.count { return toks[i + 1] }
    if let s = toks.dropFirst().first(where: { t in [".py", ".js", ".mjs", ".cjs", ".ts"].contains { t.hasSuffix($0) } }) {
        return (s as NSString).lastPathComponent
    }
    return nil
}

// what one process of an app is doing: chrome-style helpers say so in their arguments
func role(_ p: Proc) -> String {
    let c = p.cmd
    if c.contains("--extension-process") { return "extension" }
    if c.contains("--type=renderer") { return whatIs(p.label) == "browser" ? "tab" : "window" }
    if c.contains("--type=gpu-process") { return "graphics" }
    if c.contains("NetworkService") { return "network" }
    if c.contains("AudioService") { return "audio" }
    if c.contains("StorageService") { return "storage" }
    if c.contains("--type=") { return "helper" }
    if let a = appName(p.exe), p.exe.contains("/\(a).app/Contents/MacOS/"), !p.exe.contains("/Helpers/") { return "main app" }
    if let h = hint(p) { return h }
    return p.exe.contains(".app/") ? "helper" : p.base
}

// "1051M", "8450K", "1.2G+" -> bytes
func topSize(_ s: Substring) -> Double {
    let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
    let units: [Character: Double] = ["B": 1, "K": 1024, "M": 1_048_576, "G": 1_073_741_824, "T": 1_099_511_627_776]
    guard let u = t.last, let k = units[u], let v = Double(t.dropLast()) else { return Double(t) ?? 0 }
    return v * k
}

// the running app's icon, or the installed app's when it isn't running
func appIcon(_ name: String) -> NSImage? {
    if let i = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })?.icon { return i }
    let path = ["/Applications", "/System/Applications"].map { "\($0)/\(name).app" }.first { FileManager.default.fileExists(atPath: $0) }
    // resolve links (Safari in /Applications is one), or the icon carries an alias arrow
    return path.map { NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: $0).resolvingSymlinksInPath().path) }
}

// what that process actually is, for names nobody recognizes
func whatIs(_ name: String) -> String? {
    let n = name.lowercased()
    if n == "omp" { return "ai agent" }
    let table: [(String, String)] = [
        ("chrome", "browser"), ("safari", "browser"), ("arc", "browser"), ("firefox", "browser"), ("opera", "browser"),
        ("xcode", "iOS dev"), ("simulator", "iPhone simulator"), ("simmetalhost", "simulator graphics"),
        ("android studio", "android dev"), ("emulator", "android emulator"), ("gradle", "android builds"), ("kotlin", "android builds"),
        ("java", "runtime"), ("claude", "ai agent"), ("codex", "ai agent"), ("cursor", "code editor"), ("code", "code editor"),
        ("docker", "containers"), ("virtual", "virtual machine"), ("ollama", "local ai model"), ("python", "script"), ("node", "javascript"),
        ("bun", "javascript"), ("iterm", "terminal"), ("spotify", "music"), ("slack", "chat"), ("discord", "chat"), ("whatsapp", "chat"),
        ("zoom", "calls"), ("wispr", "dictation"), ("lightroom", "photos"), ("photos", "photos"),
        ("windowserver", "draws your screen"), ("kernel", "macOS itself"), ("mds", "spotlight indexing"),
    ]
    return table.first { n.contains($0.0) }?.1
}
