import Foundation

// Made-up Mac health for demo mode (CMD_DEMO=1), used for the README screenshots. Nothing here comes from
// this Mac, the findings point at no processes, and Monitor refuses to free or clean anything in demo mode.
extension Monitor {
    func loadDemo() {
        let gb = 1_073_741_824.0
        free = 64
        level = 1
        swap = 0.4
        spark = (0..<180).map { 63 + Int((3 * sin(Double($0) / 14)).rounded()) }
        mem = Mem.Breakdown(total: 8 * gb, apps: 2.2 * gb, wired: 1.5 * gb, compressed: 1.1 * gb, cached: 1.4 * gb, free: 1.8 * gb)
        scan = Scan(
            apps: [
                AppUse(name: "Safari", gb: 1.4, cpu: 3, quiet: 0, parts: [("tab", 9, 0.9 * gb), ("main app", 1, 0.3 * gb), ("graphics", 1, 0.2 * gb)]),
                AppUse(name: "Figma", gb: 0.9, cpu: 1, quiet: 900),
                AppUse(name: "omp", gb: 0.5, cpu: 0, quiet: 1200),
                AppUse(name: "Spotify", gb: 0.3, cpu: 1, quiet: 0),
            ],
            owners: nil,
            findings: [
                Finding(id: "demo-vite", kind: .agent, title: "Dev server :5173 · vite",
                        detail: "started by omp (garden-journal) · idle 2h", bytes: 412 * 1_048_576, fix: .kill([])),
                Finding(id: "demo-python", kind: .ghost, title: "Python · train.py",
                        detail: "its terminal or agent closed · idle 45m, running 3h", bytes: 310 * 1_048_576, fix: .kill([])),
            ])
        junk = [
            Junk(id: "demo-xcode", icon: "🔨", title: "Xcode build files", detail: "DerivedData · rebuilds on your next build",
                 bytes: 3.4 * gb, action: .trash([])),
            Junk(id: "demo-js", icon: "📦", title: "npm / yarn / bun / pnpm caches", detail: "re-download next time you install",
                 bytes: 1.2 * gb, action: .trash([])),
        ]
        diskFree = 96 * gb
        diskTotal = 245 * gb
    }
}
