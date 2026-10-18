import SwiftUI
import Charts

struct TodayView: View {
    @ObservedObject private var store = StudyStore.shared
    @ObservedObject private var bot = BotStore.shared
    @State private var items: [MarkdownTables.Item] = []
    @State private var notices: [[String: String]] = []
    @State private var error: String?
    @State private var sleep: SleepHistory?

    private var today: String { DeadlinesView.localToday() }
    private func days(_ it: MarkdownTables.Item) -> Int? { it.date.flatMap { Deadlines.days(from: today, to: $0) } }

    var body: some View {
        let sessions = (bot.study?.sessions ?? []).filter { $0.date == today }.sorted { $0.start < $1.start }
        let open = Deadlines.rows(items, study: bot.study).filter { !$0.done }
        let overdue = open.filter { (days($0.item) ?? 0) < 0 }.count
        let week = open.filter { d in days(d.item).map { $0 >= 0 && $0 <= 7 } ?? false }.count
        let soon = MarkdownTables.sorted(open.map(\.item)).compactMap { i in open.first { $0.id == i.id } }.prefix(6)
        let exams = MarkdownTables.sorted(items.filter { $0.kind == .exam }).filter { (days($0) ?? -1) >= 0 }
        let nextExam = exams.first.flatMap(days)
        let summary = [overdue > 0 ? "\(overdue) overdue" : nil, "\(week) due this week",
                       nextExam.map { "next exam in \($0) d" }].compactMap { $0 }.joined(separator: " · ")
        PageView(title: "Today", summary: summary) {
            VStack(alignment: .leading, spacing: 24) {
                if let error { ErrorBanner(text: error) { self.error = nil } }
                HStack(alignment: .top, spacing: 16) {
                    Stat(value: "\(overdue)", label: "Overdue", tone: overdue > 0 ? .bad : .neutral)
                    Stat(value: "\(week)", label: "Due in 7 days")
                    Stat(value: nextExam.map { "\($0) d" } ?? "—", label: "Next exam")
                }
                streaks
                countdown(ExamCountdown.upcoming(items, today: today))
                if let sleep, !sleep.nights.isEmpty { SleepWeek(history: sleep) }
                agenda(sessions)
                dueSoon(open, Array(soon))
                examsSection(exams)
                noticesSection
            }
        }
        .toolbar {
            if let s = bot.statusText { ToolbarItem(placement: .primaryAction) { Chip(text: "Offline", tone: .warn).help(s) } }
        }
        .task {
            // One small read for the week's sleep; without a token or a connection the card simply stays away.
            guard Router.shared.tokenPresent, let r = try? await BotAPI.raw("GET", "/sleep?days=7"), r.status == 200 else { return }
            sleep = try? JSONDecoder().decode(SleepHistory.self, from: r.data)
        }
        .task(id: store.tick) {
            items = DeadlineActions.loadItems()
            let rows = MarkdownTables.tables(readResource("notices.md")).first?.rows ?? []
            notices = Array(rows.filter { !(($0["title"] ?? "").isEmpty) }.enumerated()
                .sorted { ($0.element["date"] ?? "") != ($1.element["date"] ?? "") ? ($0.element["date"] ?? "") > ($1.element["date"] ?? "") : $0.offset < $1.offset }
                .map(\.element).prefix(5))
            SidebarBadges.shared.overdue = Deadlines.rows(items, study: bot.study).filter { !$0.done && (days($0.item) ?? 0) < 0 }.count
            await bot.refresh()
            SidebarBadges.shared.overdue = Deadlines.rows(items, study: bot.study).filter { !$0.done && (days($0.item) ?? 0) < 0 }.count
        }
    }

