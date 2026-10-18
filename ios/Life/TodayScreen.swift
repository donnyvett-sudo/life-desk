import SwiftUI

/// Today: the numbers that matter, exam countdowns, classes, what is due soon. Same blocks as the Mac page.
struct TodayScreen: View {
    @ObservedObject private var bot = BotStore.shared
    var onDisconnect: () -> Void = {}
    @State private var sleep: SleepHistory?
    @State private var food: FoodDay?
    @State private var money: FinanceMonth?
    @State private var habits: HabitsOverview?
    @AppStorage("focus.weekGoal") private var focusGoal = 600
    @AppStorage("money.hidden") private var moneyHidden = false

    var body: some View {
        let today = StudyData.today()
        let open = StudyData.open(bot.study)
        let overdue = open.filter { (StudyData.days($0.a.dueDate, today: today) ?? 0) < 0 }.count
        let week = open.filter { d in StudyData.days(d.a.dueDate, today: today).map { $0 >= 0 && $0 <= 7 } ?? false }.count
        let exams = StudyData.exams(bot.study, limit: 3)
        let classes = StudyData.classesToday(bot.study)
        PageView(title: L("Today"), summary: summary(overdue: overdue, week: week, next: exams.first), trailing: {
            if let s = bot.statusText { Chip(text: L("Offline"), tone: .warn).accessibilityHint(s) }
        }) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    Stat(value: "\(overdue)", label: L("Overdue"), tone: overdue > 0 ? .bad : .neutral)
                    Stat(value: "\(week)", label: L("Due in 7 days"))
                    Stat(value: exams.first.map { Loc.days($0.days) } ?? "—", label: L("Next exam"))
                }
                streaks(today: today)
                Section2(title: L("Tools")) {
                    FlowChips {
                        Button { Navigator.shared.go(.promises) } label: { Label(L("Promises"), systemImage: "hand.raised") }.buttonStyle(QuietButton())
                        Button { Navigator.shared.go(.account) } label: { Label(L("Account"), systemImage: "person.crop.circle") }.buttonStyle(QuietButton())
                    }
                }
                lifeCards(today: today)
                weekly(today: today)
                cardsLink
                badgeSection(today: today)
                if !exams.isEmpty { examCards(exams) }
                Section2(title: L("Classes today"), count: classes.isEmpty ? nil : classes.count) {
                    if classes.isEmpty {
                        Group2 { EmptyState(icon: "sun.max", title: L("No classes today"), detail: bot.study == nil ? L("The schedule appears when you are online.") : nil) }
                    } else {
                        Group2 { Rows(items: classes) { s in
                            HStack(spacing: 12) {
                                Text("\(s.start)–\(s.end)").font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.muted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((s.title ?? s.kind).replacingOccurrences(of: "Лаба", with: L("Lab"))).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(2)
                                    HStack(spacing: 6) {
                                        if let c = s.course { CourseTag(code: Theme.folder(botShort: c.short)) }
                                        if let r = s.room, !r.isEmpty { Text(r).font(.meta).foregroundStyle(Theme.muted) }
                                    }
                                }
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 14).padding(.vertical, 10)
                        } }
                    }
                }
                Section2(title: L("Due soon"), count: open.isEmpty ? nil : open.count) {
                    if open.isEmpty {
                        Group2 { EmptyState(icon: "checkmark.circle", title: L("Nothing open"), detail: L("New homework appears after a sync from your chats.")) }
                    } else {
                        Group2 { Rows(items: Array(open.prefix(6))) { r in DeadlineRow(row: r, today: today, openCourse: r.a.course?.id) } }
                        Button("All deadlines") { Navigator.shared.go(.study(.deadlines)) }.buttonStyle(QuietButton())
                    }
                }
            }
        }
        .celebrates()
        .refreshable { async let b: Void = bot.refresh(); async let l: Void = loadLife(); _ = await (b, l) }
        .task { await bot.refresh() }
        .task { await loadLife() }
    }

    // MARK: life cards
    /// Sleep, food and money for the day. Each loads on its own; a card whose request fails simply stays hidden.
    private func loadLife() async {
        async let sl = fetch(SleepHistory.self, "/sleep?days=14")
        async let hb = fetch(HabitsOverview.self, "/habits")
        async let fo = fetch(FoodDay.self, "/food")
        async let mo = fetch(FinanceMonth.self, "/finance?currency=\(UserDefaults.standard.string(forKey: "money.currency") ?? "CNY")")
        let (a, b, c, d) = await (sl, fo, mo, hb)
        sleep = a; food = b; money = c; habits = d
    }

    private func fetch<T: Decodable>(_ type: T.Type, _ path: String) async -> T? {
        guard let r = try? await BotAPI.raw("GET", path), r.status == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: r.data)
    }

    @ViewBuilder private func lifeCards(today: String) -> some View {
        let night = sleep?.nights.last
        let spent = money.map { m in m.transactions.filter { $0.kind == "expense" && $0.date == today }.reduce(0) { $0 + $1.amountDisplay } }
        let active = habits?.habits.filter(\.active) ?? []
        if night != nil || food != nil || spent != nil || !active.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                if let h = sleep, let n = night {
                    lifeCard(L("Sleep"), icon: "moon.stars.fill", tint: Theme.sleep, value: Loc.duration(n.asleepMin),
                             // An old night (no data since) says which night it is.
                             detail: "\(n.bed)–\(n.wake)" + (n.date >= (QuickEntry.add(days: -1, to: today) ?? today) ? "" : " · \(ChartFmt.md(n.date))")) {
                        MiniBars(values: h.nights.suffix(7).map { Double($0.asleepMin) }, tint: Theme.sleep)
                    }.cardLink(.life(.sleep))
                }
                if let f = food {
                    lifeCard(L("Food"), icon: "fork.knife", tint: Theme.food, value: L("\(Int(f.totals.kcal)) kcal"),
                             detail: L("of \(Int(f.targets.kcal)) kcal")) {
                        ProgressView(value: min(FoodLogic.share(f.totals.kcal, of: f.targets.kcal), 1)).tint(f.totals.kcal > f.targets.kcal ? Theme.warn : Theme.food)
                    }.cardLink(.life(.food))
                }
                if let m = money, let spent {
                    lifeCard(L("Spent today"), icon: "creditcard.fill", tint: Theme.money,
                             value: moneyHidden ? "•••" : FinanceLogic.money(spent, m.currency),
                             detail: moneyHidden ? L("This month") : L("This month \(FinanceLogic.money(m.expense, m.currency))")) {
                        MiniBars(values: lastWeek(m, today: today), tint: Theme.money)
                    }.cardLink(.life(.money))
                }
                if !active.isEmpty {
                    let done = active.filter(\.doneToday).count
                    lifeCard(L("Today's habits"), icon: "repeat", tint: Theme.accent, value: "\(done)/\(active.count)",
                             detail: done == active.count ? L("All done for today") : L("\(active.count - done) left today")) {
                        HStack { Ring(progress: Double(done) / Double(active.count), tint: Theme.accent, lineWidth: 4) { EmptyView() }.frame(width: 28, height: 28); Spacer() }
                    }.cardLink(.life(.habits))
                }
            }
        }
    }

    /// Expenses of the last 7 days (today last) from the month's transactions; days before the month count as 0.
    private func lastWeek(_ m: FinanceMonth, today: String) -> [Double] {
        (0..<7).reversed().map { back in
            let day = QuickEntry.add(days: -back, to: today) ?? ""
            return m.transactions.filter { $0.kind == "expense" && $0.date == day }.reduce(0) { $0 + $1.amountDisplay }
        }
    }

    private func lifeCard<Graph: View>(_ title: String, icon: String, tint: Color, value: String, detail: String, @ViewBuilder graph: () -> Graph) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.meta.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.bigNumber).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(Theme.text)
            Text(detail).font(.meta).foregroundStyle(Theme.muted).lineLimit(2)
            graph().frame(height: 28)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func summary(overdue: Int, week: Int, next: StudyData.ExamCard?) -> String {
        [overdue > 0 ? L("\(overdue) overdue") : nil, L("\(week) due this week"), next.map { L("next exam in \($0.days) d") }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func examCards(_ cards: [StudyData.ExamCard]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(cards) { c in
                    examCard(c)
                }
            }
        }
    }

    private func examCard(_ c: StudyData.ExamCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(c.label).font(.bigNumber).monospacedDigit()
                .foregroundStyle(c.days <= 3 ? Tone.bad.color : c.tentative ? Tone.warn.color : Theme.text)
            Text(c.title).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(1)
            HStack(spacing: 6) { CourseTag(code: Theme.folder(botShort: c.course)); Text(c.date).font(.meta).foregroundStyle(Theme.muted) }
        }
        .padding(12).frame(width: 220, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .cardLink(.exam(c.id)).accessibilityHint(L("Opens the preparation plan"))
    }

    // MARK: streaks, goals, badges
    private func streaks(today: String) -> some View {
        FlowChips {
            FlameChip(count: FocusStats.streak(bot.focusLog, today: today), label: L("focus"), tint: Theme.focus, route: .focus(courseId: nil))
            if habits != nil { FlameChip(count: Streaks.habit(habits), label: L("habits"), tint: Theme.accent, route: .life(.habits)) }
            if sleep != nil { FlameChip(count: Streaks.nights(sleep), label: L("nights"), tint: Theme.sleep, route: .life(.sleep)) }
        }
    }

    @ViewBuilder private func weekly(today: String) -> some View {
        let active = habits?.habits.filter(\.active) ?? []
        let last7 = sleep.map { Array($0.nights.suffix(7)) } ?? []
        WeeklyGoalsCard(focusMin: FocusStats.weekMinutes(bot.focusLog, today: today), focusGoal: focusGoal,
                        nightsOn: last7.filter { $0.verdict == "good" }.count, nights: last7.count,
                        habitsDone: active.filter(\.doneToday).count, habitsTotal: active.count)
    }

    private var cardsLink: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill").foregroundStyle(Theme.accent).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Chinese cards")).font(.rowTitle).foregroundStyle(Theme.text)
                Text(L("Today's session")).font(.meta).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.chip).foregroundStyle(Theme.muted).accessibilityHidden(true)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: Touch.minSize, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .linksTo(.cards).buttonStyle(CardLinkStyle())
    }

    private func badgeSection(today: String) -> some View {
        Section2(title: L("Badges")) {
            BadgeRow(badges: Badges.all(log: bot.focusLog, today: today, sleep: sleep, habits: habits, study: bot.study))
        }
    }
}

