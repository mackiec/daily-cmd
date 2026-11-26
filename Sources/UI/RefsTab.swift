import SwiftUI
import AppKit

struct RefsTab: View {
    @ObservedObject var m: AppModel
    @ObservedObject var ui: PanelState
    var focus: FocusState<Field?>.Binding

    private var target: Scope { m.scope(id: ui.refScope) ?? .inbox }

    // projects with saved links, newest first; the Inbox too when it has any (or nothing else does)
    private var groups: [(scope: Scope, refs: [Ref])] {
        let all = m.scopes.map { s in (scope: s, refs: Array(m.refs(s).reversed())) }
        let filled = all.filter { !$0.refs.isEmpty }
        return filled.isEmpty ? Array(all.prefix(1)) : filled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Paste a link", text: $ui.refText)
                    .inputField()
                    .focused(focus, equals: .ref)
                    .onSubmit { if m.addRef(ui.refText, default: target) { ui.refText = "" } }
                ScopeChip(selection: $ui.refScope, scopes: m.scopes)
            }
            .padding(.horizontal, 16)
            TokenHint(input: ui.refText, projects: m.projects).padding(.horizontal, 26)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if groups.allSatisfy({ $0.refs.isEmpty }) {
                        Text("No links saved yet. Paste one above and press Return.\nWords after the link become its note.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 28)
                    } else {
                        ForEach(groups, id: \.scope.id) { g in
                            VStack(alignment: .leading, spacing: 2) {
                                Caption(title: g.scope.name, count: g.refs.count).padding(.horizontal, 10).padding(.bottom, 2)
                                ForEach(g.refs) { r in RefRow(r: r, s: g.scope, m: m, ui: ui, focus: focus) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .dropDestination(for: String.self) { items, _ in m.drop(items, on: g.scope) }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
        }
    }
}

struct RefRow: View {
    let r: Ref
    let s: Scope
    let m: AppModel
    @ObservedObject var ui: PanelState
    var focus: FocusState<Field?>.Binding

    private var key: String { "ref:\(s.id)#\(r.url.absoluteString)" }
    private var editing: Bool { ui.editingNote == key }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(r.title).font(.system(size: 13)).lineLimit(1)
            Text([Links.placeholder(r.url), r.added].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
            if editing {
                TextField("Add a note", text: $ui.noteText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused(focus, equals: .note)
                    .onSubmit { m.setNote(r, ui.noteText, in: s); ui.editingNote = nil }
                    .onExitCommand { ui.editingNote = nil }
                    .padding(.top, 2)
            } else if let n = r.note {
                Text(n).font(.system(size: 12)).foregroundStyle(Theme.fujiDeep).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .rowHover(key, ui)
        .contentShape(Rectangle())
        .onTapGesture { if !editing { NSWorkspace.shared.open(r.url) } }
        .help(r.url.absoluteString)
        .draggable(AppModel.dragPayload(ref: r, in: s))
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(r.url) }
            Button("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(r.url.absoluteString, forType: .string)
            }
            Button(r.note == nil ? "Add note" : "Edit note") {
                ui.noteText = r.note ?? ""
                ui.editingNote = key
                DispatchQueue.main.async { focus.wrappedValue = .note }
            }
            Menu("Move to") {
                ForEach(m.scopes.filter { $0 != s }) { d in Button(d.name) { m.moveRef(r, from: s, to: d) } }
            }
            Divider()
            Button("Delete") { m.deleteRef(r, in: s) }
        }
    }
}
