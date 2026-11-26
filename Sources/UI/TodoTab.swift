import SwiftUI

struct TodoTab: View {
    @ObservedObject var m: AppModel
    @ObservedObject var ui: PanelState
    var focus: FocusState<Field?>.Binding

    private struct DoneItem: Identifiable {
        let scope: Scope, todo: Todo
        var id: String { "\(scope.id)#\(todo.line)" }
    }

    private var target: Scope { m.scope(id: ui.todoScope) ?? .inbox }

    // projects with open to-dos; the Inbox too when it has any (or nothing else does)
    private var groups: [(scope: Scope, todos: [Todo])] {
        let all = m.scopes.map { s in (scope: s, todos: m.todos(s).filter { !$0.done }) }
        let filled = all.filter { !$0.todos.isEmpty }
        return filled.isEmpty ? Array(all.prefix(1)) : filled
    }

    // ticked off in the last 7 days, newest first. Older ones stay in the files but leave the list
    private var done: [DoneItem] {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return m.scopes.flatMap { s in
            m.todos(s).filter { $0.done && ($0.finishedDate ?? .distantPast) >= cutoff }.map { DoneItem(scope: s, todo: $0) }
        }
        .sorted { ($0.todo.finishedDate ?? .distantPast) > ($1.todo.finishedDate ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Add a to-do", text: $ui.todoText)
                    .inputField()
                    .focused(focus, equals: .todo)
                    .onSubmit { if m.addTodo(ui.todoText, default: target) { ui.todoText = "" } }
                ScopeChip(selection: $ui.todoScope, scopes: m.scopes)
            }
            .padding(.horizontal, 16)
            TokenHint(input: ui.todoText, projects: m.projects).padding(.horizontal, 26)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if groups.allSatisfy({ $0.todos.isEmpty }) && done.isEmpty {
                        Text("Nothing to do. Type above and press Return.\nAdd @project to file it under a project.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 28)
                    } else {
                        ForEach(groups, id: \.scope.id) { g in
                            VStack(alignment: .leading, spacing: 2) {
                                Caption(title: g.scope.name, count: g.todos.count).padding(.horizontal, 10).padding(.bottom, 2)
                                ForEach(g.todos) { t in TodoRow(t: t, s: g.scope, m: m, ui: ui) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .dropDestination(for: String.self) { items, _ in m.drop(items, on: g.scope) }
                        }
                        if !done.isEmpty { doneSection }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
        }
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { withAnimation(.easeOut(duration: 0.2)) { ui.showDone.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("Done [\(done.count)]").monoLabel(9.5)
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(ui.showDone ? 90 : 0))
                    Spacer()
                }
                .foregroundStyle(Theme.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
            if ui.showDone {
                ForEach(done) { d in TodoRow(t: d.todo, s: d.scope, m: m, ui: ui, showScope: true) }
            }
        }
    }
}

struct TodoRow: View {
    let t: Todo
    let s: Scope
    let m: AppModel
    @ObservedObject var ui: PanelState
    var showScope = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Button { m.setDone(t, !t.done, in: s) } label: {
                Image(systemName: t.done ? "checkmark.circle.fill" : "circle").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(t.done ? Theme.willow : Theme.muted)
            .help(t.done ? "Mark not done" : "Mark done")
            Text(t.text)
                .font(.system(size: 13))
                .strikethrough(t.done, color: Theme.muted)
                .foregroundStyle(t.done ? Theme.muted : Theme.sabi)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showScope { Text(s.name).font(.system(size: 10.5)).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .rowHover("todo:\(s.id)#\(t.line)", ui)
        .contentShape(Rectangle())
        .draggable(AppModel.dragPayload(todo: t, in: s))
        .contextMenu {
            Menu("Move to") {
                ForEach(m.scopes.filter { $0 != s }) { d in Button(d.name) { m.moveTodo(t, from: s, to: d) } }
            }
            Divider()
            Button("Delete") { m.deleteTodo(t, in: s) }
        }
    }
}
