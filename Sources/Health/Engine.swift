// Adapted from baa by Selvi Arora (MIT). See NOTICE.
import Foundation
import Darwin

enum Kind { case ghost, agent, idle, hot }
enum Fix { case kill([Int]), quit(String), run(String, [String]) }

struct Finding: Identifiable {
    let id: String, kind: Kind, title: String, detail: String, bytes: Double, fix: Fix
    var freeLabel: String { kind == .hot ? "Stop" : "Free \(size(bytes))" }

    // who left it running
    var culprit: String {
        if let r = detail.range(of: "started by ") {
            let rest = detail[r.upperBound...]
            return String(rest.prefix { $0 != "(" && $0 != "·" && $0 != "," }).trimmingCharacters(in: .whitespaces)
        }
        return kind == .idle ? "Sitting idle" : "Left behind"
    }
    var emoji: String { kind == .hot ? "🔥" : kind == .ghost ? "👻" : kind == .agent ? "🤖" : "💤" }
}

// one app's share, rolled up from all its processes, with what those processes are for
struct AppUse {
    var name: String, gb: Double
    var pids: [Int] = [], cpu = 0.0, quiet = 0.0
    var packed: Double? = nil   // how much of it macOS has compressed or swapped (filled in by Engine.owners)
    var parts: [(role: String, count: Int, bytes: Double)] = []
    // one line under the name: what it is and whether it's busy right now
    var doing: String {
        let state = cpu >= 5 ? "busy · \(Int(cpu.rounded()))% CPU" : quiet >= 600 ? "idle \(dur(quiet))" : "quiet"
        return [whatIs(name), state].compactMap { $0 }.joined(separator: " · ")
    }
}

// whose memory it is: you, another login on this mac, or macOS itself
struct Owner { let name: String, bytes: Double }

struct Scan {
    var apps: [AppUse] = []
    var owners: [Owner]? = nil
    var findings: [Finding] = []
    var freeable: Double { findings.reduce(0) { $0 + $1.bytes } }
}

final class Engine {
    // per-pid cpu history, so "idle" means "hasn't used CPU lately", not just "low right now"
    private var seen: [Int: (cpu: Double, at: Date, active: Date, born: Date)] = [:]
    // when each pid started burning CPU (>= half a core), to catch runaways that never go idle
    private var hotSince: [Int: Date] = [:]
    private let me = Int(getuid())

    private func idle(_ p: Proc, _ now: Date) -> Double {
        let born = now.addingTimeInterval(-p.elapsed)
        if var s = seen[p.pid], abs(s.born.timeIntervalSince(born)) < 90 {
            let dt = now.timeIntervalSince(s.at)
            if dt > 0, (p.cpu - s.cpu) / dt >= 0.01 { s.active = now }
            s.cpu = p.cpu; s.at = now; seen[p.pid] = s
            return now.timeIntervalSince(s.active)
        }
        // first sighting: if it's barely touched the CPU in its whole life, call it idle since birth
        let quiet = p.elapsed > 0 && p.cpu / p.elapsed < 0.01
        let active = quiet ? born : now
        seen[p.pid] = (p.cpu, now, active, born)
        return now.timeIntervalSince(active)
    }

    private func launchdPIDs() -> Set<Int> {
        Set(run("/bin/launchctl", ["list"]).out.split(separator: "\n").compactMap { Int($0.split(separator: "\t").first ?? "") })
    }

