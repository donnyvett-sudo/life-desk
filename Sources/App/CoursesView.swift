import SwiftUI

func countFiles(_ dir: String) -> Int { courseFileList(dir).count }

func courseFileList(_ dir: String) -> [URL] {
    guard let en = FileManager.default.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: [.skipsHiddenFiles]) else { return [] }
    var out: [URL] = []
    for case let u as URL in en where (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        && u.lastPathComponent != "files.md" { out.append(u) }
    return out.sorted { $0.path < $1.path }
}

func isoToday() -> String {
    DateFmt.today()
}

private enum CourseTab: String, CaseIterable, Identifiable {
    case overview = "Overview", tasks = "Assignments", files = "Files", facts = "Facts"
    var id: String { rawValue }
}

private extension Tone {
    init(_ p: CourseInfo.PolicyTone) { self = p == .bad ? .bad : .warn }
    init(_ d: DueTone) { self = d == .bad ? .bad : d == .accent ? .accent : .neutral }
}

struct CoursesView: View {
    @ObservedObject private var store = StudyStore.shared
    @State private var folders: [String] = []
    @State private var titles: [String: String] = [:]
    @State private var open: [String: Int] = [:]
    @State private var total: [String: (done: Int, all: Int)] = [:]
    @AppStorage("courses.selected") private var selected = ""

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 260)
            Rectangle().fill(Theme.line).frame(width: 1)
            Group {
                if folders.contains(selected) {
                    CourseDetail(course: selected, title: titles[selected] ?? Theme.short(selected)).id(selected)
                } else {
                    EmptyState(icon: "books.vertical", title: "Pick a course",
                               detail: "Courses come from the folders in resources/.").frame(maxHeight: .infinity)
                }
            }.frame(maxWidth: .infinity).background(Theme.bg)
        }
        .task(id: store.tick) { reload() }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("COURSES").font(.sectionLabel).tracking(0.6).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10).padding(.bottom, 6)
                ForEach(folders, id: \.self) { f in CourseListRow(code: f, count: open[f] ?? 0, progress: total[f] ?? (0, 0), on: selected == f) { selected = f } }
            }.padding(12)
        }.background(Theme.sidebar)
    }

    private func reload() {
        let res = Config.resources
        let all = MarkdownTables.courseFolders(resources: res).filter { $0 != "general" }
        let items = MarkdownTables.assignments(resources: res)
        open = Dictionary(uniqueKeysWithValues: all.map { f in (f, items.filter { $0.course == f && !$0.done }.count) })
        total = Dictionary(uniqueKeysWithValues: all.map { f in
            let mine = items.filter { $0.course == f && $0.kind == .assignment }
            return (f, (mine.filter(\.done).count, mine.count))
        })
        folders = all
        titles = MarkdownTables.courseTitles(workspace: Config.workspace)
        if !all.contains(selected), let f = all.first { selected = f }
    }
}

