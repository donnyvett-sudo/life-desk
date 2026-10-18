import SwiftUI

/// Announcements from the course chats, newest first, with unread markers.
struct NoticesSection: View {
    @ObservedObject private var docs = StudyDocsStore.shared
    @State private var query = ""
    @State private var course = ""

    var body: some View {
        let today = StudyData.today()
        let shown = docs.notices.filter { n in
            (course.isEmpty || n.course == course)
                && (query.isEmpty || [n.title, n.source, Theme.short(n.course)].contains { $0.localizedCaseInsensitiveContains(query) })
        }
        let courses = Array(Set(docs.notices.map(\.course).filter { !$0.isEmpty })).sorted()
        VStack(alignment: .leading, spacing: 14) {
            if !docs.loaded {
                if docs.failed {
                    VStack(spacing: 10) {
                        Text(L("Could not load announcements.")).font(.body13).foregroundStyle(Theme.muted)
                        Button(L("Try again")) { Task { await docs.refresh() } }.buttonStyle(QuietButton())
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                } else { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40) }
            } else if docs.unsupported || docs.notices.isEmpty {
                Group2 { EmptyState(icon: "bell", title: L("No announcements yet"),
                                    detail: docs.unsupported ? L("The server is being updated.") : L("Teacher messages appear here after your Mac syncs the chats.")) }
            } else {
                HStack {
                    SearchField(text: $query, prompt: L("Search announcements"))
                    if docs.unreadNotices > 0 { Button("Mark seen") { Task { await docs.markAllSeen() } }.buttonStyle(QuietButton()) }
                }
                if courses.count > 1 {
                    FlowChips {
                        FilterChip(title: L("All"), on: course.isEmpty) { course = "" }
                        ForEach(courses, id: \.self) { c in FilterChip(title: Theme.short(c), on: course == c) { course = course == c ? "" : c } }
                    }
                }
                let days = Dictionary(grouping: shown, by: \.date)
                ForEach(days.keys.sorted(by: >), id: \.self) { d in
                    Section2(title: Loc.dayTitle(d, today: today)) {
                        Group2 { Rows(items: days[d] ?? []) { n in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 8) {
                                    if !n.seen { Circle().fill(Theme.accent).frame(width: 8, height: 8).padding(.top, 6).accessibilityLabel("Unread") }
                                    Text(n.title).font(.rowTitle).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                                }
                                HStack(spacing: 6) {
                                    if !n.course.isEmpty { CourseTag(code: n.course) }
                                    Text(n.source).font(.meta).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                            }.padding(.horizontal, 14).padding(.vertical, 10)
                        } }
                    }
                }
            }
        }
        .task { await docs.refresh() }
    }
}

/// One course: its AI rule, overview text, deadlines, files and exam preparation.
struct CourseDetailScreen: View {
    @ObservedObject private var nav = Navigator.shared
    let course: BotStudy.Course
    @ObservedObject private var bot = BotStore.shared
    @ObservedObject private var docs = StudyDocsStore.shared
    @State private var done: Set<String> = []

    private var folder: String { Theme.folder(botShort: course.short) }

