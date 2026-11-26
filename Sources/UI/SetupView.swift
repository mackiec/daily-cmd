import SwiftUI
import AppKit

// The first-run picker, and the settings section behind the gear in the footer: the same form.
// Choices save as soon as they're picked; Start/Done only closes the form.
struct SetupView: View {
    @ObservedObject var prefs: Prefs
    let firstRun: Bool
    let done: () -> Void

    // existing code folders, plus the current choice if it's somewhere else
    private var folders: [URL] {
        var c = Prefs.folderCandidates()
        if !c.contains(where: { $0.path == prefs.projectsRoot.path }) { c.append(prefs.projectsRoot) }
        return c
    }

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if firstRun {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hello.").font(.system(size: 26, weight: .light))
                        Text("cmd lists your projects and opens each one in a terminal with your coding agent ready. Three quick choices; change them any time from the gear in the footer.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }

                group("Where your projects live") {
                    ForEach(folders, id: \.path) { u in
                        Choice(title: tilde(u), selected: prefs.projectsRoot.path == u.path) { prefs.projectsRoot = u }
                    }
                    Button("Choose another folder…") { chooseFolder() }
                        .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Theme.fujiDeep).padding(.top, 2)
                }

                group("Open projects with") {
                    ForEach(Agent.allCases) { a in
                        Choice(title: a.name, hint: a.installed ? nil : "not found", selected: prefs.agent == a) { prefs.agent = a }
                    }
                }

                group("In") {
                    ForEach(TerminalApp.allCases) { t in
                        Choice(title: t.name, hint: t.installed ? nil : "not installed", selected: prefs.terminal == t, enabled: t.installed) {
                            prefs.terminal = t
                        }
                    }
                }

                group("Notes for agents") {
                    Toggle(isOn: $prefs.agentsPointer) {
                        Text("Add a line to each project's AGENTS.md that points to its to-dos and links")
                            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.switch).controlSize(.mini)
                    Text("The notes live in .cmd/ inside the project, kept out of git.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)

        // always in view, so nobody has to scroll to find it
        HStack {
            Button(firstRun ? "Start" : "Done", action: done).buttonStyle(PillButtonStyle(prominent: true))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Caption(title: title).padding(.bottom, 4)
            content()
        }
    }

    private func tilde(_ u: URL) -> String {
        let p = u.path, h = Env.home.path
        return p.hasPrefix(h) ? "~" + p.dropFirst(h.count) : p
    }

    // the open panel takes focus, so the menu bar panel closes; the choice is there when it reopens
    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.directoryURL = prefs.projectsRoot
        p.prompt = "Use this folder"
        p.message = "Choose the folder that holds your projects"
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK, let u = p.url { prefs.projectsRoot = u }
    }
}

// one option in a pick-one list
struct Choice: View {
    let title: String
    var hint: String? = nil
    let selected: Bool
    var enabled = true
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 9) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Theme.fujiDeep : Theme.muted)
                Text(title).font(.system(size: 13))
                Spacer()
                if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(Theme.muted) }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
