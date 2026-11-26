// Adapted from baa by Selvi Arora (MIT). See NOTICE.
// RAM, leftovers and disk junk. Polls on baa's cadence: free RAM every 10s, a leftover scan every
// 30s, disk junk every 6h (and when the Mac tab opens, if the last scan is over 15 minutes old).
import AppKit

final class Monitor: ObservableObject {
    static let shared = Monitor()
    @Published var free = Mem.freePct
    @Published var level = 1
    @Published var swap = 0.0
    @Published var scan = Scan()
    @Published var mem = Mem.Breakdown()
    @Published var perMin = 0.0
    @Published var minutesToRed: Double?
    @Published var toast: String?
    @Published var busy: Set<String> = []
    @Published var spark: [Int] = []          // free %, every 10s, last 30 min
    @Published var freedCount = 0             // bumps on every free, drives the header pulse
    @Published var warnAt = Limits.warn { didSet { Limits.warn = warnAt; if critAt >= warnAt { critAt = warnAt - 1 } } }
    @Published var critAt = Limits.crit { didSet { Limits.crit = critAt } }
    @Published var trendOn = Limits.trend { didSet { Limits.trend = trendOn; if !trendOn { minutesToRed = nil } } }
    @Published var muted = Env.defaults.bool(forKey: "muted") {
        didSet { Env.defaults.set(muted, forKey: "muted") }
    }
    @Published var junk: [Junk] = []
    @Published var diskFree = 0.0
    var diskTotal = 0.0

    var health: Health { .of(free: free, level: level, minutesToRed: minutesToRed) }

    private let engine = Engine()
    private let q = DispatchQueue(label: "cmd.scan")
    private let dq = DispatchQueue(label: "cmd.disk")
    private var history: [(at: Date, free: Int)] = []
    private var lastPing: (at: Date, critical: Bool)?
    private var trendPing: Date?
    // remembered across restarts so a relaunch doesn't re-ping the same leftover
    private var ghostPings: [String: Date] = ((Env.defaults.dictionary(forKey: "ghostPings") as? [String: Double]) ?? [:])
        .mapValues { Date(timeIntervalSince1970: $0) }
    private var lastDiskScan: Date?
    private var diskPing: Date?
    private var chime: NSSound?

