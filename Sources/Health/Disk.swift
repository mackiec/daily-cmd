// Adapted from baa by Selvi Arora (MIT). See NOTICE.
// Changes from baa: no "old installers in Downloads" check, and the node_modules search skips every
// folder macOS guards with a privacy prompt (Desktop, Documents, Downloads, Pictures, Music, Movies).
// Documents and Downloads hold private files and are off-limits on this Mac; entering the others would
// make macOS ask "cmd would like to access…", and the scan would wait on that prompt.
// baa's "find more space" (big-folder sizes + asking AI) is left out.
import AppKit

// only known, rebuildable dev junk. never your files, Xcode archives, or emulator images
enum JunkAction { case trash([URL]), run([(String, [String])]) }

struct Junk: Identifiable {
    let id: String, icon: String, title: String, detail: String, bytes: Double, action: JunkAction
    var blockedBy: String? = nil
    var pingable = true   // cheap to rebuild, so the disk-full ping may offer it as a one-click clear
    var trashes: Bool { if case .trash = action { return true }; return false }
}

enum Disk {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static func h(_ p: String) -> URL { home.appendingPathComponent(p) }
    static let protected = ["Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies"].map(h)

    static var free: Double {
        let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Double(v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
    static var total: Double {
        let v = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return Double(v?.volumeTotalCapacity ?? 0)
    }

    static func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    static func du(_ urls: [URL]) -> Double {
        let paths = urls.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return 0 }
        return run("/usr/bin/du", ["-sk"] + paths).out.split(separator: "\n")
            .compactMap { Double($0.split(separator: "\t").first ?? "") }.reduce(0, +) * 1024
    }

    static func modified(_ u: URL) -> Date {
        (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    static func children(_ u: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles])) ?? []
    }