    var body: some View {
        let info = docs.courseInfo[folder]
        let tone = AIPolicy.level(course: folder, info: info) ?? (course.aiPolicy == "banned" ? .bad : course.aiPolicy == "own_work" ? .warn : nil)
        let tasks = StudyData.open(bot.study).filter { $0.a.course?.id == course.id }
        let exams = StudyData.exams(bot.study).filter { $0.course == course.short }
        let files = docs.files.filter { $0.course == folder }
        let topics = docs.examTopics[folder] ?? []
        PageView(title: course.title ?? course.short, summary: nil, trailing: {
            Button { Navigator.shared.go(.focus(courseId: course.id)) } label: { Label(L("Focus on this course"), systemImage: "timer") }
                .buttonStyle(QuietButton()).tint(Theme.focus)
        }) {
            VStack(alignment: .leading, spacing: 20) {
                if let tone {
                    Banner(icon: tone == .bad ? "exclamationmark.shield" : "info.circle",
                           text: tone == .bad ? L("AI is banned in assessments for this course.") : L("Assignments must be your own work."),
                           tone: tone == .bad ? .bad : .warn)
                }
                if !exams.isEmpty {
                    Section2(title: L("Exams")) {
                        Group2 { Rows(items: exams) { c in
                            Button { Navigator.shared.go(.exam(c.id)) } label: {
                                HStack {
                                    VStack(alignment: .leading) { Text(c.title).font(.rowTitle).foregroundStyle(Theme.text); Text(c.date).font(.meta).foregroundStyle(Theme.muted) }
                                    Spacer(); Chip(text: c.label, tone: c.days <= 3 ? .bad : .neutral)
                                    if docs.examTopics[folder] != nil { Image(systemName: "chevron.right").font(.chip).foregroundStyle(Theme.muted) }
                                }.padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        } }
                    }
                }
                if !topics.isEmpty {
                    Section2(title: L("Path"), count: nil) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView(value: Double(done.intersection(topics).count), total: Double(topics.count)).tint(Theme.course(folder))
                                Text(L("\(done.intersection(topics).count) of \(topics.count) topics")).font(.chip).monospacedDigit().foregroundStyle(Theme.muted).fixedSize()
                            }
                            LearningPath(topics: topics, done: done, tint: Theme.course(folder)) { toggle($0, all: topics) }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                    }
                }
                if !tasks.isEmpty {
                    Section2(title: L("Open deadlines"), count: tasks.count) {
                        Group2 { Rows(items: tasks) { r in DeadlineRow(row: r, today: StudyData.today()) } }
                    }
                }
                if let info, !info.isEmpty {
                    Section2(title: L("Overview")) { MarkdownView(text: info, skipFirstHeading: true, proseWidth: 600) }
                }
                if !files.isEmpty {
                    Section2(title: L("Files"), count: files.count) {
                        Group2 { Rows(items: Array(files.prefix(40))) { f in
                            VStack(alignment: .leading, spacing: 3) {
                                Text((f.path as NSString).lastPathComponent).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(2)
                                if !f.summary.isEmpty { Text(f.summary).font(.meta).foregroundStyle(Theme.muted).lineLimit(2) }
                                Text("The file itself stays on your Mac.").font(.chip).foregroundStyle(Theme.muted)
                            }.padding(.horizontal, 14).padding(.vertical, 10)
                        } }
                    }
                }
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .celebrates()
        .onAppear { done = Set(UserDefaults.standard.stringArray(forKey: "prep.done.\(folder)") ?? []) }
        .onChange(of: nav.sheet) { _, s in if s == nil { done = Set(UserDefaults.standard.stringArray(forKey: "prep.done.\(folder)") ?? []) } }
        .task { await docs.refresh() }
    }

    /// Same done-set as the exam plan sheet (UserDefaults "prep.done.<folder>").
    private func toggle(_ t: String, all: [String]) {
        // The exam sheet may have changed the set since this view loaded it: start from what is stored.
        done = Set(UserDefaults.standard.stringArray(forKey: "prep.done.\(folder)") ?? [])
        if done.contains(t) { done.remove(t) } else { done.insert(t) }
        UserDefaults.standard.set(Array(done), forKey: "prep.done.\(folder)")
        if done.contains(t), done.isSuperset(of: all) { Celebrate.shared.fire() }
    }
}

/// Day-by-day plan for an exam from the course's topic list; ticks are kept on this device.
struct ExamPrepSheet: View {
    let exam: StudyData.ExamCard
    let folder: String
    let topics: [String]
    @State private var done: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    private var key: String { "prep.done.\(folder)" }

    var body: some View {
        NavigationStack {
            PageView(title: L("Prepare: \(exam.title)"), summary: L("\(exam.days) d left · \(exam.date)"), trailing: { EmptyView() }) {
                VStack(alignment: .leading, spacing: 16) {
                    if let tone = AIPolicy.level(course: folder, info: StudyDocsStore.shared.courseInfo[folder]) {
                        Banner(icon: "exclamationmark.shield",
                               text: tone == .bad ? L("AI is banned in assessments here: explanations only.") : L("Your own work: use help to understand, not to produce what you submit."),
                               tone: tone == .bad ? .bad : .warn)
                    }
                    if topics.isEmpty {
                        Group2 { EmptyState(icon: "list.bullet", title: L("No topic list yet"), detail: L("Add a Topics table to archive-2025.md on your Mac and sync.")) }
                    } else {
                        ForEach(ExamPrep.plan(topics: topics, daysLeft: max(1, exam.days)), id: \.number) { d in
                            Section2(title: d.review ? L("Day \(d.number) · review and timed practice") : L("Day \(d.number)")) {
                                Group2 { Rows(items: d.topics.map { Topic(name: $0) }) { t in
                                    Button { toggle(t.name) } label: {
                                        HStack {
                                            Image(systemName: done.contains(t.name) ? "checkmark.square.fill" : "square").foregroundStyle(done.contains(t.name) ? Theme.accent : Theme.muted)
                                            Text(t.name).font(.body13).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                                            Spacer()
                                        }.padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityAddTraits(done.contains(t.name) ? .isSelected : [])
                                } }
                            }
                        }
                        Text("\(done.intersection(topics).count) of \(topics.count) topics done").font(.meta).foregroundStyle(Theme.muted)
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onAppear { done = Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        }
    }
    private struct Topic: Identifiable { let name: String; var id: String { name } }
    private func toggle(_ t: String) {
        if done.contains(t) { done.remove(t) } else { done.insert(t) }
        UserDefaults.standard.set(Array(done), forKey: key)
    }
}
