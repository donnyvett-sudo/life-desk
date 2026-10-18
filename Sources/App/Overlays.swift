import SwiftUI
import AppKit

/// A short message with an optional Undo, shown at the bottom of the window for 5 s.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    struct Toast: Identifiable { let id = UUID(); let text: String; let undo: (() -> Void)? }
    @Published private(set) var toast: Toast?

    func show(_ text: String, undo: (() -> Void)? = nil) {
        let t = Toast(text: text, undo: undo)
        toast = t
        Task { try? await Task.sleep(nanoseconds: 5_000_000_000); if toast?.id == t.id { toast = nil } }
    }
    func dismiss() { toast = nil }
}

struct ToastView: View {
    @ObservedObject private var center = ToastCenter.shared
    var body: some View {
        if let t = center.toast {
            HStack(spacing: 12) {
                Text(t.text).font(.body13).foregroundStyle(Theme.text)
                if let undo = t.undo { Button("Undo") { center.dismiss(); undo() }.buttonStyle(QuietButton()) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
            .padding(.bottom, 18)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }
}

/// ⌘K: pages, actions and deadlines in one list.
struct CommandPalette: View {
    @ObservedObject private var router = Router.shared
    @ObservedObject private var bot = BotStore.shared
    @State private var query = ""
    @State private var selection = 0
    @State private var docs: [SearchIndex.Doc] = []
    @FocusState private var focused: Bool

    struct Entry: Identifiable {
        let id: String
        let title: String
        let hint: String
        let run: () -> Void
    }

    private var entries: [Entry] {
        var all: [Entry] = []
        for p in Page.study + Page.life {
            all.append(Entry(id: "page-\(p.rawValue)", title: "Go to \(p.title)", hint: "Page") { router.page = p })
        }
        all.append(Entry(id: "new-chat", title: "New chat", hint: "Agent") { router.page = .chat; ChatModel.shared.newChat() })
        all.append(Entry(id: "start-focus", title: "Start focus…", hint: "Focus") { router.page = .focus })
        let items = DeadlineActions.loadItems()
        for r in Deadlines.rows(items, study: bot.study) where !r.done {
            all.append(Entry(id: "done-\(r.id)", title: "Mark done: \(r.title)", hint: "Deadline") {
                Task { @MainActor in
                    if let err = await DeadlineActions.toggleWithUndo(r) { ToastCenter.shared.show(err) }
                }
            })
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return Array(all.prefix(12)) }
        let actions = all.filter { ($0.title + " " + $0.hint).lowercased().contains(q) }.prefix(5).map { $0 }
        let found = SearchIndex.search(docs, query: q, limit: 12).map { d in
            Entry(id: d.id, title: d.title, hint: d.kind.label + (d.body.isEmpty ? "" : " · " + SearchIndex.snippet(d.body, query: q, radius: 24))) {
                open(d)
            }
        }
        return Array((actions + found).prefix(14))
    }

    var body: some View {
        let list = entries
        VStack(spacing: 0) {
            TextField("Type a page, action or deadline", text: $query)
                .textFieldStyle(.plain).font(.system(size: 16)).padding(14)
                .focused($focused)
                .onSubmit { run(list) }
                .onChange(of: query) { selection = 0 }
                .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, list.count - 1)); return .handled }
                .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
                .onKeyPress(.escape) { router.paletteVisible = false; return .handled }
            Hairline()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                        Button { selection = i; run(list) } label: {
                            HStack {
                                Text(e.title).font(.body13).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer()
                                Text(e.hint).font(.meta).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(i == selection ? Theme.surface2 : .clear)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if list.isEmpty { Text("Nothing found").font(.body13).foregroundStyle(Theme.muted).padding(14) }
                }
            }.frame(maxHeight: 320)
        }
        .frame(width: 520)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear { focused = true; query = ""; selection = 0 }
        .task { docs = await SearchSources.collect() }
    }

    private func open(_ d: SearchIndex.Doc) {
        switch d.kind {
        case .deadline: router.focusDeadline = d.ref; router.page = .deadlines
        case .notice: router.page = .notices
        case .file: FileOpener.open(URL(fileURLWithPath: d.ref))
        case .chat:
            if let id = UUID(uuidString: d.ref) { ChatModel.shared.select(id) }
            router.page = .chat
        case .course: router.page = .courses
        }
    }

    private func run(_ list: [Entry]) {
        guard selection < list.count else { return }
        let e = list[selection]
        router.paletteVisible = false
        e.run()
    }
}
