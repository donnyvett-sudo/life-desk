import SwiftUI
import AppKit

/// Done/Undo shared by Today and Deadlines: file first (proves a unique row), then the bot, rolling the file back on failure.
enum DeadlineActions {
    static func localToday() -> String { DeadlinesView.localToday() }

    /// nil = ok, otherwise the message to show.
    @MainActor static func toggle(_ r: Deadlines.Row) async -> String? {
        let target = !r.done
        if r.botOnly, let id = r.botId {
            // No file row: the bot is the only record.
            do { try await BotAPI.setDone(id: id, done: target) } catch { return "Couldn't update the bot" }
            await BotStore.shared.refresh(afterWrite: true)
            return nil
        }
        guard AssignmentsFile.markDone(course: r.item.course, num: r.item.num, done: target) else {
            return "Couldn't find a unique matching row in assignments.md — nothing changed"
        }
        if let id = r.botId {
            do { try await BotAPI.setDone(id: id, done: target) } catch {
                let back = AssignmentsFile.markDone(course: r.item.course, num: r.item.num, done: !target)
                return back ? "Couldn't update the bot — file change undone"
                            : "Couldn't update the bot, and the file now says \(target ? "done" : "todo") — fix assignments.md by hand"
            }
        }
        await BotStore.shared.refresh(afterWrite: true)
        return nil
    }

    /// Done/Undo with a 5 s "Undo" toast. nil = ok, otherwise the message to show.
    @MainActor static func toggleWithUndo(_ r: Deadlines.Row) async -> String? {
        if let err = await toggle(r) { return err }
        var back = r; back.done = !r.done
        ToastCenter.shared.show(r.done ? "Reopened" : "Marked done") { Task { _ = await toggle(back); StudyStore.shared.tick += 1 } }
        return nil
    }

    /// Save panel -> .ics of open deadlines and exams.
    @MainActor static func exportCalendar(items: [MarkdownTables.Item], study: BotStudy?) {
        let text = ICS.calendar(assignments: Deadlines.rows(items, study: study), exams: items.filter { $0.kind == .exam },
                                label: Theme.short)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "life-desk-deadlines.ics"
        panel.allowedContentTypes = [.init(filenameExtension: "ics") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            ToastCenter.shared.show("Saved \(url.lastPathComponent)")
        } catch {
            ToastCenter.shared.show("Could not save the calendar file")
        }
    }

    static func loadItems() -> [MarkdownTables.Item] {
        MarkdownTables.assignments(resources: Config.resources) + MarkdownTables.exams(resources: Config.resources)
    }
}

struct DeadlinesView: View {
    @ObservedObject private var store = StudyStore.shared
    @ObservedObject private var bot = BotStore.shared
    @ObservedObject private var router = Router.shared
    @State private var items: [MarkdownTables.Item] = []
    @State private var query = ""
    @State private var course = ""          // "" = all
    @State private var showDone = false
    @State private var expanded: Set<String> = []
    @State private var error: String?

    private var today: String { Self.localToday() }
    static func localToday() -> String {
        DateFmt.today()
    }

    private func matches(_ it: MarkdownTables.Item) -> Bool {
        (course.isEmpty || it.course == course) &&
        (query.isEmpty || [it.title, it.details, it.num, Theme.short(it.course)].joined(separator: " ").localizedCaseInsensitiveContains(query))
    }

    /// One list entry: an assignment row or an exam.
    private struct Entry: Identifiable {
        var row: Deadlines.Row?
        var exam: MarkdownTables.Item?
        var item: MarkdownTables.Item { row?.item ?? exam! }
        var id: String { item.id }
    }