    private func listeningPorts() -> [Int: [Int]] {
        var out: [Int: [Int]] = [:], cur = 0
        for l in run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-u", "\(me)", "-Fpn"]).out.split(separator: "\n") {
            if l.hasPrefix("p") { cur = Int(l.dropFirst()) ?? 0 }
            else if l.hasPrefix("n"), let c = l.lastIndex(of: ":"), let port = Int(l[l.index(after: c)...]),
                    !(out[cur]?.contains(port) ?? false) { out[cur, default: []].append(port) }
        }
        return out
    }

    private func cwds(_ pids: [Int]) -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        var out: [Int: String] = [:], cur = 0
        let args = ["-a", "-d", "cwd", "-p", pids.map(String.init).joined(separator: ","), "-Fpn"]
        for l in run("/usr/sbin/lsof", args).out.split(separator: "\n") {
            if l.hasPrefix("p") { cur = Int(l.dropFirst()) ?? 0 }
            else if l.hasPrefix("n") { out[cur] = (String(l.dropFirst()) as NSString).lastPathComponent }
        }
        return out
    }

    private func systemish(_ p: Proc) -> Bool {
        if runtimeLabels.contains(p.label) || agentLabels.contains(p.label) { return false }
        if !p.exe.hasPrefix("/") { return true } // bare names are almost always macOS agents
        let sys = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/", "/Library/Developer/",
                   "/Library/PrivilegedHelperTools/", "/Library/Application Support/", "/private/"]
        return sys.contains { p.exe.hasPrefix($0) } || [".app/", ".xpc/", ".framework/"].contains { p.exe.contains($0) }
    }

    func scan(owners: Bool = false) -> Scan {
        let now = Date()
        let procs = readProcs()
        seen = seen.filter { procs[$0.key] != nil }
        hotSince = hotSince.filter { procs[$0.key] != nil }

        var kids: [Int: [Int]] = [:]
        for p in procs.values where p.pid != p.ppid { kids[p.ppid, default: []].append(p.pid) }
        func tree(_ pid: Int) -> [Int] {
            var out = [pid], i = 0
            while i < out.count { out += kids[out[i]] ?? []; i += 1 }
            return out
        }
        let mine = procs.values.filter { $0.uid == me }.sorted { $0.pid < $1.pid }
        var idleOf: [Int: Double] = [:], hotFor: [Int: Double] = [:]
        for p in mine {
            let first = seen[p.pid] == nil
            idleOf[p.pid] = idle(p, now)
            if p.pcpu >= 50 {
                // first sighting: trust its lifetime average instead of waiting
                let since = hotSince[p.pid] ?? (first && p.cpu / max(p.elapsed, 1) >= 0.5 ? now.addingTimeInterval(-p.elapsed) : now)
                hotSince[p.pid] = since; hotFor[p.pid] = now.timeIntervalSince(since)
            } else { hotSince[p.pid] = nil }
        }
        func treeIdle(_ pids: [Int]) -> Double { pids.compactMap { idleOf[$0] }.min() ?? 0 }
        func treeBytes(_ pids: [Int]) -> Double { pids.compactMap { procs[$0]?.bytes }.reduce(0, +) }

        // never suggest killing cmd itself or whatever launched it
        var claimed = Set<Int>([Int(getpid())])
        var a = Int(getppid())
        while let p = procs[a], a > 1 { claimed.insert(a); a = p.ppid }

        var found: [Finding] = []
        func add(_ id: String, _ kind: Kind, _ title: String, _ detail: String, _ pids: [Int], fix: Fix? = nil) {
            let pids = pids.filter { !claimed.contains($0) && procs[$0]?.uid == me }
            guard !pids.isEmpty, kind == .hot || treeBytes(pids) >= 50 * 1_048_576 else { return }
            claimed.formUnion(pids)
            found.append(Finding(id: id, kind: kind, title: title, detail: detail, bytes: treeBytes(pids), fix: fix ?? .kill(pids)))
        }

        let ideOpen = mine.contains {
            $0.label != "Gradle" && $0.label != "Kotlin daemon" &&
            ($0.exe.contains("Android Studio.app/Contents/MacOS/") || ($0.exe.contains("IntelliJ IDEA") && $0.exe.contains("/Contents/MacOS/")))
        }
        let simAppOpen = mine.contains { $0.exe.contains("Simulator.app/Contents/MacOS/Simulator") }

        // Gradle / Kotlin daemons outlive Android Studio by design
        let daemons = mine.filter { $0.label == "Gradle" || $0.label == "Kotlin daemon" }
        if !daemons.isEmpty {
            let pids = daemons.flatMap { tree($0.pid) }, i = treeIdle(pids)
            if !ideOpen && i >= mins(2) {
                add("gradle", .ghost, "Gradle + Kotlin daemons", "Android Studio is closed but these are still holding memory", pids)
            } else if i >= mins(20) {
                add("gradle", .idle, "Gradle + Kotlin daemons", "idle \(dur(i)) · they restart on your next build", pids)
            }
        }

        // simulators keep running after you close the Simulator window
        let sims = mine.filter { $0.exe.contains("launchd_sim") }
        if !sims.isEmpty && !simAppOpen {
            add("simulator", .ghost, "iOS Simulator (background)", "still booted, but the Simulator app is closed",
                sims.flatMap { tree($0.pid) }, fix: .run("/usr/bin/xcrun", ["simctl", "shutdown", "all"]))
        }

        // Android emulator
        let emu = mine.filter { $0.label == "Android emulator" && procs[$0.ppid]?.label != "Android emulator" }
        for e in emu {
            let pids = tree(e.pid), i = treeIdle(pids)
            if !ideOpen && i >= mins(10) { add("emulator", .ghost, "Android emulator", "Android Studio is closed · idle \(dur(i))", pids) }
            else if i >= mins(20) { add("emulator", .idle, "Android emulator", "no activity for \(dur(i))", pids) }
        }

        // Docker VM with nothing in it
        if let vm = mine.first(where: { ["com.docker.virtualization", "com.docker.hyperkit", "com.docker.krun"].contains(where: $0.cmd.contains) }) {
            let cli = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
                .first { FileManager.default.isExecutableFile(atPath: $0) }
            if let cli {
                let r = run(cli, ["ps", "-q"])
                if r.status == 0 && r.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add("docker", .idle, "Docker", "VM is running with no containers", tree(vm.pid), fix: .quit("Docker"))
                }
            }
        }

        // Ollama keeps the last model in RAM
        for p in mine where p.label == "Ollama" && p.cmd.contains(" runner") {
            let pids = tree(p.pid), i = treeIdle(pids)
            if i >= mins(10) { add("ollama-\(p.pid)", .idle, "Ollama model", "still loaded, idle \(dur(i)) · reloads next time you use it", pids) }
        }

        // AI agents: what they leave running, then the sessions themselves
        let sessions = mine.filter { agentLabels.contains($0.label) && procs[$0.ppid]?.label != $0.label &&
                                     !$0.cmd.contains("--chrome-native-host") && !$0.cmd.contains(" mcp") }
        let cwd = cwds(sessions.map(\.pid))
        func agentRoot(_ p: Proc) -> Proc? {
            var a = p.ppid
            while let q = procs[a], a > 1 {
                if agentLabels.contains(q.label) || q.label == "Cursor" { return procs[a] }
                a = q.ppid
            }
            return nil
        }
        func who(_ r: Proc) -> String { r.label + (cwd[r.pid].map { " (\($0))" } ?? "") }
        let ports = listeningPorts()
        for p in mine where !claimed.contains(p.pid) {
            let headless = p.label == "Headless browser"
            guard headless || (["Node", "Python", "Bun", "Deno", "Ruby"].contains(p.label) && ports[p.pid] != nil) else { continue }
            if procs[p.ppid]?.label == p.label { continue } // only the top of a browser/server tree
            let root = agentRoot(p)
            guard root != nil || p.ppid == 1 else { continue }
            let pids = tree(p.pid), i = treeIdle(pids)
            guard i >= mins(15), p.elapsed >= mins(15) else { continue }
            let title = headless
                ? "Headless browser" + (p.exe.contains("playwright") ? " (Playwright)" : p.exe.contains("puppeteer") ? " (Puppeteer)" : "")
                : "Dev server" + (ports[p.pid]?.min().map { " :\($0)" } ?? "") + " · " + (hint(p) ?? p.label.lowercased())
            let by = root.map { "started by \(who($0))" } ?? "whatever started it is gone"
            add("agent-\(p.pid)", .agent, title, "\(by) · idle \(dur(i))", pids)
        }
        for s in sessions {
            let pids = tree(s.pid), i = treeIdle(pids)
            guard i >= mins(60) else { continue }
            add("session-\(s.pid)", .idle, "\(s.label) session" + (cwd[s.pid].map { " · \($0)" } ?? ""),
                "idle \(dur(i)) · pick it back up later with \(resumeHint(s.label))", pids)
        }

        // runaways: leftovers stuck burning CPU (fans + battery), which never look idle so the checks below miss them
        let launchd = launchdPIDs()
        for p in mine where (hotFor[p.pid] ?? 0) >= mins(5) && !claimed.contains(p.pid) && !shells.contains(p.base)
                            && !agentLabels.contains(p.label) && !systemish(p) {
            // climb to the top of the job (eg npm -> node -> esbuild), stopping at a shell, agent, app or launchd
            var top = p
            while let q = procs[top.ppid], q.pid > 1, q.uid == me, !shells.contains(q.base), !agentLabels.contains(q.label), !systemish(q) { top = q }
            let orphan = top.ppid == 1 && !launchd.contains(top.pid)
            let root = agentRoot(top), quiet = root.flatMap { idleOf[$0.pid] } ?? 0
            // a terminal you still have open is your call
            guard orphan || (root != nil && !claimed.contains(root!.pid) && quiet >= mins(15)) else { continue }
            let pids = tree(top.pid), load = pids.compactMap { procs[$0]?.pcpu }.reduce(0, +)
            let by = orphan ? "its terminal or agent closed" : "started by \(who(root!)), idle \(dur(quiet))"
            add("hot-\(top.pid)", .hot, top.label + (hint(top).map { " · \($0)" } ?? ""),
                "\(Int(load.rounded()))% CPU for \(dur(hotFor[p.pid]!)) · \(by)", pids)
        }

        // orphans: reparented to launchd because the terminal / agent that started them closed
        for p in mine where p.ppid == 1 && !claimed.contains(p.pid) && !launchd.contains(p.pid) && !systemish(p) {
            if p.base.hasPrefix("tmux") || p.base.hasPrefix("screen") { continue }
            let pids = tree(p.pid).filter { !claimed.contains($0) }
            let b = treeBytes(pids), i = treeIdle(pids)
            guard b >= 150 * 1_048_576, i >= mins(10), p.elapsed >= mins(10),
                  let big = pids.compactMap({ procs[$0] }).max(by: { $0.bytes < $1.bytes }) else { continue }
            add("orphan-\(p.pid)", .ghost, big.label + (hint(big).map { " · \($0)" } ?? ""),
                "its terminal or agent closed · idle \(dur(i)), running \(dur(p.elapsed))", pids)
        }

        // anything else big that's been sitting idle
        for p in mine where !claimed.contains(p.pid) && !shells.contains(p.base) && !agentLabels.contains(p.label) && !systemish(p) {
            if let par = procs[p.ppid], par.label == p.label { continue }
            let pids = tree(p.pid).filter { !claimed.contains($0) }
            let b = treeBytes(pids), i = treeIdle(pids)
            guard b >= 500 * 1_048_576, i >= mins(30) else { continue }
            add("idle-\(p.pid)", .idle, p.label + (hint(p).map { " · \($0)" } ?? ""), "using \(size(b)), no activity for \(dur(i))", pids)
        }

        // other people's apps only show up as their total (see owners), never by name
        var byApp: [String: [Proc]] = [:]
        for p in procs.values where p.uid == me || p.uid < 501 { byApp[p.label, default: []].append(p) }
        let all = byApp.map { name, ps -> AppUse in
            var parts: [String: (count: Int, bytes: Double)] = [:]
            for p in ps { let r = role(p); parts[r, default: (0, 0)].count += 1; parts[r]!.bytes += p.bytes }
            return AppUse(name: name, gb: ps.reduce(0) { $0 + $1.bytes } / 1_073_741_824, pids: ps.map(\.pid),
                          cpu: ps.reduce(0) { $0 + $1.pcpu }, quiet: treeIdle(ps.map(\.pid)),
                          parts: parts.map { ($0.key, $0.value.count, $0.value.bytes) }.sorted { $0.bytes > $1.bytes })
        }
        var apps = Array(all.filter { $0.gb >= 0.2 }.sorted { $0.gb > $1.gb }.prefix(6))
        let who = owners ? Engine.owners(&apps) : nil
        return Scan(apps: apps, owners: who, findings: found.sorted { $0.bytes > $1.bytes })
    }

    // ps can't see other people's processes, so a second login (or macOS itself) looks like missing RAM.
    // /usr/bin/top is allowed to read every process, so ask it for everyone's footprint + compressed share.
    // ~1s of system time, so only when the Mac tab opens
    static func owners(_ apps: inout [AppUse]) -> [Owner]? {
        let r = run("/usr/bin/top", ["-l", "1", "-n", "10000", "-stats", "pid,uid,mem,cmprs"])
        guard r.status == 0 else { return nil }
        let me = Int(getuid())
        var byUid: [Int: Double] = [:], packed: [Int: Double] = [:]
        for line in r.out.split(separator: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count == 4, let pid = Int(f[0]), let uid = Int(f[1]) else { continue }
            byUid[uid, default: 0] += topSize(f[2]); packed[pid] = topSize(f[3])
        }
        guard !byUid.isEmpty else { return nil }
        for i in apps.indices { apps[i].packed = apps[i].pids.compactMap { packed[$0] }.reduce(0, +) }
        var people: [String: Double] = [:], system = 0.0
        for (uid, b) in byUid {
            if uid == me { continue }
            if uid >= 501, let pw = getpwuid(uid_t(uid)) { people[String(cString: pw.pointee.pw_name), default: 0] += b }
            else { system += b }
        }
        return [Owner(name: "you", bytes: byUid[me] ?? 0)]
            + people.sorted { $0.value > $1.value }.map { Owner(name: $0.key, bytes: $0.value) }
            + [Owner(name: "macOS", bytes: system)]
    }
}

func apply(_ f: Finding, wait: Bool) {
    switch f.fix {
    case .kill(let pids):
        let ok = pids.filter { $0 > 1 && pid_t($0) != getpid() }
        for p in ok.reversed() { kill(pid_t(p), SIGTERM) }
        let finish = { for p in ok where kill(pid_t(p), 0) == 0 { kill(pid_t(p), SIGKILL) } }
        if wait { Thread.sleep(forTimeInterval: 4); finish() }
        else { DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: finish) }
    case .quit(let app): run("/usr/bin/osascript", ["-e", "quit app \"\(app)\""])
    case .run(let path, let args): run(path, args)
    }
}

func fixText(_ apps: [AppUse]) -> String {
    let names = Set(apps.map(\.name))
    if names.contains("Xcode") && names.contains("Android Studio") { return "Xcode + Android Studio are both open → quit one" }
    if names.contains("Android emulator") { return "Emulator is running → close it, test on your phone" }
    if names.contains("iOS Simulator") { return "iOS Simulator is open → quit it if you're on your phone" }
    if let top = apps.first { return "\(top.name) is the biggest → close what you're done with" }
    return "close what you're done with"
}