private struct CourseListRow: View {
    let code: String, count: Int, progress: (done: Int, all: Int), on: Bool, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7).fill(Theme.course(code)).frame(width: 28, height: 28)
                    .overlay { Text(String(Theme.short(code).prefix(1))).font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(Theme.short(code)).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(1)
                    if progress.all > 0 {
                        HStack(spacing: 6) {
                            ProgressView(value: Double(progress.done), total: Double(progress.all)).tint(Theme.course(code)).frame(width: 60)
                            Text("\(progress.done)/\(progress.all)").font(.meta).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                }
                Spacer(minLength: 4)
                if let p = CourseInfo.policy(code) {
                    Image(systemName: p.tone == .bad ? "exclamationmark.shield.fill" : "pencil.line")
                        .font(.meta).foregroundStyle(Tone(p.tone).color).help(p.text)
                }
                if count > 0 { Chip(text: "\(count)", tone: .accent) }
            }
            .padding(.horizontal, 10).frame(minHeight: 44)
            .background(on ? Theme.surface2 : hover ? Theme.surface2.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

private struct CourseDetail: View {
    let course: String
    let title: String
    @ObservedObject private var store = StudyStore.shared
    @AppStorage("courses.tab") private var tabRaw = CourseTab.overview.rawValue
    @State private var info = ""
    @State private var teacher: String?
    @State private var facts: MarkdownTables.Table?
    @State private var tasks: [MarkdownTables.Item] = []

    private var tab: Binding<CourseTab> {
        Binding(get: { CourseTab(rawValue: tabRaw) ?? .overview }, set: { tabRaw = $0.rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.pageTitle).foregroundStyle(Theme.text)
                    if let teacher { Text(teacher).font(.body13).foregroundStyle(Theme.muted) }
                }
                if let p = CourseInfo.policy(course) {
                    Banner(icon: p.tone == .bad ? "exclamationmark.shield.fill" : "pencil.line", text: p.text, tone: Tone(p.tone))
                }
                Picker("", selection: tab) { ForEach(CourseTab.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 400)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
            .frame(maxWidth: 780, alignment: .leading)
            ScrollView {
                content.padding(.horizontal, 28).padding(.bottom, 28)
                    .frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: store.tick) { load() }
    }

    @ViewBuilder private var content: some View {
        switch tab.wrappedValue {
        case .overview:
            if info.isEmpty {
                EmptyState(icon: "doc.text", title: "No course-info.md yet",
                           detail: "It is created when the syllabus arrives in a chat (run sync).")
            } else { MarkdownView(text: info, skipFirstHeading: true) }
        case .tasks: tasksTab
        case .files: CourseFilesTab(course: course)
        case .facts: factsTab
        }
    }

    private var tasksTab: some View {
        let today = isoToday()
        let open = MarkdownTables.sorted(tasks.filter { !$0.done }), done = tasks.filter(\.done)
        return VStack(alignment: .leading, spacing: 16) {
            if tasks.isEmpty {
                EmptyState(icon: "checklist", title: "No assignments yet",
                           detail: "Forwarded or synced homework shows up here from assignments.md.")
            }
            if !open.isEmpty { Section2(title: "Open", count: open.count) { Group2 { Rows(items: open) { taskRow($0, today) } } } }
            if !done.isEmpty { Section2(title: "Done", count: done.count) { Group2 { Rows(items: done) { taskRow($0, today) } } } }
            if !tasks.isEmpty { Text("Mark as done on the Deadlines page.").font(.meta).foregroundStyle(Theme.muted) }
        }
    }

    private func taskRow(_ t: MarkdownTables.Item, _ today: String) -> some View {
        let due = CourseInfo.dueLabel(date: t.date, today: today)
        return RowButton(action: { Router.shared.page = .deadlines }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title.isEmpty ? t.num : "\(t.num) · \(t.title)").font(.rowTitle)
                        .foregroundStyle(Theme.text).strikethrough(t.done).lineLimit(2)
                    if !t.dueText.isEmpty { Text(t.dueText).font(.meta).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1) }
                }
                Spacer(minLength: 8)
                if t.done { Chip(text: "done", tone: .good) } else { Chip(text: due.text, tone: Tone(due.tone)) }
            }.opacity(t.done ? 0.6 : 1)
        }
    }

    private var factsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let facts, !facts.rows.isEmpty {
                Group2 {
                    Rows(items: facts.rows.enumerated().map { FactRow(id: $0.offset, r: $0.element) }) { f in
                        RowButton {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Self.label(f.r["key"] ?? "")).font(.sectionLabel).tracking(0.6).foregroundStyle(Theme.muted)
                                Text(MarkdownView.inline(f.r["value"] ?? "")).font(.body13).foregroundStyle(Theme.text)
                                    .lineSpacing(3).textSelection(.enabled)
                                if let s = f.r["source"], !s.isEmpty {
                                    Text("Source: \(MarkdownTables.clean(s))").font(.meta).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }
            } else {
                EmptyState(icon: "text.badge.checkmark", title: "No facts from chats yet",
                           detail: "Submission rules and teacher announcements are added to course-info.md → “Facts from chats” by sync.")
            }
        }
    }

    private struct FactRow: Identifiable { let id: Int; let r: [String: String] }
    static func label(_ key: String) -> String {
        let s = MarkdownTables.clean(key).replacingOccurrences(of: "_", with: " ")
        return s.uppercased()
    }

    private func load() {
        info = readResource("\(course)/course-info.md")
        teacher = CourseInfo.teacher(info: info)
        facts = MarkdownTables.tables(info).first { $0.heading.lowercased().contains("facts") }
        tasks = MarkdownTables.assignments(resources: Config.resources).filter { $0.course == course && $0.kind == .assignment }
    }
}
