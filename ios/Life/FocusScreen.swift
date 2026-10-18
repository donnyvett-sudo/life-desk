import SwiftUI
import UIKit
import Charts

/// Focus: pick what you work on and for how long, then a big countdown that keeps the screen awake.
struct FocusScreen: View {
    @ObservedObject private var focus = FocusModel.shared
    @ObservedObject private var bot = BotStore.shared
    @State private var courseId: String?
    /// `courseId`: preselect a course (the Courses list's "Focus" swipe).
    init(courseId: String? = nil) { _courseId = State(initialValue: courseId) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topic = ""
    @State private var minutes = UserDefaults.standard.integer(forKey: "focus.minutes") == 0 ? 25 : UserDefaults.standard.integer(forKey: "focus.minutes")
    @State private var confirmStop = false
    private let presets = [15, 25, 45, 60, 90]

    var body: some View {
        Group {
            switch focus.phase {
            case .idle: setup
            case .running, .paused: countdown
            case .finished(let m): done(m)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // fill the whole cover, not just the content
        .background(Theme.bg.ignoresSafeArea())
        .task { await bot.refresh(); await focus.adoptIfRunning() }
        .onChange(of: focus.immersive) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = focus.immersive }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: setup
    private var courses: [BotStudy.Course] { bot.study?.courses ?? [] }
    private var picked: BotStudy.Course? { courses.first { $0.id == courseId } }

    private var setup: some View {
        PageView(title: L("Focus"), summary: summary, trailing: { EmptyView() }) {
            VStack(alignment: .leading, spacing: 20) {
                Section2(title: L("What are you working on")) {
                    FlowChips {
                        ForEach(courses, id: \.id) { c in
                            let code = Theme.folder(botShort: c.short)
                            Button { courseId = c.id } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(Theme.course(code)).frame(width: 7, height: 7)
                                    Text(Theme.short(code)).font(.chip)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .foregroundStyle(courseId == c.id ? Theme.accent : Theme.text)
                                .background(courseId == c.id ? Theme.accent.opacity(0.15) : Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                        FilterChip(title: L("Free topic"), on: courseId == nil) { courseId = nil }
                    }
                    TextField(courseId == nil ? L("What is it? (e.g. Reading about PID control)") : L("Optional note"), text: $topic)
                        .padding(12).background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    if let p = picked, AIPolicy.level(course: Theme.folder(botShort: p.short), info: StudyDocsStore.shared.courseInfo[Theme.folder(botShort: p.short)]) == .bad {
                        Banner(icon: "exclamationmark.shield", text: L("AI is banned in assessments here: this timer is for your own work."), tone: .bad)
                    }
                }
                Section2(title: L("How long")) {
                    FlowChips { ForEach(presets, id: \.self) { m in FilterChip(title: L("\(m) min"), on: minutes == m) { minutes = m } } }
                    Stepper(value: $minutes, in: 5...180, step: 5) { Text(Loc.minutes(minutes)).font(.rowTitle).monospacedDigit() }
                    Text("Ends at \(DateFmt.clock(Date().addingTimeInterval(Double(minutes) * 60)))").font(.meta).foregroundStyle(Theme.muted)
                }
                if let e = focus.error { ErrorBanner(text: AppLanguage.tr(e)) { focus.error = nil } }
                Button { start() } label: { Text(focus.busy ? L("Starting…") : L("Start \(minutes) min")).frame(maxWidth: .infinity).padding(.vertical, 4) }
                    .buttonStyle(PrimaryButton()).disabled(focus.busy)
                FocusActivityCard(log: bot.focusLog)
            }
        }
    }

    private var summary: String {
        guard let s = bot.study?.focus else { return L("Pick what you work on, set the time, and go.") }
        return L("Today \(Loc.minutes(s.todayMin)) · this week \(Loc.minutes(s.weekMin))")
    }

    private func start() {
        UserDefaults.standard.set(minutes, forKey: "focus.minutes")
        Task { await focus.start(course: picked, topic: topic, minutes: minutes) }
    }

    // MARK: countdown
    private var countdown: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 10)
                Circle().trim(from: 0, to: focus.progress).stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90)).animation(reduceMotion ? nil : .linear(duration: 0.25), value: focus.progress)
                VStack(spacing: 6) {
                    Text(FocusLogic.clock(focus.remaining)).font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.text).opacity(focus.phase == .paused ? 0.6 : 1).minimumScaleFactor(0.5)
                        .accessibilityLabel("\(FocusLogic.clock(focus.remaining)) left")
                    if focus.phase == .paused { Text("PAUSED").font(.sectionLabel).tracking(1).foregroundStyle(Theme.warn) }
                }
            }.frame(width: 280, height: 280)
            if !focus.label.isEmpty {
                HStack(spacing: 8) {
                    if let code = focus.courseCode { Circle().fill(Theme.course(code)).frame(width: 9, height: 9) }
                    Text(AppLanguage.tr(focus.label)).font(.system(size: 22, weight: .medium, design: .serif)).foregroundStyle(Theme.text)
                }
            }
            Text("until \(DateFmt.clock(focus.endDate)) · \(Loc.minutes(focus.plannedMin))").font(.body13).foregroundStyle(Theme.muted)
            if let e = focus.error { Text(AppLanguage.tr(e)).font(.meta).foregroundStyle(Theme.warn).multilineTextAlignment(.center).padding(.horizontal) }
            Spacer()
            HStack(spacing: 12) {
                if confirmStop {
                    Button("Keep going") { confirmStop = false }.buttonStyle(QuietButton())
                    Button("End session") { confirmStop = false; Task { await focus.stop() } }.buttonStyle(PrimaryButton())
                } else if focus.phase == .paused {
                    Button("Resume") { Task { await focus.resume() } }.buttonStyle(PrimaryButton())
                    Button("End") { confirmStop = true }.buttonStyle(QuietButton())
                } else {
                    Button("Pause") { Task { await focus.pause() } }.buttonStyle(QuietButton())
                    Button("Stop") { confirmStop = true }.buttonStyle(QuietButton())
                }
            }.disabled(focus.busy)
            if confirmStop { Text("The minutes so far still count.").font(.meta).foregroundStyle(Theme.muted) }
            Spacer().frame(height: 24)
        }.padding()
    }

    private func done(_ m: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(Theme.good)
            Text("\(Loc.minutes(m)) of focus").font(.system(size: 30, weight: .semibold, design: .serif)).foregroundStyle(Theme.text)
            Text("Saved to your week.").font(.body13).foregroundStyle(Theme.muted)
            Button("Done") { focus.reset(); Task { await bot.refresh() } }.buttonStyle(PrimaryButton()).padding(.horizontal, 40)
            Spacer()
        }.padding()
    }
}

