import SwiftUI
import AppKit

extension View {
    // the text field look used at the top of every tab
    func inputField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.shiro))
    }

    // soft highlight under a row while the pointer is over it
    func rowHover(_ id: String, _ ui: PanelState) -> some View {
        background(RoundedRectangle(cornerRadius: 8).fill(ui.hovered == id ? Theme.usukumo.opacity(0.55) : .clear))
            .onHover { if $0 { ui.hovered = id } else if ui.hovered == id { ui.hovered = nil } }
    }
}

// capsule buttons: prominent ones carry the wisteria → sakura gradient
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent ? 12.5 : 11, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, prominent ? 14 : 10)
            .padding(.vertical, prominent ? 7 : 4)
            .foregroundStyle(Theme.sabi)
            .background(Capsule().fill(prominent
                ? AnyShapeStyle(LinearGradient(colors: [Theme.fuji.opacity(0.55), Theme.sakura], startPoint: .leading, endPoint: .trailing))
                : AnyShapeStyle(Color.white.opacity(0.8))))
            .overlay(Capsule().stroke(prominent ? Color.clear : Theme.shiro))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}

// "INBOX [3]": a group or section caption
struct Caption: View {
    let title: String
    var count: Int? = nil
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(count.map { "\(title) [\($0)]" } ?? title).monoLabel(9.5)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 10.5)).monospacedDigit() }
        }
        .foregroundStyle(Theme.muted)
    }
}

// where a new item goes: the Inbox or a project. Remembers the last choice per tab.
struct ScopeChip: View {
    @Binding var selection: String   // a Scope id
    let scopes: [Scope]
    var current: Scope { scopes.first { $0.id == selection } ?? .inbox }
    var body: some View {
        Menu {
            ForEach(scopes) { s in
                Button(s.name) { selection = s.id }
                if s.project == nil { Divider() }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.name).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.fujiDeep)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.fuji.opacity(0.16)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Where new items go. Or type @project in the field.")
    }
}

// the "→ garden-journal" line under a field while you type an @project token
struct TokenHint: View {
    let input: String
    let projects: [Project]
    var body: some View {
        let t = ScopeToken(input, projects: projects)
        if let s = t.scope {
            Text("→ \(s.name)").font(.system(size: 11)).foregroundStyle(Theme.fujiDeep)
        } else if let u = t.unknown {
            Text("No project matches “\(u)”").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }
}

// Adapted from baa by Selvi Arora (MIT). See NOTICE.
struct Bar: View {
    let fraction: Double, color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.shiro.opacity(0.6))
                Capsule().fill(color.gradient).frame(width: max(4, g.size.width * min(1, fraction)))
            }
        }
    }
}

// Adapted from baa by Selvi Arora (MIT). See NOTICE.
// last 30 min of RAM use, with a dotted line toward red when it's falling
struct Spark: View {
    let free: [Int], minutesToRed: Double?, color: Color
    var body: some View {
        Canvas { c, sz in
            let used = free.map { Double(100 - $0) }
            guard used.count > 1 else { return }
            let lo = max(0, (used.min() ?? 0) - 10), hi = 100.0
            let span = Double(max(used.count, 30)), ahead = minutesToRed.map { min(60, $0 * 6) } ?? 0   // samples are 10s apart
            let w = sz.width, h = sz.height
            let x = { (i: Double) in w * i / (span + ahead) }
            let y = { (v: Double) in h - h * (v - lo) / (hi - lo) }
            let start = span - Double(used.count)   // stretches to whatever's been collected
            var red = Path(); red.move(to: .init(x: 0, y: y(85))); red.addLine(to: .init(x: w, y: y(85)))
            c.stroke(red, with: .color(Theme.akabeni.opacity(0.35)), style: .init(lineWidth: 1, dash: [2, 3]))
            var line = Path()
            for (i, v) in used.enumerated() {
                let p = CGPoint(x: x(start + Double(i)), y: y(v))
                i == 0 ? line.move(to: p) : line.addLine(to: p)
            }
            var fill = line
            fill.addLine(to: .init(x: x(start + Double(used.count - 1)), y: h)); fill.addLine(to: .init(x: x(start), y: h)); fill.closeSubpath()
            c.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.3), color.opacity(0.02)]), startPoint: .zero, endPoint: .init(x: 0, y: h)))
            c.stroke(line, with: .color(color), style: .init(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            if ahead > 0, let last = used.last {
                var p = Path()
                p.move(to: .init(x: x(span - 1), y: y(last))); p.addLine(to: .init(x: w, y: y(85)))
                c.stroke(p, with: .color(Theme.akabeni), style: .init(lineWidth: 1.4, lineCap: .round, dash: [3, 3]))
            }
        }
    }
}