    func start() {
        if Env.demo { loadDemo(); return }
        Notifier.shared.setup()
        tick(); rescan()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in self.tick() }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in self.rescan() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.diskScan() }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in self.diskScan() }
    }

    private func tick() {
        free = Mem.freePct; level = Mem.level; swap = Mem.swapGB; mem = Mem.breakdown
        let now = Date()
        history.append((now, free))
        spark.append(free); if spark.count > 180 { spark.removeFirst(spark.count - 180) }
        history.removeAll { now.timeIntervalSince($0.at) > 180 }
        (perMin, minutesToRed) = Monitor.trend(history, free: free, warn: Limits.warn, on: Limits.trend)
        pressurePing()
    }

    // least-squares slope, in % free per minute
    static func slope(_ pts: ArraySlice<(at: Date, free: Int)>) -> Double {
        guard let t0 = pts.first?.at else { return 0 }
        let xs = pts.map { $0.at.timeIntervalSince(t0) / 60 }, ys = pts.map { Double($0.free) }
        let n = Double(xs.count), mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let den = zip(xs, xs).map { ($0 - mx) * ($1 - mx) }.reduce(0, +)
        return den > 0 ? zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +) / den : 0
    }

    // "dropping fast" only when it's a real slide, not one app launch that already leveled off:
    // falling over the last 3 min AND still falling in the last minute, and already within 10 points of yellow
    static func trend(_ h: [(at: Date, free: Int)], free: Int, warn: Int, on: Bool) -> (Double, Double?) {
        guard h.count >= 8 else { return (0, nil) }
        let per = slope(h[...]), recent = slope(h.suffix(6)), gap = free - warn
        return (per, (on && per < -1.5 && recent < -1.5 && gap > 0 && gap <= 10) ? Double(gap) / -per : nil)
    }

    // full: also ask top who owns the rest of the RAM (about 1s of system time, so only when the Mac tab opens).
    // the 30s background scan skips that and keeps the last answer
    func rescan(full: Bool = false, then: (() -> Void)? = nil) {
        guard !Env.demo else { return }
        q.async {
            var s = self.engine.scan(owners: full)
            DispatchQueue.main.async {
                if !full {
                    s.owners = self.scan.owners
                    let old = Dictionary(self.scan.apps.map { ($0.name, $0.packed) }, uniquingKeysWith: { a, _ in a })
                    for i in s.apps.indices { s.apps[i].packed = old[s.apps[i].name] ?? nil }
                }
                self.scan = s; self.ghostPing(); then?()
            }
        }
    }

    private var subtitle: String {
        scan.apps.prefix(3).map { "\($0.name) \(String(format: "%.1f", $0.gb)) GB" }.joined(separator: "  ·  ")
    }

    private func pingWithBestFix(_ title: String) {
        if let f = scan.findings.first {
            Notifier.shared.post(title, subtitle, "\(f.title): \(f.detail)", button: f.freeLabel) { self.freeUp(f.id) }
        } else {
            Notifier.shared.post(title, subtitle, fixText(scan.apps))
        }
    }

    private func pressurePing() {
        let now = Date(), h = health
        if h == .tight || h == .critical {
            // one ping per 30 min, unless it just got worse (yellow -> red)
            if let l = lastPing, h != .critical || l.critical, now.timeIntervalSince(l.at) < 1800 { return }
            lastPing = (now, h == .critical)
            pingWithBestFix("\(h.dot) RAM \(h.word) · \(free)% free")
        } else {
            lastPing = nil
            if h == .falling, let m = minutesToRed, trendPing.map({ now.timeIntervalSince($0) > 1800 }) ?? true {
                trendPing = now
                pingWithBestFix("🟠 RAM dropping fast · red in ~\(max(1, Int(m.rounded()))) min")
            }
        }
    }

    // big leftovers get one heads-up every 6h, even when RAM is fine
    private func ghostPing() {
        let now = Date()
        guard let f = scan.findings.first(where: { ($0.kind == .hot || ($0.kind != .idle && $0.bytes >= 1_073_741_824)) &&
                                                   ghostPings[$0.id].map { now.timeIntervalSince($0) > 6 * 3600 } ?? true }) else { return }
        ghostPings[f.id] = now
        UserDefaults.standard.set(ghostPings.mapValues(\.timeIntervalSince1970), forKey: "ghostPings")
        Notifier.shared.post(f.kind == .hot ? "🔥 stuck burning CPU" : "👻 \(size(f.bytes)) still running", f.title, f.detail, button: f.freeLabel) { self.freeUp(f.id) }
    }

    // a soft chime plus the header pulse when something was actually freed
    private func freed() {
        freedCount += 1
        guard !muted else { return }
        chime = NSSound(named: "Glass")
        chime?.volume = 0.35
        chime?.play()
    }

    func freeUp(_ id: String) {
        guard !Env.demo else { flash("Demo mode: nothing was freed"); return }
        busy.insert(id)
        q.async {
            guard let f = self.engine.scan().findings.first(where: { $0.id == id }) else {
                DispatchQueue.main.async { self.busy.remove(id); self.rescan() }
                return
            }
            apply(f, wait: true)
            DispatchQueue.main.async {
                self.busy.remove(id)
                self.freed()
                self.flash("Freed \(size(f.bytes)) · \(f.title)")
                self.tick(); self.rescan()
            }
        }
    }

    func freeAll() {
        guard !Env.demo else { flash("Demo mode: nothing was freed"); return }
        let ids = scan.findings.map(\.id), total = scan.freeable
        busy.formUnion(ids)
        q.async {
            let fs = self.engine.scan().findings.filter { ids.contains($0.id) }
            fs.forEach { apply($0, wait: false) }
            Thread.sleep(forTimeInterval: 4.5)
            DispatchQueue.main.async {
                self.busy.subtract(ids)
                if !ids.isEmpty { self.freed() }
                self.flash("Freed \(size(total))")
                self.tick(); self.rescan()
            }
        }
    }

    func diskScan(ifOlderThan age: TimeInterval = 0) {
        guard !Env.demo else { return }
        if let l = lastDiskScan, Date().timeIntervalSince(l) < age { return }
        lastDiskScan = Date()
        dq.async {
            let j = Disk.scan(), free = Disk.free, total = Disk.total
            DispatchQueue.main.async {
                self.junk = j; self.diskFree = free; self.diskTotal = total
                self.diskLowPing()
            }
        }
    }

    // under 10% or 15 GB free -> one ping every 12h, with the biggest safe cleanup on it
    private func diskLowPing() {
        let now = Date()
        guard diskTotal > 0, diskFree < max(diskTotal * 0.1, 15e9),
              diskPing.map({ now.timeIntervalSince($0) > 12 * 3600 }) ?? true else { return }
        diskPing = now
        let title = "💾 Disk almost full · \(size(diskFree)) left"
        if let j = junk.first(where: { $0.blockedBy == nil && $0.pingable }) {
            Notifier.shared.post(title, "\(size(junk.reduce(0) { $0 + $1.bytes })) of dev junk you can clear", "\(j.title): \(j.detail)",
                                 button: "Clear \(size(j.bytes))") { self.clean(j.id) }
        } else {
            Notifier.shared.post(title, "", "open cmd's Mac tab to see what you can clear")
        }
    }

    func clean(_ id: String) {
        guard !Env.demo else { flash("Demo mode: nothing was cleared"); return }
        busy.insert(id)
        dq.async {
            guard let j = Disk.scan().first(where: { $0.id == id }), j.blockedBy == nil else {
                DispatchQueue.main.async { self.busy.remove(id); self.diskScan() }
                return
            }
            Disk.clean(j)
            DispatchQueue.main.async {
                self.busy.remove(id)
                self.freed()
                self.flash(j.trashes ? "Moved \(size(j.bytes)) to the Trash · empty it to get the space back"
                                     : "Cleared \(size(j.bytes)) · \(j.title)")
                self.diskScan()
            }
        }
    }

    private func flash(_ s: String) {
        toast = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { if self.toast == s { self.toast = nil } }
    }
}
