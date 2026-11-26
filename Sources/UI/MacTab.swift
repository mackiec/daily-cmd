// Layout and behaviour adapted from baa's memory and disk tabs by Selvi Arora (MIT). See NOTICE.
import SwiftUI
import AppKit

struct MacTab: View {
    @ObservedObject var mon: Monitor
    @ObservedObject var ui: PanelState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                gauge
                if !mon.scan.findings.isEmpty { leftovers }
                whereItWent
                usingTheMost
                disk
                settings
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }

    private var status: (title: String, line: String) {
        let none = mon.scan.findings.isEmpty
        switch mon.health {
        case .ok: return ("room to breathe", none ? "nothing to free right now" : "no need to free anything yet")
        case .falling: return ("dropping fast", "you'll hit red in ~\(max(1, Int((mon.minutesToRed ?? 1).rounded()))) min")
        case .tight: return ("getting tight", none ? "close an app you're done with" : "free the leftovers to make room")
        case .critical: return ("about to freeze", none ? "close something big now" : "free them now")
        }
    }

    // MARK: RAM

    private var gauge: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(mon.free)").font(.system(size: 44, weight: .light)).monospacedDigit()
                Text("% RAM free").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(mon.health.color).frame(width: 6, height: 6)
                        Text(status.title).font(.system(size: 12.5))
                    }
                    Text(status.line).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            Spark(free: mon.spark, minutesToRed: mon.minutesToRed, color: mon.health.color).frame(height: 30)
            HStack {
                Text("last 30 min").monoLabel(8.5)
                Spacer()
                if mon.swap >= 0.1 { Text("swap \(String(format: "%.1f", mon.swap)) GB").font(.system(size: 10)) }
            }
            .foregroundStyle(Theme.muted)
        }
    }

    private var groups: [(who: String, items: [Finding])] {
        Dictionary(grouping: mon.scan.findings, by: \.culprit)
            .map { ($0.key, $0.value) }
            .sorted { $0.1.reduce(0) { $0 + $1.bytes } > $1.1.reduce(0) { $0 + $1.bytes } }
    }

    @ViewBuilder private var leftovers: some View {
        let n = mon.scan.findings.count
        if mon.health == .ok && !ui.showLeftovers {
            // healthy: leftovers stay out of the way until asked for
            Button { withAnimation(.easeOut(duration: 0.2)) { ui.showLeftovers = true } } label: {
                HStack {
                    Text("\(n) leftover\(n == 1 ? "" : "s") still running")
                    Spacer()
                    Text(size(mon.scan.freeable)).monospacedDigit().foregroundStyle(Theme.muted)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                .font(.system(size: 12.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(size(mon.scan.freeable)).font(.system(size: 22, weight: .light)).monospacedDigit()
                        Text("of leftovers you can free").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button(mon.busy.isEmpty ? "Free all" : "Freeing…") { mon.freeAll() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(!mon.busy.isEmpty)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sakura.opacity(0.28)))

                ForEach(groups, id: \.who) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        let total = size(g.items.reduce(0) { $0 + $1.bytes })
                        Caption(title: g.items[0].detail.contains("started by ") ? "\(g.who) left these" : g.who, trailing: total)
                        ForEach(g.items) { f in
                            HStack(alignment: .center, spacing: 10) {
                                Text(f.emoji).font(.system(size: 13))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.system(size: 12.5)).lineLimit(1)
                                    Text(f.detail).font(.system(size: 11)).foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Button(mon.busy.contains(f.id) ? "Freeing…" : f.freeLabel) { mon.freeUp(f.id) }
                                    .buttonStyle(PillButtonStyle())
                                    .disabled(mon.busy.contains(f.id))
                                    .fixedSize().layoutPriority(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // the bar that makes the math add up: what's in the RAM, and who it belongs to
    @ViewBuilder private var whereItWent: some View {
        let b = mon.mem
        if b.total > 0 {
            let slices: [(String, Double, Color)] = [
                ("apps", b.apps, Theme.fujiDeep), ("squeezed", b.compressed, Theme.fuji), ("macOS", b.wired, Theme.minato),
                ("cache", b.cached, Theme.shiro), ("free", b.free, Theme.usukumo.opacity(0.45)),
            ]
            VStack(alignment: .leading, spacing: 9) {
                Caption(title: "\(Int((b.total / 1_073_741_824).rounded())) GB of RAM")
                GeometryReader { g in
                    HStack(spacing: 1) {
                        ForEach(slices, id: \.0) { s in Rectangle().fill(s.2).frame(width: max(0, g.size.width * s.1 / b.total - 1)) }
                    }
                }
                .frame(height: 7).clipShape(Capsule())
                HStack(spacing: 8) {
                    ForEach(slices, id: \.0) { s in
                        HStack(spacing: 3) {
                            Circle().fill(s.2).frame(width: 6, height: 6)
                            Text("\(s.0) \(String(format: "%.1f", s.1 / 1_073_741_824))").font(.system(size: 10)).monospacedDigit()
                        }
                        .fixedSize()
                    }
                }
                .foregroundStyle(Theme.muted)
                if let o = mon.scan.owners, o.count > 2 {   // only worth showing when someone else is logged in
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(o, id: \.name) { w in
                            HStack {
                                Text(w.name).font(.system(size: 12))
                                Spacer()
                                Text(size(w.bytes)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var usingTheMost: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption(title: "Using the most")
            let top = mon.scan.apps.first?.gb ?? 1
            ForEach(mon.scan.apps.prefix(5), id: \.name) { a in AppRow(a: a, top: top, ui: ui) }
        }
    }

    // MARK: disk

    private var junkTotal: Double { mon.junk.reduce(0) { $0 + $1.bytes } }

    private var disk: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption(title: "Disk", trailing: mon.diskTotal > 0 ? "\(size(mon.diskFree)) free of \(size(mon.diskTotal))" : "checking…")
            if mon.diskTotal > 0 {
                let low = mon.diskFree < max(mon.diskTotal * 0.1, 15e9)
                Bar(fraction: 1 - mon.diskFree / mon.diskTotal, color: low ? Theme.akabeni : Theme.fuji).frame(height: 5)
            }
            if mon.junk.isEmpty {
                Text(mon.diskTotal > 0 ? "No dev junk to clean up." : "Looking for dev junk…")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                Caption(title: "Dev junk", trailing: size(junkTotal)).padding(.top, 4)
                ForEach(mon.junk.prefix(6)) { j in
                    HStack(alignment: .center, spacing: 10) {
                        Text(j.icon).font(.system(size: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(j.title).font(.system(size: 12.5)).lineLimit(1)
                            Text(j.blockedBy ?? j.detail).font(.system(size: 11))
                                .foregroundStyle(j.blockedBy == nil ? Theme.muted : Theme.persimmon)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(mon.busy.contains(j.id) ? "Clearing…" : "\(j.trashes ? "Trash" : "Clear") \(size(j.bytes))") { mon.clean(j.id) }
                            .buttonStyle(PillButtonStyle())
                            .disabled(mon.busy.contains(j.id) || j.blockedBy != nil)
                            .fixedSize().layoutPriority(1)
                    }
                }
                if mon.junk.count > 6 {
                    Text("+\(mon.junk.count - 6) more").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: settings

    private func limitRow(_ dot: String, _ label: String, _ v: Binding<Int>, _ r: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Text("\(dot) \(label)").font(.system(size: 12))
            Spacer()
            Text("\(v.wrappedValue)% free").font(.system(size: 12)).monospacedDigit()
            Stepper("", value: v, in: r).labelsHidden().controlSize(.small)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button { mon.muted.toggle() } label: {
                    Label(mon.muted ? "Sound off" : "Sound on", systemImage: mon.muted ? "speaker.slash" : "speaker.wave.2")
                }
                Button { withAnimation(.easeOut(duration: 0.2)) { ui.showLimits.toggle() } } label: {
                    Label("Warning levels", systemImage: "slider.horizontal.3")
                }
                Spacer()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)

            if ui.showLimits {
                VStack(alignment: .leading, spacing: 8) {
                    Caption(title: "Warn me when")
                    limitRow("🟡", "getting tight", $mon.warnAt, 5...50)
                    limitRow("🔴", "critical", $mon.critAt, 2...max(2, mon.warnAt - 1))
                    HStack(spacing: 8) {
                        Text("🟠 heads-up when it's dropping fast").font(.system(size: 12))
                        Spacer()
                        Toggle("", isOn: $mon.trendOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }
                    Text("Goes red anyway if macOS says memory is critical.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.6)))
            }
        }
    }
}

// one app in "using the most". tap to see what it's running
struct AppRow: View {
    let a: AppUse, top: Double
    @ObservedObject var ui: PanelState
    private var isOpen: Bool { ui.openApp == a.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Group {
                    if let i = appIcon(a.name) { Image(nsImage: i).resizable() }
                    else { Image(systemName: "gearshape").resizable().padding(2).foregroundStyle(Theme.muted) }
                }
                .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.name).font(.system(size: 12)).lineLimit(1)
                    Text(a.doing).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .frame(width: 120, alignment: .leading)
                Bar(fraction: a.gb / top, color: Theme.fuji).frame(height: 4)
                Text(String(format: "%.1f GB", a.gb)).font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(Theme.muted).frame(width: 44, alignment: .trailing)
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(a.parts.prefix(5), id: \.role) { p in
                        HStack {
                            Text(p.count > 1 ? "\(p.count) × \(p.role)" : p.role).font(.system(size: 11))
                            Spacer()
                            Text(size(p.bytes)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                    if let packed = a.packed, packed > 0 {
                        HStack {
                            Text("squeezed").font(.system(size: 11)).foregroundStyle(Theme.fujiDeep)
                            Spacer()
                            Text(size(packed)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .rowHover("app:\(a.name)", ui)
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { ui.openApp = isOpen ? nil : a.name } }
    }
}