    var body: some View {
        let all = Deadlines.rows(items, study: bot.study)
        let rows = all.filter { matches($0.item) }
        let open = rows.filter { !$0.done }
        let done = rows.filter(\.done)
        let exams = items.filter { $0.kind == .exam && matches($0) && ($0.date.map { $0 >= today } ?? true) }
        let entries = MarkdownTables.sorted((open.map(\.item)) + exams).map { it in
            Entry(row: open.first { $0.id == it.id }, exam: it.kind == .exam ? it : nil)
        }
        let overdue = all.filter { !$0.done && Deadlines.bucket($0.item.date, today: today) == .overdue }.count
        let totalOpen = all.filter { !$0.done }.count
        let courses = Array(Set(all.filter { !$0.done }.map(\.item.course))).sorted()
        PageView(title: "Deadlines", summary: "\(totalOpen) open · \(overdue) overdue") {
            VStack(alignment: .leading, spacing: 24) {
                if let error { ErrorBanner(text: error) { self.error = nil } }
                filters(courses: courses, all: all)
                ForEach(Deadlines.Bucket.allCases, id: \.self) { b in
                    let part = entries.filter { Deadlines.bucket($0.item.date, today: today) == b }
                    if !part.isEmpty {
                        Section2(title: b.rawValue, count: part.count, tone: b == .overdue ? .bad : .neutral) {
                            Group2 { Rows(items: part) { entryRow($0) } }
                        }
                    }
                }
                if entries.isEmpty {
                    EmptyState(icon: "checkmark.circle", title: totalOpen == 0 ? "Nothing open" : "No matches",
                               detail: totalOpen == 0 ? "New homework appears here after a sync from the chats." : "Try another course or search term.")
                }
                if !done.isEmpty {
                    Button { showDone.toggle() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showDone ? "chevron.down" : "chevron.right").font(.chip)
                            Text("Show completed (\(done.count))").font(.body13)
                        }.foregroundStyle(Theme.muted)
                    }.buttonStyle(.plain)
                    if showDone { Group2 { Rows(items: done) { entryRow(Entry(row: $0)) } } }
                }
            }
        }
        .task(id: store.tick) {
            items = DeadlineActions.loadItems()
            await bot.refresh()
            SidebarBadges.shared.overdue = Deadlines.rows(items, study: bot.study)
                .filter { !$0.done && Deadlines.bucket($0.item.date, today: today) == .overdue }.count
        }
        .onAppear { applyFocus() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let s = bot.statusText { Chip(text: "Offline", tone: .warn).help(s) }
                Button { DeadlineActions.exportCalendar(items: items, study: bot.study) } label: { Label("Export .ics", systemImage: "calendar.badge.plus") }
                    .help("Save open deadlines and exams as a calendar file")
            }
        }
        .onChange(of: router.focusDeadline) { applyFocus() }
    }

    private func applyFocus() {
        guard let id = router.focusDeadline else { return }
        expanded.insert(id); course = ""; query = ""; router.focusDeadline = nil
    }

    private func filters(courses: [String], all: [Deadlines.Row]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DeskSearchField(prompt: "Search deadlines", text: $query)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(title: "All", on: course.isEmpty) { course = "" }
                    ForEach(courses, id: \.self) { c in
                        let n = all.filter { !$0.done && $0.item.course == c }.count
                        FilterChip(title: "\(Theme.short(c)) \(n)", on: course == c) { course = course == c ? "" : c }
                    }
                }
            }
        }
    }

    private func entryRow(_ e: Entry) -> some View {
        let it = e.item
        let r = e.row
        let isDone = r?.done ?? false
        let open = expanded.contains(e.id)
        return VStack(alignment: .leading, spacing: 0) {
            RowButton(action: { if !expanded.insert(e.id).inserted { expanded.remove(e.id) } }) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r?.title ?? it.title).font(.rowTitle).lineLimit(2).strikethrough(isDone)
                            .foregroundStyle(isDone ? Theme.muted : Theme.text)
                        HStack(spacing: 8) {
                            CourseTag(code: it.course)
                            if e.exam != nil { Chip(text: "Exam", tone: Deadlines.isTentative(it) ? .warn : .accent) }
                            if !it.dueText.isEmpty { Text(it.dueText).font(.meta).foregroundStyle(Theme.muted).lineLimit(1) }
                        }
                    }
                    Spacer(minLength: 8)
                    if !isDone { DueChip(date: it.date, today: today) }
                    if let r {
                        Button(r.done ? "Undo" : "Done") { Task { error = await DeadlineActions.toggleWithUndo(r) } }
                            .buttonStyle(QuietButton())
                    }
                }
            }
            if open { detail(e) }
        }
        .opacity(isDone ? 0.6 : 1)
    }

    private func detail(_ e: Entry) -> some View {
        let it = e.item
        let url = it.file.isEmpty ? nil : URL(fileURLWithPath: "\(Config.resources)/\(it.course)/\(it.file)")
        let exists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            let full = e.row?.full ?? [it.title, it.details].filter { !$0.isEmpty }.joined(separator: "\n\n")
            Text(full).font(.body13).foregroundStyle(Theme.text).textSelection(.enabled)
            if !it.submission.isEmpty { labelled("Submission", it.submission) }
            if !it.file.isEmpty { labelled("Source", "resources/\(it.course)/\(it.file)") }
            if let r = e.row, r.diverges {
                Text(r.botDone == true ? "Done in the bot, still open in the file — mark it done in the file." : "Open in the bot, done in the file — run life_sync.")
                    .font(.meta).foregroundStyle(Theme.muted)
            }
            if let r = e.row, r.botId == nil, !r.done { Text("Not in the bot yet — appears after the next sync.").font(.meta).foregroundStyle(Theme.muted) }
            if it.kind == .exam {
                Button("Prepare…") { Router.shared.prepExam = it }.buttonStyle(QuietButton())
            }
            if exists, let url {
                Button("Open file") { FileOpener.open(url) }.buttonStyle(QuietButton())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    private func labelled(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(k.uppercased()).font(.sectionLabel).tracking(0.6).foregroundStyle(Theme.muted).frame(width: 84, alignment: .leading)
            Text(v).font(.meta).foregroundStyle(Theme.muted).textSelection(.enabled)
        }
    }
}
