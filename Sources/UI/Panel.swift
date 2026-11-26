import SwiftUI
import AppKit

enum Tab: String, CaseIterable { case projects, todo, refs, mac }
enum Field: Hashable { case filter, todo, ref, note }

// View state lives in this object rather than in @State: the macOS 27 SDK turns @State into a
// macro whose plugin only ships with full Xcode, so @State won't compile with the Command Line Tools.
final class PanelState: ObservableObject {
    private static let d = Env.defaults
    @Published var open = false
    @Published var seed = Double.random(in: 0...10_000)
    @Published var pulse = 0.0
    @Published var tab = Tab(rawValue: PanelState.d.string(forKey: "tab") ?? "") ?? .projects { didSet { Self.d.set(tab.rawValue, forKey: "tab") } }
    @Published var hovered: String?
    // Projects
    @Published var filter = ""
    @Published var expanded: Set<String> = []
    // To-do and Refs
    @Published var todoText = ""
    @Published var refText = ""
    @Published var todoScope = PanelState.d.string(forKey: "todoScope") ?? Scope.inbox.id { didSet { Self.d.set(todoScope, forKey: "todoScope") } }
    @Published var refScope = PanelState.d.string(forKey: "refScope") ?? Scope.inbox.id { didSet { Self.d.set(refScope, forKey: "refScope") } }
    @Published var showDone = false
    @Published var editingNote: String?   // RefRow key while its note is being edited
    @Published var noteText = ""
    // Mac
    @Published var showLeftovers = false
    @Published var showLimits = false
    @Published var openApp: String?
    // the settings form, opened from the gear in the footer
    @Published var showSettings = false
}

struct Panel: View {
    @ObservedObject var m: AppModel
    @ObservedObject var mon: Monitor
    @ObservedObject private var prefs = Prefs.shared
    @StateObject private var ui = PanelState()
    @FocusState private var focus: Field?

