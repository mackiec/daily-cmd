import SwiftUI
import AppKit

struct ProjectsTab: View {
    @ObservedObject var m: AppModel
    @ObservedObject var ui: PanelState
    var focus: FocusState<Field?>.Binding

    private var shown: [Project] {
        ui.filter.isEmpty ? m.projects : m.projects.filter { $0.name.localizedCaseInsensitiveContains(ui.filter) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Filter", text: $ui.filter)
                .inputField()
                .focused(focus, equals: .filter)
                .onSubmit { if let p = shown.first { m.open(p) } }
                .padding(.horizontal, 16)

            // a plain VStack, not a LazyVStack: with a dozen rows laziness buys nothing, and the lazy
            // stack sometimes drew no rows after the panel reopened
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(shown) { p in ProjectRow(p: p, m: m, ui: ui, pinned: m.isPinned(p)) }
                    if shown.isEmpty {
                        Text(ui.filter.isEmpty ? "No folders in ~/Projects yet." : "No project matches “\(ui.filter)”.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 24)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
        }
    }
}

struct ProjectRow: View {
    let p: Project
    let m: AppModel
    @ObservedObject var ui: PanelState
    // passed in as a value so the row redraws when it's pinned or unpinned (it doesn't observe the model)
    let pinned: Bool

    private var scope: Scope { Scope(project: p.url) }
    private var hasItems: Bool { !p.openTodos.isEmpty || !p.refs.isEmpty }
    private var expanded: Bool { ui.expanded.contains(p.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(p.name).font(.system(size: 13.5))
                        if pinned {
                            Image(systemName: "pin.fill").font(.system(size: 8.5)).rotationEffect(.degrees(40))
                                .foregroundStyle(Theme.fujiDeep).help("Pinned")
                        }
                    }
                    if let s = p.lastSession {
                        Text("last session \(ago(s))").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 8)
                if !p.openTodos.isEmpty {
                    Text("[\(p.openTodos.count)]").monoLabel(10).foregroundStyle(Theme.fujiDeep)
                }
                if hasItems {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if expanded { ui.expanded.remove(p.id) } else { ui.expanded.insert(p.id) }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .help(expanded ? "Hide to-dos and references" : "Show to-dos and references")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .rowHover("project:\(p.id)", ui)
            .contentShape(Rectangle())
            .onTapGesture { m.open(p) }
            .contextMenu {
                Button(pinned ? "Unpin" : "Pin to top") { m.togglePin(p) }
                Divider()
                if p.lastSession != nil { Button("Continue last session") { m.open(p) } }
                if Prefs.shared.agent.command != nil { Button("New session") { m.open(p, fresh: true) } }
                Divider()
                Button("Open in Finder") { Projects.reveal(p) }
                Button("Copy path") { Projects.copyPath(p) }
            }

            if expanded && hasItems { detail }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(p.openTodos) { t in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button { m.setDone(t, true, in: scope) } label: { Image(systemName: "circle").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Mark done")
                    Text(t.text).font(.system(size: 12))
                }
            }
            ForEach(p.refs) { r in
                Button { NSWorkspace.shared.open(r.url) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "arrow.up.right").font(.system(size: 9.5)).foregroundStyle(Theme.fujiDeep)
                        Text(r.title).font(.system(size: 12)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help(r.url.absoluteString)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }
}
