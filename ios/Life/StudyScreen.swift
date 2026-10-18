import SwiftUI

/// Study: deadlines, exams, courses, announcements behind one selector.
struct StudyScreen: View {
    enum Part: String, CaseIterable, Identifiable { case deadlines = "Deadlines", exams = "Exams", courses = "Courses", notices = "Notices"; var id: String { rawValue } }
    @ObservedObject private var bot = BotStore.shared
    @ObservedObject private var docs = StudyDocsStore.shared
    @ObservedObject private var nav = Navigator.shared
    @State private var query = ""
    @State private var course = ""
    @State private var expanded: Set<String> = []
    @ObservedObject private var focus = FocusModel.shared

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Study")).font(.pageTitle).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    if let s = bot.statusText { Chip(text: L("Offline"), tone: .warn).accessibilityHint(s) }
                    FlameChip(count: FocusStats.streak(bot.focusLog, today: StudyData.today()), label: L("focus"), tint: Theme.focus, route: .focus(courseId: nil))
                }
                Button { nav.go(.focus(courseId: nil)) } label: {
                    Label(focus.immersive ? L("Focus running · \(FocusLogic.clock(focus.remaining))") : L("Start focus"), systemImage: "timer")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }.buttonStyle(PrimaryButton())
                Button { nav.go(.cards) } label: { Label("Chinese cards", systemImage: "rectangle.stack").frame(maxWidth: .infinity).padding(.vertical, 4) }
                    .buttonStyle(QuietButton())
                Picker("", selection: $nav.studyPart) { ForEach(AppRoute.StudyPart.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue.capitalized)).tag($0) } }.pickerStyle(.segmented)
            }
            .plainRow()
            switch nav.studyPart {
            case .deadlines: deadlines
            case .exams: exams
            case .courses: courses
            case .notices: Section { NoticesSection() }.plainRow()
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .celebrates()
        .refreshable { await bot.refresh() }
        .task { await bot.refresh() }
    }

    private func header(_ title: String, count: Int? = nil, tone: Tone = .neutral) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).font(.sectionLabel).tracking(0.6).foregroundStyle(tone == .neutral ? Theme.muted : tone.color)
            if let count { Text("\(count)").font(.chip).monospacedDigit().foregroundStyle(Theme.muted) }
        }.textCase(nil)
    }

    // MARK: deadlines
    private var courseCodes: [String] { Array(Set(StudyData.open(bot.study).map(\.course).filter { !$0.isEmpty })).sorted() }

    @ViewBuilder private var deadlines: some View {
        let today = StudyData.today()
        let match: (StudyData.DueRow) -> Bool = { r in
            (course.isEmpty || r.course == course)
                && (query.isEmpty || [r.a.title, r.course, r.a.details ?? ""].contains { $0.localizedCaseInsensitiveContains(query) })
        }
        let all = StudyData.open(bot.study).filter(match)
        let finished = (bot.study?.recentlyDone ?? []).map(StudyData.DueRow.init).filter(match).prefix(5)
        // On accessibility text sizes the swipe is hard to find and to do: the button stays.
        let button = typeSize.isAccessibilitySize
        Section {
            SearchField(text: $query, prompt: L("Search deadlines"))
            if courseCodes.count > 1 || !course.isEmpty {
                FlowChips {
                    FilterChip(title: L("All"), on: course.isEmpty) { course = "" }
                    ForEach(courseCodes, id: \.self) { c in
                        FilterChip(title: c, on: course == c) { course = course == c ? "" : c }
                    }
                }
            }
        }.plainRow()
        if all.isEmpty {
            Section { EmptyState(icon: "checkmark.circle", title: L("Nothing open"), detail: query.isEmpty ? nil : L("Nothing matches “\(query)”.")) }
                .listRowBackground(Theme.surface)
        }
        ForEach([Deadlines.Bucket.overdue, .week, .later, .undated], id: \.self) { b in
            let rows = all.filter { Deadlines.bucket($0.a.dueDate, today: today) == b }
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { r in
                        VStack(alignment: .leading, spacing: 0) {
                            // A deadline with notes expands (and offers the course); one without opens its course.
                            let notes = [r.a.details, r.a.dueNote].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                            Button {
                                if notes.isEmpty, let c = r.a.course?.id { nav.go(.course(c)) }
                                else if !expanded.insert(r.id).inserted { expanded.remove(r.id) }
                            } label: {
                                DeadlineRow(row: r, today: today, showButton: button).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if expanded.contains(r.id), !notes.isEmpty {
                                Text(notes).font(.body13).foregroundStyle(Theme.muted).textSelection(.enabled)
                                    .padding(.horizontal, 14).padding(.bottom, r.a.course == nil ? 12 : 0)
                                if let c = r.a.course?.id {
                                    Button { nav.go(.course(c)) } label: { Label(L("Open course"), systemImage: "arrow.right.circle") }
                                        .buttonStyle(QuietButton()).padding(.horizontal, 8)
                                }
                            }
                        }
                        .row()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) { doneButton(r, done: true) }
                        .contextMenu { doneButton(r, done: true) }
                    }
                } header: { header(Loc.bucket(b), count: rows.count, tone: b == .overdue ? .bad : .neutral) }
            }
        }
        if !finished.isEmpty {
            Section {
                ForEach(Array(finished)) { r in
                    DeadlineRow(row: r, today: today, showButton: button, finished: true)
                        .row()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) { doneButton(r, done: false) }
                        .contextMenu { doneButton(r, done: false) }
                }
            } header: { header(L("Recently done")) }
        }
    }

    /// Swipe and menu action: mark done, or reopen a finished one (the toast offers Undo either way).
    private func doneButton(_ r: StudyData.DueRow, done: Bool) -> some View {
        Button { Task { await Celebrate.deadline(id: r.a.id, done: done, title: r.a.title) } } label: {
            Label(done ? L("Done") : L("Reopen"), systemImage: done ? "checkmark" : "arrow.uturn.backward")
        }.tint(done ? Theme.good : Theme.accent)
    }

    // MARK: exams
    @ViewBuilder private var exams: some View {
        let list = StudyData.exams(bot.study)
        Section {
            if list.isEmpty {
                EmptyState(icon: "graduationcap", title: L("No upcoming exams"), detail: L("Dates appear after a sync from your Mac.")).row()
            } else {
                ForEach(list) { c in
                    Button { nav.go(.exam(c.id)) } label: { HStack(spacing: 12) {
                        Text(c.label).font(.bigNumber).monospacedDigit().frame(width: 84, alignment: .leading)
                            .foregroundStyle(c.days <= 3 ? Tone.bad.color : c.tentative ? Tone.warn.color : Theme.text)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.title).font(.rowTitle).foregroundStyle(Theme.text)
                            HStack(spacing: 6) {
                                CourseTag(code: Theme.folder(botShort: c.course))
                                Text(c.date).font(.meta).foregroundStyle(Theme.muted)
                                if c.tentative { Chip(text: L("Tentative"), tone: .warn) }
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.meta).foregroundStyle(Theme.muted)
                    }.padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle()).accessibilityElement(children: .combine) }
                    .buttonStyle(.plain).accessibilityHint(L("Opens the preparation plan"))
                    .row()
                }
            }
        }
    }

    // MARK: courses
    @ViewBuilder private var courses: some View {
        let list = bot.study?.courses ?? []
        Section {
            if list.isEmpty {
                EmptyState(icon: "books.vertical", title: L("No courses yet")).row()
            } else {
                ForEach(list, id: \.id) { c in
                    NavigationLink(value: c.id) { courseRow(c) }
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.line)
                        .swipeActions(edge: .trailing) { courseActions(c) }
                        .contextMenu { courseActions(c) }
                }
            }
        }
    }

    @ViewBuilder private func courseActions(_ c: BotStudy.Course) -> some View {
        Button { nav.go(.focus(courseId: c.id)) } label: { Label(L("Focus"), systemImage: "timer") }.tint(Theme.focus)
        Button { query = ""; course = c.short; nav.studyPart = .deadlines } label: { Label(L("Deadlines"), systemImage: "list.bullet") }.tint(Theme.accent)
    }

    private func courseRow(_ c: BotStudy.Course) -> some View {
        let folder = Theme.folder(botShort: c.short)
        let open = StudyData.open(bot.study).filter { $0.a.course?.id == c.id }
        // Done/total over what the bot still lists: open + finished in assignments, plus the recently done ones.
        var seen = Set<String>()
        let mine = ((bot.study?.assignments ?? []) + (bot.study?.recentlyDone ?? []).map { var a = $0; a.done = true; return a })
            .filter { $0.course?.id == c.id && seen.insert($0.id).inserted }
        let done = mine.filter(\.done).count
        return HStack(spacing: 12) {
            CourseRing(progress: mine.isEmpty ? 0 : Double(done) / Double(mine.count), tint: Theme.course(folder), size: tile) {
                Image(systemName: Self.symbol(folder)).font(.body.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.course(folder), in: Circle())
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.title ?? c.short).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(2)
                if let next = open.first {
                    Text(L("Next: \(next.a.title) · \(StudyData.days(next.a.dueDate).map { Loc.dueLabel($0).text } ?? L("No date"))"))
                        .font(.meta).foregroundStyle(Theme.muted).lineLimit(1)
                } else {
                    Text(L("No open deadlines")).font(.meta).foregroundStyle(Theme.muted)
                }
                if !mine.isEmpty {
                    Text(L("\(done) of \(mine.count) done")).font(.chip).monospacedDigit().foregroundStyle(Theme.muted)
                }
                if c.aiPolicy == "banned" {
                    Chip(text: L("AI banned in assessments"), tone: .bad)
                } else if c.aiPolicy == "own_work" {
                    Chip(text: L("Assignments must be your own work"), tone: .warn)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 36

    /// One SF Symbol per course folder.
    private static func symbol(_ folder: String) -> String {
        let f = folder.lowercased()
        if f.contains("lab") { return "flask.fill" }
        if f.contains("phys") { return "atom" }
        if f.contains("cpp") || f.contains("code") || f.contains("prog") { return "chevron.left.forwardslash.chevron.right" }
        if f.contains("stat") || f.contains("prob") { return "dice.fill" }
        if f.contains("lang") || f.contains("chinese") { return "character.bubble.fill" }
        return "book.closed.fill"
    }
}

private extension View {
    /// A row that is only layout (title, buttons, filters): no card, no separator, edge to edge with the cards.
    func plainRow() -> some View {
        listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
    /// A content row on the card surface; the row draws its own padding.
    func row() -> some View {
        listRowBackground(Theme.surface).listRowSeparatorTint(Theme.line).listRowInsets(EdgeInsets())
    }
}
