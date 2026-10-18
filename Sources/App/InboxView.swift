import SwiftUI
import AppKit

/// Everything that needs attention in one list, with a button per item.
@MainActor
final class InboxModel: ObservableObject {
    static let shared = InboxModel()
    @Published private(set) var entries: [Inbox.Entry] = []
    private static let dismissedKey = "inbox.dismissed", seenKey = "notices.seen"

    private var dismissed: Set<String> { Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? []) }
    private var reloadGeneration = 0
    private static let ackKey = "inbox.acked"
    /// The Inbox page is on screen: what arrives meanwhile counts as seen.
    var visible = false

    /// The sidebar badge counts entries the user has not looked at yet; opening the page clears it.
    private func updateBadge() {
        if visible { ack() }
        let acked = Set(UserDefaults.standard.stringArray(forKey: Self.ackKey) ?? [])
        SidebarBadges.shared.inbox = entries.filter { !acked.contains($0.id) }.count
    }

    func ack() {
        let ids = entries.map(\.id)
        // Only ids that exist now are kept: the set cannot grow beyond the list.
        UserDefaults.standard.set(ids, forKey: Self.ackKey)
        SidebarBadges.shared.inbox = 0
    }

    func dismiss(_ id: String) {
        // Ordered, so "the newest 500" really are the newest.
        var list = UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? []
        list.removeAll { $0 == id }; list.append(id)
        UserDefaults.standard.set(Array(list.suffix(500)), forKey: Self.dismissedKey)
        entries.removeAll { $0.id == id }
        updateBadge()
    }

    func markNoticeSeen(_ key: String) {
        var s = UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []
        if !s.contains(key) { s.append(key) }
        UserDefaults.standard.set(Array(s.suffix(500)), forKey: Self.seenKey)
        entries.removeAll { $0.kind == .notice && $0.ref == key }
        updateBadge()
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let res = Config.resources
        let today = DateFmt.today()
        let items = DeadlineActions.loadItems()
        let rows = Deadlines.rows(items, study: BotStore.shared.study)
        let overdue = rows.filter { !$0.done && ($0.item.date.flatMap { Deadlines.days(from: today, to: $0) } ?? 0) < 0 }
        let noticeRows = (MarkdownTables.tables(MarkdownTables.read("\(res)/notices.md")).first?.rows ?? []).map {
            Inbox.NoticeRow(date: MarkdownTables.clean($0["date"] ?? ""), course: MarkdownTables.clean($0["course"] ?? ""), title: $0["title"] ?? "")
        }
        let seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        let stale = SyncInfo.staleRows(MarkdownTables.tables(MarkdownTables.read("\(res)/sources.md")).first?.rows ?? [])
        let files = await Task.detached { () -> [Inbox.FileRow] in
            var out: [Inbox.FileRow] = []
            let fm = FileManager.default
            for course in MarkdownTables.courseFolders(resources: res) {
                let root = "\(res)/\(course)/2026"
                guard let en = fm.enumerator(atPath: root) else { continue }
                var n = 0
                while let rel = en.nextObject() as? String, n < 1500 {
                    n += 1
                    guard !(rel as NSString).lastPathComponent.hasPrefix("."), !rel.hasSuffix(".md") else { continue }
                    let p = "\(root)/\(rel)"
                    guard let a = try? fm.attributesOfItem(atPath: p), (a[.type] as? FileAttributeType) == .typeRegular,
                          let m = a[.modificationDate] as? Date else { continue }
                    out.append(Inbox.FileRow(path: p, course: course, modified: m))
                }
            }
            return out
        }.value
        // A newer reload started meanwhile: let it have the last word. Seen/dismissed are read again after the walk.
        guard generation == reloadGeneration else { return }
        let seenNow = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        entries = Inbox.build(overdue: overdue, today: today, notices: noticeRows, seen: seenNow.union(seen), files: files, staleSources: stale,
                              diverged: rows.filter(\.diverges), dismissed: dismissed)
        updateBadge()
    }
}

struct InboxView: View {
    @ObservedObject private var model = InboxModel.shared
    @ObservedObject private var store = StudyStore.shared
    @State private var error: String?

    var body: some View {
        PageView(title: "Inbox", summary: model.entries.isEmpty ? "Nothing needs attention" : "\(model.entries.count) need attention") {
            VStack(alignment: .leading, spacing: 24) {
                if let error { ErrorBanner(text: error) { self.error = nil } }
                if model.entries.isEmpty {
                    EmptyState(icon: "tray", title: "Inbox zero",
                               detail: "Overdue work, new announcements, new files and out-of-date chats show up here.")
                } else {
                    Group2 { Rows(items: model.entries) { row($0) } }
                }
            }
        }
        .onAppear { model.visible = true; model.ack() }
        .onDisappear { model.visible = false }
    }

    private func row(_ e: Inbox.Entry) -> some View {
        RowButton {
            HStack(spacing: 12) {
                Chip(text: e.kind.label, tone: e.kind == .overdue ? .bad : e.kind == .sync || e.kind == .diverged ? .warn : .accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(2)
                    HStack(spacing: 8) {
                        if !e.course.isEmpty { CourseTag(code: e.course) }
                        Text(e.detail).font(.meta).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                actions(e)
                Button { model.dismiss(e.id) } label: { Image(systemName: "xmark").font(.chip) }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Dismiss")
                    .accessibilityLabel("Dismiss \(e.title)")
            }
        }
    }

    @ViewBuilder private func actions(_ e: Inbox.Entry) -> some View {
        switch e.kind {
        case .overdue:
            Button("Done") {
                Task {
                    if let r = Deadlines.rows(DeadlineActions.loadItems(), study: BotStore.shared.study).first(where: { $0.id == e.ref }) {
                        error = await DeadlineActions.toggleWithUndo(r)
                        await model.reload()
                    }
                }
            }.buttonStyle(QuietButton())
            Button("Open") { open(deadline: e.ref) }.buttonStyle(QuietButton())
        case .diverged:
            Button("Open") { open(deadline: e.ref) }.buttonStyle(QuietButton())
        case .notice:
            Button("Seen") { model.markNoticeSeen(e.ref) }.buttonStyle(QuietButton())
            Button("Open") { Router.shared.page = .notices }.buttonStyle(QuietButton())
        case .file:
            Button("Open") { FileOpener.open(URL(fileURLWithPath: e.ref)) }.buttonStyle(QuietButton())
        case .sync:
            Button("Sync") { Router.shared.page = .sync }.buttonStyle(QuietButton())
        }
    }

    private func open(deadline id: String) { Router.shared.focusDeadline = id; Router.shared.page = .deadlines }
}