    /// Calm one-line streaks: focus days in a row and minutes this week (from the local focus log).
    @ViewBuilder private var streaks: some View {
        let streak = FocusStats.streak(bot.focusLog, today: today)
        let week = FocusStats.weekMinutes(bot.focusLog, today: today)
        Button { Router.shared.go(.focus(courseId: nil)) } label: {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? Theme.focus : Theme.muted)
                Text(streak > 0 ? "Focus streak: \(streak) \(streak == 1 ? "day" : "days")" : "No focus streak yet")
                    .font(.body13).foregroundStyle(Theme.text)
                Text("· \(FocusLogic.minutes(week)) this week").font(.body13).foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.meta).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help("Open Focus")
    }

    @ViewBuilder private func agenda(_ sessions: [BotStudy.Session]) -> some View {
                Section2(title: "Today", count: sessions.isEmpty ? nil : sessions.count) {
                    if sessions.isEmpty {
                        Group2 { EmptyState(icon: "sun.max", title: "No classes today",
                                            detail: bot.study == nil ? "The schedule appears when the bot is reachable." : nil) }
                    } else {
                        Group2 { Rows(items: sessions) { s in
                            RowButton {
                                HStack(spacing: 12) {
                                    Text("\(s.start)–\(s.end)").font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.muted)
                                        .frame(width: 96, alignment: .leading)
                                    Text((s.title ?? s.kind).replacingOccurrences(of: "Лаба", with: "Lab")).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(1)
                                    if let c = s.course { CourseTag(code: Theme.folder(botShort: c.short)) }
                                    Spacer(minLength: 8)
                                    if let r = s.room, !r.isEmpty { Text(r).font(.meta).foregroundStyle(Theme.muted) }
                                }
                            }
                        } }
                    }
                }
    }

    @ViewBuilder private func dueSoon(_ open: [Deadlines.Row], _ soon: [Deadlines.Row]) -> some View {
                Section2(title: "Due soon", count: open.isEmpty ? nil : open.count) {
                    if soon.isEmpty {
                        Group2 { EmptyState(icon: "checkmark.circle", title: "Nothing open", detail: "New homework appears after a sync from the chats.") }
                    } else {
                        Group2 { Rows(items: Array(soon)) { r in
                            RowButton(action: { Router.shared.go(.course(r.item.course)) }) {
                                HStack(spacing: 12) {
                                    Text(r.title).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(1)
                                    CourseTag(code: r.item.course)
                                    Spacer(minLength: 8)
                                    DueChip(date: r.item.date, today: today)
                                    Button("Done") { Task { error = await DeadlineActions.toggleWithUndo(r); items = DeadlineActions.loadItems() } }
                                        .buttonStyle(QuietButton())
                                    Image(systemName: "chevron.right").font(.meta).foregroundStyle(Theme.muted)
                                }
                            }.contextMenu { Button("Show in Deadlines") { Router.shared.focusDeadline = r.id; Router.shared.go(.study(.deadlines)) } }
                        } }
                    }
                }
    }

    @ViewBuilder private func countdown(_ cards: [ExamCountdown.Card]) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(cards, id: \.id) { c in
                    Button { Router.shared.go(.exam(c.id)) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.label).font(.bigNumber).monospacedDigit()
                                .foregroundStyle(c.days <= 3 ? Tone.bad.color : c.tentative ? Tone.warn.color : Theme.text)
                            Text(c.title).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(1)
                            HStack(spacing: 6) {
                                CourseTag(code: c.course)
                                Text(c.date).font(.meta).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(c.title), \(Theme.short(c.course)), \(c.label)")
                        .contextMenu {
                            Button("Prepare…") { if let e = items.first(where: { $0.id == c.id }) { Router.shared.prepExam = e } }
                        }
                }
            }
                Button("Prepare for \(cards[0].title)…") {
                    if let e = items.first(where: { $0.id == cards[0].id }) { Router.shared.prepExam = e }
                }.buttonStyle(QuietButton())
            }
        }
    }

    @ViewBuilder private func examsSection(_ exams: [MarkdownTables.Item]) -> some View {
                if !exams.isEmpty {
                    Section2(title: "Exams", count: exams.count) {
                        Group2 { Rows(items: exams) { e in
                            RowButton(action: { Router.shared.focusDeadline = e.id; Router.shared.page = .deadlines }) {
                                HStack(spacing: 12) {
                                    // The date in the column; the long note ("Tentative, week 8 …") on hover instead of cut off.
                                    Text(e.date ?? "—").font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.muted)
                                        .lineLimit(1).frame(width: 96, alignment: .leading)
                                    Text(e.title).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(1)
                                    CourseTag(code: e.course)
                                    if Deadlines.isTentative(e) { Chip(text: "Tentative", tone: .warn) }
                                    Spacer(minLength: 8)
                                    DueChip(date: e.date, today: today)
                                }.help(e.dueText)
                            }
                        } }
                    }
                }
    }

    @ViewBuilder private var noticesSection: some View {
                Section2(title: "New in chats") {
                    if notices.isEmpty {
                        Group2 { EmptyState(icon: "bell", title: "No notices yet", detail: "Teacher announcements show up here after a sync.") }
                    } else {
                        Group2 { Rows(items: notices.enumerated().map { NoticeLine(i: $0.offset, n: $0.element) }) { l in
                            RowButton(action: { Router.shared.page = .notices }) {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(String((l.n["date"] ?? "").dropFirst(5))).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.muted)
                                        .frame(width: 96, alignment: .leading)
                                    Text(Deadlines.shortText(MarkdownTables.clean(l.n["title"] ?? ""), limit: 110)).font(.body13)
                                        .foregroundStyle(Theme.text).lineLimit(2)
                                    Spacer(minLength: 8)
                                    CourseTag(code: MarkdownTables.clean(l.n["course"] ?? ""))
                                }
                            }
                        } }
                    }
                }
    }

    private struct NoticeLine: Identifiable { let i: Int; let n: [String: String]; var id: Int { i } }
}

/// Last 7 nights: hours asleep against the target, in the Sleep area colour.
private struct SleepWeek: View {
    let history: SleepHistory
    var body: some View {
        let sum = SleepLogic.summary(history)
        let target = Double(SleepLogic.targetSleep(history.target)) / 60
        Section2(title: "Sleep, 7 nights") {
            Group2 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        Stat(value: sum.avgAsleep.map { "\($0 / 60)h \($0 % 60)m" } ?? "—", label: "average asleep")
                        Stat(value: "\(sum.onTrack)/\(sum.nights)", label: "nights on track", tone: sum.onTrack * 2 >= sum.nights ? .good : .warn)
                    }
                    Chart {
                        ForEach(history.nights) { n in
                            BarMark(x: .value("Night", String(n.date.suffix(5))), y: .value("Hours", Double(n.asleepMin) / 60))
                                .foregroundStyle(Theme.sleep.opacity(n.verdict == "good" ? 1 : 0.55))
                                .cornerRadius(3)
                                .accessibilityLabel(n.date).accessibilityValue("\(n.asleepMin / 60) h \(n.asleepMin % 60) min, bed \(n.bed)")
                        }
                        RuleMark(y: .value("Target", target))
                            .foregroundStyle(Theme.muted).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .trailing) { Text("target").font(.chip).foregroundStyle(Theme.muted) }
                    }
                    .chartYAxis { AxisMarks(values: [0, 4, 8]) { AxisGridLine(); AxisValueLabel() } }
                    .frame(height: 110)
                }
                .padding(14)
            }
        }
        .overlay(alignment: .topTrailing) { Image(systemName: "chevron.right").font(.meta).foregroundStyle(Theme.muted).padding(4) }
        .contentShape(Rectangle())
        .onTapGesture { Router.shared.go(.life(.sleep)) }
        .help("Open Sleep")
    }
}