    var body: some View {
        VStack(spacing: 0) {
            if !prefs.setupDone || ui.showSettings {
                Text(prefs.setupDone ? "Settings" : "Welcome")
                    .monoLabel(10)
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.sabi).frame(height: 1) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 14)
                SetupView(prefs: prefs, firstRun: !prefs.setupDone) {
                    prefs.setupDone = true
                    ui.showSettings = false
                    m.refresh()
                    focusField()
                }
                .frame(height: 430, alignment: .top)
            } else {
                tabBar
                content.frame(height: 430, alignment: .top)
            }
            footer
        }
        .frame(width: 360)
        .background(alignment: .top) { aura }
        .background(Theme.base)
        .foregroundStyle(Theme.sabi)
        .environment(\.colorScheme, .light)
        .background(WindowEvents(onShow: shown, onHide: { ui.open = false }, onKey: focusField))
        .onChange(of: prefs.projectsRoot) { _, _ in m.refresh() }
        .onChange(of: prefs.agent) { _, _ in m.refresh() }
        .onChange(of: ui.tab) { _, t in
            ui.hovered = nil
            focusField()
            if t == .mac { macShown() }
        }
        .onChange(of: mon.freedCount) { _, _ in
            ui.pulse = 1
            withAnimation(.easeOut(duration: 1.6)) { ui.pulse = 0 }
        }
    }

    @ViewBuilder private var content: some View {
        switch ui.tab {
        case .projects: ProjectsTab(m: m, ui: ui, focus: $focus)
        case .todo: TodoTab(m: m, ui: ui, focus: $focus)
        case .refs: RefsTab(m: m, ui: ui, focus: $focus)
        case .mac: MacTab(mon: mon, ui: ui)
        }
    }

    private func shown() {
        ui.seed = .random(in: 0...10_000)
        ui.open = true
        ui.filter = ""
        ui.editingNote = nil
        m.refresh()
        if ui.tab == .mac { macShown() }
    }

    // the Mac tab asks top who owns the rest of the RAM (about 1s of system time), so only when it's shown
    private func macShown() {
        mon.rescan(full: true)
        mon.diskScan(ifOlderThan: 15 * 60)
    }

    private func focusField() {
        let f: Field? = switch ui.tab { case .projects: .filter; case .todo: .todo; case .refs: .ref; case .mac: nil }
        DispatchQueue.main.async { focus = f }
    }

    private func title(_ t: Tab) -> String {
        switch t {
        case .projects: return "Projects [\(m.projects.count)]"
        case .todo: return m.openTodoCount > 0 ? "To-do [\(m.openTodoCount)]" : "To-do"
        case .refs: return m.refCount > 0 ? "Refs [\(m.refCount)]" : "Refs"
        case .mac: return mon.health == .ok ? "Mac" : "Mac \(mon.health.dot)"
        }
    }

    // ⌘1–⌘4 switch tabs (plain digits would land in the text fields)
    private var tabBar: some View {
        HStack(spacing: 14) {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, t in
                Button { ui.tab = t } label: {
                    Text(title(t))
                        .monoLabel(10)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.bottom, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.sabi).frame(height: 1).opacity(ui.tab == t ? 1 : 0) }
                        .foregroundStyle(ui.tab == t ? Theme.sabi : Theme.muted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                .help("⌘\(i + 1)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    // sits behind the tab bar and the first field, fading out into the list. Warms as RAM gets
    // tight, and pulses once when something is freed.
    private var aura: some View {
        Aura(palette: Theme.aura(mon.health), running: ui.open, seed: ui.seed)
            .brightness(0.06 * ui.pulse)
            .saturation(1 + 0.6 * ui.pulse)
            .frame(height: 150)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45),
                                         .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let t = m.toast ?? mon.toast {
                Text(t).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                if mon.health != .ok, mon.scan.freeable > 0, ui.tab != .mac {
                    Button { ui.tab = .mac } label: { Text("\(size(mon.scan.freeable)) of leftovers → Mac").font(.system(size: 11)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(mon.health.color)
                }
                Spacer()
                Text("\(mon.free)% free").font(.system(size: 11)).monospacedDigit()
            }
            if prefs.setupDone {
                Button { withAnimation(.easeOut(duration: 0.2)) { ui.showSettings.toggle() } } label: {
                    Image(systemName: "gearshape").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ui.showSettings ? Theme.sabi : Theme.muted)
                .help("Settings")
            }
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power").font(.system(size: 11)) }
                .buttonStyle(.plain).help("Quit cmd")
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// Tells the panel when its window is on screen, so the aura only animates while it can be
// seen, and when it becomes key, so the filter field can take focus.
// The menu bar panel posts an occlusion change when it opens but nothing at all (no occlusion
// change, no resign-key) when it hides. So while it's showing, a half-second check watches
// for the window leaving the screen. The check only runs while the panel is open.
struct WindowEvents: NSViewRepresentable {
    var onShow: () -> Void
    var onHide: () -> Void
    var onKey: () -> Void

    func makeNSView(context: Context) -> Tracker { Tracker() }
    func updateNSView(_ v: Tracker, context: Context) { v.onShow = onShow; v.onHide = onHide; v.onKey = onKey }

    final class Tracker: NSView {
        var onShow: () -> Void = {}
        var onHide: () -> Void = {}
        var onKey: () -> Void = {}
        private var visible = false
        private var poll: Timer?
        private var tokens: [NSObjectProtocol] = []

        private func setVisible(_ now: Bool) {
            guard now != visible else { return }
            visible = now
            poll?.invalidate()
            poll = nil
            if now {
                onShow()
                poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() }
            } else {
                onHide()
            }
        }

        private func check() {
            guard let w = window else { setVisible(false); return }
            setVisible(w.isVisible && w.occlusionState.contains(.visible) && w.alphaValue > 0)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let w = window else { setVisible(false); return }
            let nc = NotificationCenter.default
            tokens.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self] _ in self?.check() })
            tokens.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in self?.setVisible(false) })
            tokens.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.onKey() }
            })
            DispatchQueue.main.async { [weak self, weak w] in
                self?.check()
                if w?.isKeyWindow == true { self?.onKey() }
            }
        }
    }
}