/// One deadline with its due chip and a Done button (Reopen for a finished one). In the Study list a swipe does the
/// same, so there the button only shows on accessibility text sizes.
struct DeadlineRow: View {
    let row: StudyData.DueRow
    let today: String
    var showButton = true
    var finished = false
    /// When set, tapping the title opens that course.
    var openCourse: String? = nil
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.a.title).font(.rowTitle).foregroundStyle(finished ? Theme.muted : Theme.text).strikethrough(finished).lineLimit(2)
            HStack(spacing: 6) {
                if !row.course.isEmpty { CourseTag(code: Theme.folder(botShort: row.course)) }
                if !finished { LocalDueChip(date: row.a.dueDate, today: today) }
            }
        }
    }
    var body: some View {
        HStack(spacing: 10) {
            if let c = openCourse {
                Button { Navigator.shared.go(.course(c)) } label: { titleBlock.frame(maxWidth: .infinity, minHeight: Touch.minSize, alignment: .leading).contentShape(Rectangle()) }
                    .buttonStyle(CardLinkStyle()).accessibilityHint(L("Opens the course"))
            } else {
                titleBlock
                Spacer(minLength: 8)
            }
            if showButton {
                Button(finished ? L("Reopen") : L("Done")) { Task { await Celebrate.deadline(id: row.a.id, done: !finished, title: row.a.title) } }
                    .buttonStyle(QuietButton())
                    .accessibilityLabel(finished ? L("Reopen \(row.a.title)") : L("Mark \(row.a.title) done"))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
