import SwiftUI

private struct Notice: Identifiable {
    let id: Int
    let date: String, course: String, title: String, source: String
    var key: String { NoticeLogic.key(date: date, course: course, title: title) }
}

struct NoticesView: View {
    @ObservedObject private var store = StudyStore.shared
    @State private var all: [Notice] = []
    @State private var seen: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "notices.seen") ?? [])
    @State private var query = ""
    @State private var course = ""
    @State private var expanded: Set<Int> = []

    private var shown: [Notice] {
        all.filter { n in
            (course.isEmpty || n.course == course)
                && (query.isEmpty || [n.title, n.source, Theme.short(n.course)].contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    private var days: [(String, [Notice])] {
        let d = Dictionary(grouping: shown, by: \.date)
        return d.keys.sorted(by: >).map { ($0, d[$0]!) }
    }
    private var unread: Int { all.filter { !seen.contains($0.key) }.count }

    var body: some View {
        let today = isoToday()
        PageView(title: "Notices",
                 summary: all.isEmpty ? nil : unread == 0 ? "All seen · \(all.count) announcements" : "\(unread) new · \(all.count) announcements") {
            if all.isEmpty {
                EmptyState(icon: "bell", title: "No announcements yet",
                           detail: "Teacher messages that are not homework or exams land in resources/notices.md when you run sync.")
            } else {
                filters
                if days.isEmpty { EmptyState(icon: "magnifyingglass", title: "Nothing matches", detail: "Clear the search or pick All courses.") }
                ForEach(days, id: \.0) { day, items in
                    Section2(title: NoticeLogic.dayTitle(day, today: today), count: items.count) {
                        Group2 { Rows(items: items) { row($0) } }
                    }
                }
            }
        }
        .task(id: store.tick) { load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { markSeen() } label: { Label("Mark all seen", systemImage: "checkmark.circle") }.disabled(unread == 0)
                    .help("Clears the new markers and the sidebar badge")
            }
        }
        .onChange(of: unread) { _, n in SidebarBadges.shared.newNotices = n }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchField(text: $query, prompt: "Search announcements").frame(maxWidth: 320)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(title: "All", on: course.isEmpty) { course = "" }
                    ForEach(Array(Set(all.map(\.course))).sorted(), id: \.self) { c in
                        FilterChip(title: Theme.short(c), on: course == c) { course = c }
                    }
                }
            }
        }
    }

    private func row(_ n: Notice) -> some View {
        let open = expanded.contains(n.id)
        let long = n.title.count > 200
        let isNew = !seen.contains(n.key)
        return RowButton(action: { if !expanded.insert(n.id).inserted { expanded.remove(n.id) } }) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(isNew ? Theme.accent : .clear).frame(width: 7, height: 7).padding(.top, 5)
                    .help(isNew ? "New since you last marked all seen" : "")
                VStack(alignment: .leading, spacing: 5) {
                    CourseTag(code: n.course)
                    Text(MarkdownView.inline(n.title)).font(.body13).foregroundStyle(Theme.text).lineSpacing(3)
                        .lineLimit(open ? nil : 3).multilineTextAlignment(.leading)
                    if long && !open { Text("more").font(.meta).foregroundStyle(Theme.accent) }
                    if !n.source.isEmpty {
                        Text(MarkdownView.inline(n.source)).font(.meta).foregroundStyle(Theme.muted).lineLimit(open ? nil : 1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func markSeen() {
        seen.formUnion(all.map(\.key))
        UserDefaults.standard.set(Array(seen), forKey: "notices.seen")
    }

    private func load() {
        let rows = MarkdownTables.tables(readResource("notices.md")).first?.rows ?? []
        all = rows.enumerated().map { i, r in
            Notice(id: i, date: MarkdownTables.clean(r["date"] ?? ""), course: MarkdownTables.clean(r["course"] ?? ""),
                   title: r["title"] ?? "", source: r["source"] ?? "")
        }
        SidebarBadges.shared.newNotices = unread
    }
}