    // "2.3GB (45%)" -> bytes
    static func parseSize(_ s: Substring) -> Double {
        let t = s.split(separator: " ").first.map(String.init) ?? ""
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("B", 1)]
        for (u, m) in units where t.hasSuffix(u) { return (Double(t.dropLast(u.count)) ?? 0) * m }
        return 0
    }

    static func scan() -> [Junk] {
        var out: [Junk] = []
        let xcodeOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode").isEmpty
        let quitXcode = xcodeOpen ? "quit Xcode first" : nil
        func add(_ id: String, _ icon: String, _ title: String, _ detail: String, _ urls: [URL], blocked: String? = nil) {
            let urls = urls.filter(exists)
            let b = du(urls)
            guard b >= 200 * 1_048_576 else { return }
            out.append(Junk(id: id, icon: icon, title: title, detail: detail, bytes: b, action: .trash(urls), blockedBy: blocked))
        }

        add("xcode-build", "🔨", "Xcode build files", "DerivedData · rebuilds on your next build",
            [h("Library/Developer/Xcode/DerivedData")], blocked: quitXcode)

        // device support: keep the newest version for each device model
        var old: [URL] = []
        for os in ["iOS", "watchOS", "tvOS", "visionOS"] {
            let byModel = Dictionary(grouping: children(h("Library/Developer/Xcode/\(os) DeviceSupport"))) {
                $0.lastPathComponent.split(separator: " ").first.map(String.init) ?? ""
            }
            for (_, dirs) in byModel { old += dirs.sorted { modified($0) > modified($1) }.dropFirst() }
        }
        add("device-support", "📲", "Old iOS device support", "versions your phone isn't on anymore · Xcode re-adds them if needed",
            old, blocked: quitXcode)

        // simulator runtimes: keep the newest per platform
        if let data = run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"]).out.data(using: .utf8),
           let all = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            let rts = all.map { (id: $0.key, platform: $0.value["platformIdentifier"] as? String ?? "",
                                 version: $0.value["version"] as? String ?? "", size: ($0.value["sizeBytes"] as? NSNumber)?.doubleValue ?? 0) }
            var stale: [(id: String, platform: String, version: String, size: Double)] = []
            for (_, group) in Dictionary(grouping: rts, by: { $0.platform }) {
                stale += group.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }.dropFirst()
            }
            let bytes = stale.reduce(0) { $0 + $1.size }
            if bytes >= 200 * 1_048_576 {
                out.append(Junk(id: "sim-runtimes", icon: "📱", title: "Old simulator versions",
                                detail: stale.map { "iOS \($0.version)" }.sorted().joined(separator: ", ") + " · keeps your newest one",
                                bytes: bytes, action: .run(stale.map { ("/usr/bin/xcrun", ["simctl", "runtime", "delete", $0.id]) }),
                                blockedBy: quitXcode))
            }
        }
        add("sim-caches", "📱", "Simulator caches", "rebuild automatically", [h("Library/Developer/CoreSimulator/Caches")])

        add("gradle", "🐘", "Gradle caches", "re-download on your next Android build",
            [h(".gradle/caches"), h(".gradle/daemon"), h(".gradle/wrapper/dists")])
        add("js", "📦", "npm / yarn / bun / pnpm caches", "re-download next time you install",
            [h(".npm/_cacache"), h("Library/Caches/Yarn"), h(".bun/install/cache"), h("Library/pnpm/store")])
        add("python", "🐍", "pip / uv caches", "re-download next time you install", [h("Library/Caches/pip"), h(".cache/uv")])
        add("brew", "🍺", "Homebrew / CocoaPods / SwiftPM caches", "old downloads",
            [h("Library/Caches/Homebrew"), h("Library/Caches/CocoaPods"), h("Library/Caches/org.swift.swiftpm")])
        add("test-browsers", "🧪", "Test browsers (Playwright / Puppeteer)", "reinstall with npx playwright install",
            [h("Library/Caches/ms-playwright"), h(".cache/puppeteer")])
        // models: only ones you haven't opened in 2 weeks. if one comes back after a clean, an app needs it, so leave it alone
        let cleaned = Set(Env.defaults.stringArray(forKey: "cleanedModels") ?? [])
        let models = children(h(".cache/huggingface/hub")).filter { m in
            m.lastPathComponent.hasPrefix("models--") && !cleaned.contains(m.lastPathComponent) &&
            run("/usr/bin/find", [m.path, "-type", "f", "-atime", "-14", "-print", "-quit"]).out.isEmpty
        }
        let before = out.count
        add("hf", "🤗", "Unused Hugging Face models",
            "\(models.count) not opened in 2+ weeks · " + models.prefix(2).map { $0.lastPathComponent.components(separatedBy: "--").last ?? "" }.joined(separator: ", "),
            models)
        if out.count > before { out[out.count - 1].pingable = false }

        // node_modules in projects nobody has touched in a month. never looks inside the off-limits folders
        let monthAgo = Date().addingTimeInterval(-30 * 86400)
        var prune: [String] = ["(", "-path", h("Library").path]
        for u in protected { prune += ["-o", "-path", u.path] }
        prune += ["-o", "-name", ".*", ")", "-prune"]
        let found = run("/usr/bin/find", [home.path, "-maxdepth", "5"] + prune + ["-o", "-type", "d", "-name", "node_modules", "-print", "-prune"]).out
        let stale = found.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }.filter { nm in
            let project = nm.deletingLastPathComponent()
            let last = ([project] + children(project).filter { $0.lastPathComponent != "node_modules" }).map(modified).max() ?? .distantPast
            return last < monthAgo
        }
        add("node-modules", "📦", "Old node_modules", "\(stale.count) project\(stale.count == 1 ? "" : "s") untouched for 30+ days · npm install brings them back", stale)

        // docker: whatever it says is reclaimable
        if let cli = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let r = run(cli, ["system", "df", "--format", "{{.Reclaimable}}"])
            let bytes = r.status == 0 ? r.out.split(separator: "\n").map(parseSize).reduce(0, +) : 0
            if bytes >= 200 * 1_048_576 {
                out.append(Junk(id: "docker", icon: "🐳", title: "Docker leftovers", detail: "stopped containers, unused images, build cache",
                                bytes: bytes, action: .run([(cli, ["system", "prune", "-f"])])))
            }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    static func clean(_ j: Junk) {
        switch j.action {
        case .trash(let urls):
            for u in urls { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
            if j.id == "hf" {
                let names = (Env.defaults.stringArray(forKey: "cleanedModels") ?? []) + urls.map(\.lastPathComponent)
                Env.defaults.set(Array(Set(names)), forKey: "cleanedModels")
            }
        case .run(let cmds): for (path, args) in cmds { run(path, args) }
        }
    }
}