/// Streak, weekly goal and a 12-week activity map from the daily log the app keeps.
struct FocusActivityCard: View {
    let log: FocusLog
    @AppStorage("focus.weekGoal") private var goal = 600

    var body: some View {
        let today = DateFmt.today()
        let week = FocusStats.weekMinutes(log, today: today)
        let streak = FocusStats.streak(log, today: today)
        let cols = FocusStats.heatmap(log, today: today)
        Section2(title: L("Activity")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Stat(value: "\(streak)", label: streak == 1 ? L("day streak") : L("days streak"), tone: streak > 0 ? .good : .neutral)
                    Stat(value: Loc.minutes(week), label: L("this week"))
                }
                ProgressView(value: Double(min(week, goal)), total: Double(max(goal, 1))).tint(week >= goal ? Theme.good : Theme.focus)
                HStack {
                    Text(week >= goal ? L("Weekly goal reached") : L("\(Loc.minutes(goal - week)) to the weekly goal")).font(.meta).foregroundStyle(Theme.muted)
                    Spacer()
                    Stepper("Goal \(Loc.minutes(goal))", value: $goal, in: 60...3000, step: 60).font(.meta).fixedSize()
                }
                heatmap(cols, today: today)
                    .accessibilityLabel("Focus activity, last 12 weeks. Streak \(streak) days, this week \(Loc.minutes(week)).")
            }
        }
    }

    /// Weeks left to right (oldest first), Monday on top; deeper teal = more minutes (levels 30 / 60 / 120 min).
    private func heatmap(_ cols: [[FocusStats.Cell]], today: String) -> some View {
        var cal = Calendar(identifier: .gregorian); cal.locale = AppLanguage.locale
        let sym = cal.shortStandaloneWeekdaySymbols
        let names = Array(sym.dropFirst()) + [sym[0]]          // Monday first
        return Chart {
            ForEach(cols.indices, id: \.self) { w in
                ForEach(cols[w].indices, id: \.self) { d in
                    let c = cols[w][d]
                    RectangleMark(x: .value("Week", String(w)), y: .value("Weekday", names[d % 7]), width: .ratio(0.86), height: .ratio(0.86))
                        .foregroundStyle(c.level == 0 ? Theme.surface2.opacity(c.future ? 0.3 : 1) : Theme.focus.opacity([0.3, 0.5, 0.75, 1][min(c.level, 4) - 1]))
                        .cornerRadius(2)
                        .accessibilityLabel(Loc.dayTitle(c.day, today: today))
                        .accessibilityValue(c.future ? "" : Loc.minutes(c.minutes))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .leading, values: [names[0], names[2], names[4]]) { _ in AxisValueLabel().font(.chip).foregroundStyle(Theme.muted) } }
        .chartLegend(.hidden)
        .frame(height: 170)
    }
}
