import SwiftUI
import Charts

/// Study modes: pick a course or a free topic, set minutes, then a full-width countdown.
struct FocusView: View {
    @ObservedObject private var focus = FocusModel.shared
    @ObservedObject private var bot = BotStore.shared

    var body: some View {
        Group {
            switch focus.phase {
            case .idle: FocusSetup()
            case .running, .paused: FocusCountdown()
            case .finished(let m): FocusDone(minutes: m)
            }
        }
        .task { await focus.adoptIfRunning() }
    }
}

// MARK: Setup

private struct FocusSetup: View {
    @ObservedObject private var focus = FocusModel.shared
    @ObservedObject private var bot = BotStore.shared
    @State private var courseId: String? = nil          // nil = free topic
    @State private var topic = ""
    @State private var minutes = UserDefaults.standard.integer(forKey: "focus.minutes").nonZero(25)
    private let presets = [15, 25, 45, 60, 90, 120]

    private var courses: [BotStudy.Course] { bot.study?.courses ?? [] }
    private var picked: BotStudy.Course? { courses.first { $0.id == courseId } }
    private var stats: BotStudy.Focus? { bot.study?.focus }

    var body: some View {
        PageView(title: "Focus", summary: summary) {
            VStack(alignment: .leading, spacing: 24) {
                Section2(title: "What are you working on") {
                    FlowChips {
                        ForEach(courses, id: \.id) { c in
                            let code = Theme.folder(botShort: c.short)
                            Button { courseId = c.id } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(Theme.course(code)).frame(width: 7, height: 7)
                                    Text(Theme.short(code)).font(.chip)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(courseId == c.id ? Theme.accent : Theme.text)
                                .background(courseId == c.id ? Theme.accent.opacity(0.15) : Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                        FilterChip(title: "Free topic", on: courseId == nil) { courseId = nil }
                    }
                    DeskTextField(prompt: courseId == nil ? "What is it? (e.g. Reading about PID control)" : "Optional note: what exactly?", text: $topic)
                    if let p = picked, CourseInfo.policy(Theme.folder(botShort: p.short))?.tone == .bad {
                        Banner(icon: "exclamationmark.shield", text: "\(p.short) bans AI in assessments: this timer is for your own work.", tone: .bad)
                    }
                }
                Section2(title: "How long") {
                    FlowChips {
                        ForEach(presets, id: \.self) { m in FilterChip(title: "\(m) min", on: minutes == m) { minutes = m } }
                    }
                    HStack(spacing: 10) {
                        Stepper(value: $minutes, in: 5...180, step: 5) { Text("\(FocusLogic.minutes(minutes))").font(.rowTitle).monospacedDigit() }
                            .frame(maxWidth: 220)
                        Text("Ends at \(endTime)").font(.meta).foregroundStyle(Theme.muted)
                    }
                }
                if let e = focus.error { ErrorBanner(text: e) { focus.error = nil } }
                Button { start() } label: {
                    Text(focus.busy ? "Starting…" : "Start \(minutes) min").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton()).disabled(focus.busy).keyboardShortcut(.return, modifiers: .command)
                DisclosureGroup("Customize clock") {
                    FocusClockSettings(course: picked.map { Theme.folder(botShort: $0.short) })
                }.font(.body13).foregroundStyle(Theme.muted)
                FocusActivity(log: bot.focusLog)
                if let s = stats, !s.byCourse.isEmpty {
                    Section2(title: "This week") {
                        Group2 {
                            let total = max(1, s.byCourse.map(\.minutes).max() ?? 1)
                            ForEach(Array(s.byCourse.sorted { $0.minutes > $1.minutes }.enumerated()), id: \.offset) { i, row in
                                if i > 0 { Hairline() }
                                HStack(spacing: 12) {
                                    let code = row.course.map { Theme.folder(botShort: $0.short) } ?? ""
                                    if code.isEmpty { Text("Free topics").font(.body13).foregroundStyle(Theme.muted).frame(width: 130, alignment: .leading) }
                                    else { CourseTag(code: code).frame(width: 130, alignment: .leading) }
                                    GeometryReader { g in
                                        RoundedRectangle(cornerRadius: 3).fill(Theme.focus.opacity(0.8))
                                            .frame(width: max(3, g.size.width * CGFloat(row.minutes) / CGFloat(total)), height: 6)
                                            .frame(maxHeight: .infinity, alignment: .center)
                                    }.frame(height: 14)
                                    Text(FocusLogic.minutes(row.minutes)).font(.meta).monospacedDigit().foregroundStyle(Theme.muted)
                                        .frame(width: 80, alignment: .trailing)
                                }.padding(.horizontal, 14).padding(.vertical, 9)
                            }
                        }
                    }
                }
            }
        }
        .task { await bot.refresh() }
        .onAppear { applyRoute() }
        .onChange(of: Router.shared.focusCourse) { applyRoute() }
    }

    private func applyRoute() {
        if let c = Router.shared.focusCourse { courseId = c; Router.shared.focusCourse = nil }
    }

    private var summary: String {
        guard let s = stats else { return "Pick what you're working on, set the time, and go." }
        return "Today \(FocusLogic.minutes(s.todayMin)) · this week \(FocusLogic.minutes(s.weekMin))"
    }
    private var endTime: String {
        DateFmt.clock(Date().addingTimeInterval(Double(minutes) * 60))
    }
    private func start() {
        UserDefaults.standard.set(minutes, forKey: "focus.minutes")
        Task { await focus.start(course: picked, topic: topic, minutes: minutes) }
    }
}

private extension Int { func nonZero(_ d: Int) -> Int { self == 0 ? d : self } }

// MARK: Countdown (full width, nothing else on screen)

private struct FocusCountdown: View {
    @ObservedObject private var focus = FocusModel.shared
    @ObservedObject private var styles = FocusStyleStore.shared
    @State private var confirmStop = false

    var body: some View {
        let s = styles.style
        GeometryReader { g in
            ZStack(alignment: .leading) {
                s.backdropColor(course: focus.courseCode)
                if s.progress == .fill {
                    Rectangle().fill(Theme.accent.opacity(0.12)).frame(width: g.size.width * focus.progress)
                }
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(s.text(remaining: focus.remaining))
                        .font(s.font(size: max(60, min(g.size.width * (s.format == .minutes ? 0.45 : 0.27), g.size.height * 0.5)) * s.size))
                        .monospacedDigit().minimumScaleFactor(0.3).lineLimit(1)
                        .foregroundStyle(s.color(course: focus.courseCode))
                        .opacity(focus.phase == .paused ? 0.5 : 1)
                        .accessibilityLabel("\(FocusLogic.clock(focus.remaining)) left")
                    if focus.phase == .paused {
                        Text("Paused").font(.sectionLabel).textCase(.uppercase).foregroundStyle(Theme.warn).padding(.top, 4)
                    }
                    if s.format == .minutes { Text("minutes left").font(.body13).foregroundStyle(Theme.muted) }
                    if s.showLabel {
                        HStack(spacing: 8) {
                            if let code = focus.courseCode { Circle().fill(Theme.course(code)).frame(width: 9, height: 9) }
                            Text(focus.label).font(.system(size: 24, weight: .medium, design: .serif)).foregroundStyle(Theme.text)
                        }.padding(.top, 8)
                    }
                    if s.showEnd {
                        Text("until \(endClock) · \(FocusLogic.minutes(focus.plannedMin))").font(.body13).foregroundStyle(Theme.muted).padding(.top, 6)
                    }
                    Spacer(minLength: 0)
                    if s.progress == .bar {
                        ProgressView(value: focus.progress).progressViewStyle(.linear).tint(Theme.accent).padding(.horizontal, 48)
                    }
                    HStack(spacing: 12) {
                        if confirmStop {
                            Text("End now? The minutes so far still count.").font(.body13).foregroundStyle(Theme.muted)
                            Button("End session") { Task { await focus.stop() } }.buttonStyle(PrimaryButton())
                            Button("Keep going") { confirmStop = false }.buttonStyle(QuietButton())
                        } else if focus.phase == .paused {
                            Button("Resume") { Task { await focus.resume() } }.buttonStyle(PrimaryButton())
                            Button("End session") { confirmStop = true }.buttonStyle(QuietButton())
                        } else {
                            Button("Pause") { Task { await focus.pause() } }.buttonStyle(QuietButton())
                            Button("Stop") { confirmStop = true }.buttonStyle(QuietButton())
                        }
                    }.padding(.vertical, 24).disabled(focus.busy)
                        .background(
                            // Keyboard: Space pause/resume, Esc ask to end (again = keep going), ⌘. ask to end.
                            Group {
                                Button("") { if !confirmStop && !focus.busy { Task { focus.phase == .paused ? await focus.resume() : await focus.pause() } } }
                                    .keyboardShortcut(.space, modifiers: [])
                                Button("") { if !focus.busy { confirmStop.toggle() } }.keyboardShortcut(.cancelAction)
                                Button("") { if !focus.busy { confirmStop = true } }.keyboardShortcut(".", modifiers: .command)
                            }.opacity(0).frame(width: 0, height: 0).accessibilityHidden(true))
                    Text("Space pause · Esc end").font(.meta).foregroundStyle(Theme.muted).padding(.bottom, 12)
                }
                .frame(width: g.size.width, height: g.size.height)
            }
        }
    }

    private var endClock: String {
        DateFmt.clock(focus.endDate)
    }
}

// MARK: Done

private struct FocusDone: View {
    let minutes: Int
    @ObservedObject private var focus = FocusModel.shared
    @ObservedObject private var bot = BotStore.shared
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.system(size: 54)).foregroundStyle(Theme.good)
            Text("\(FocusLogic.minutes(minutes)) done").font(.system(size: 44, weight: .semibold, design: .serif)).foregroundStyle(Theme.text)
            Text(focus.label).font(.rowTitle).foregroundStyle(Theme.muted)
            if let t = bot.study?.focus?.todayMin { Text("Today in total: \(FocusLogic.minutes(t))").font(.body13).foregroundStyle(Theme.muted) }
            if let e = focus.error { Text(e).font(.meta).foregroundStyle(Theme.warn).multilineTextAlignment(.center).padding(.horizontal, 40) }
            Button("Back to Focus") { focus.reset() }.buttonStyle(PrimaryButton()).padding(.top, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
        .task { await bot.refresh() }
    }
}

// MARK: Small shared bits

/// Wrapping row of chips.
struct DeskTextField: View {
    let prompt: String
    @Binding var text: String
    var body: some View {
        TextField(prompt, text: $text).textFieldStyle(.plain).font(.body13).foregroundStyle(Theme.text)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
    }
}


// MARK: Clock style

extension FocusStyle {
    func font(size: CGFloat) -> Font {
        let w: Font.Weight = switch weight { case .ultraLight: .ultraLight; case .light: .light; case .regular: .regular; case .bold: .bold }
        let d: Font.Design = switch face { case .serif: .serif; case .sans: .default; case .mono: .monospaced; case .rounded: .rounded }
        return .system(size: size, weight: w, design: d)
    }
    func color(course: String?) -> Color {
        switch tint {
        case .text: Theme.text
        case .accent: Theme.accent
        case .course: course.map { Theme.course($0) } ?? Theme.accent
        case .custom: Color(hex: customHex) ?? Theme.accent
        }
    }
    @ViewBuilder func backdropColor(course: String?) -> some View {
        switch backdrop {
        case .standard: Theme.bg
        case .black: Color.black
        case .tinted: ZStack { Theme.bg; (course.map { Theme.course($0) } ?? Theme.accent).opacity(0.10) }
        }
    }
}

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

private struct FocusClockSettings: View {
    let course: String?
    @ObservedObject private var store = FocusStyleStore.shared

    var body: some View {
        Section2(title: "Clock") {
            Group2 {
                // Live preview with the current style.
                ZStack {
                    store.style.backdropColor(course: course)
                    VStack(spacing: 4) {
                        Text(store.style.text(remaining: 24 * 60 + 7))
                            .font(store.style.font(size: 72 * store.style.size)).monospacedDigit()
                            .foregroundStyle(store.style.color(course: course)).lineLimit(1).minimumScaleFactor(0.4)
                        if store.style.showLabel { Text(course.map { Theme.short($0) } ?? "Free topic").font(.rowTitle).foregroundStyle(Theme.text) }
                    }.padding(.vertical, 18)
                }
                .frame(height: 150).frame(maxWidth: .infinity)
                Hairline()
                row("Typeface") { pick($store.style.face, FocusStyle.Face.allCases) { $0.rawValue } }
                Hairline()
                row("Weight") { pick($store.style.weight, FocusStyle.Weight.allCases) { $0.rawValue } }
                Hairline()
                row("Size") { Slider(value: $store.style.size, in: 0.5...1.0).frame(maxWidth: 220) }
                Hairline()
                row("Digits") { pick($store.style.format, FocusStyle.Format.allCases) { $0.rawValue } }
                Hairline()
                row("Colour") {
                    HStack(spacing: 8) {
                        pick($store.style.tint, FocusStyle.Tint.allCases) { $0.rawValue }
                        if store.style.tint == .custom {
                            ColorPicker("", selection: Binding(get: { Color(hex: store.style.customHex) ?? Theme.accent },
                                                               set: { store.style.customHex = $0.hexString }), supportsOpacity: false).labelsHidden()
                        }
                    }
                }
                Hairline()
                row("Background") { pick($store.style.backdrop, FocusStyle.Backdrop.allCases) { $0.rawValue } }
                Hairline()
                row("Progress") { pick($store.style.progress, FocusStyle.Progress.allCases) { $0.rawValue } }
                Hairline()
                row("Show") {
                    HStack(spacing: 14) {
                        Toggle("Name", isOn: $store.style.showLabel)
                        Toggle("End time", isOn: $store.style.showEnd)
                    }.toggleStyle(.checkbox).font(.body13)
                }
                Hairline()
                row("When finished") {
                    HStack(spacing: 10) {
                        Picker("", selection: $store.style.sound) { ForEach(FocusStyle.sounds, id: \.self) { Text($0).tag($0) } }
                            .labelsHidden().frame(width: 130)
                        Button("Play") { if store.style.sound != "None" { NSSound(named: NSSound.Name(store.style.sound))?.play() } }
                            .buttonStyle(QuietButton())
                    }
                }
                Hairline()
                row("Full screen") { Toggle("Enter full screen when I start", isOn: $store.style.autoFullScreen).toggleStyle(.checkbox).font(.body13) }
            }
            HStack {
                Spacer()
                Button("Reset clock") { store.style = FocusStyle() }.buttonStyle(QuietButton())
            }
        }
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.body13).foregroundStyle(Theme.muted).frame(width: 110, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }.padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func pick<T: Hashable>(_ binding: Binding<T>, _ all: [T], _ title: @escaping (T) -> String) -> some View {
        FlowChips { ForEach(all, id: \.self) { v in FilterChip(title: title(v), on: binding.wrappedValue == v) { binding.wrappedValue = v } } }
    }
}

// MARK: Activity (heatmap, streak, weekly goal)

private struct FocusActivity: View {
    let log: FocusLog
    @AppStorage("focus.weekGoal") private var goal = 600
    @State private var hovered: FocusStats.Cell?

    var body: some View {
        let today = DateFmt.today()
        let week = FocusStats.weekMinutes(log, today: today)
        let streak = FocusStats.streak(log, today: today)
        let cols = FocusStats.heatmap(log, today: today)
        Section2(title: "Activity") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    Stat(value: "\(streak)", label: streak == 1 ? "day streak" : "days streak", tone: streak > 0 ? .good : .neutral)
                    Stat(value: FocusLogic.minutes(week), label: "this week")
                }
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(min(week, goal)), total: Double(max(goal, 1))).tint(week >= goal ? Theme.good : Theme.focus)
                    HStack {
                        Text(week >= goal ? "Weekly goal reached" : "\(FocusLogic.minutes(goal - week)) to the weekly goal")
                            .font(.meta).foregroundStyle(Theme.muted)
                        Spacer()
                        Stepper("Goal \(FocusLogic.minutes(goal))", value: $goal, in: 60...3000, step: 60).font(.meta)
                            .fixedSize()
                    }
                }
                // 12 weeks × 7 days, Monday on top, oldest week on the left; colour = the Focus area colour by level.
                Chart {
                    ForEach(cols.indices, id: \.self) { w in
                        ForEach(Array(cols[w].enumerated()), id: \.element.day) { d, c in
                            RectangleMark(x: .value("Week", w), y: .value("Day", 6 - d), width: .fixed(14), height: .fixed(14))
                                .cornerRadius(2)
                                .accessibilityLabel(c.day).accessibilityValue(FocusLogic.minutes(c.minutes))
                                .foregroundStyle(c.level == 0 ? Theme.surface2.opacity(c.future ? 0.25 : 0.8) : Theme.focus.opacity(0.25 + 0.2 * Double(c.level)))
                        }
                    }
                }
                .chartXScale(domain: -0.5...(Double(max(cols.count, 1)) - 0.5))
                .chartYScale(domain: -0.5...6.5)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [6, 4, 2]) { v in
                        AxisValueLabel { Text(["", "", "Fri", "", "Wed", "", "Mon"][v.as(Int.self) ?? 0]).font(.chip) }
                    }
                }
                .chartXAxis(.hidden)
                .chartPlotStyle { $0.frame(width: CGFloat(cols.count) * 17, height: 7 * 17) }
                .chartOverlay { proxy in
                    GeometryReader { g in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                guard case .active(let pt) = phase, let frame = proxy.plotFrame.map({ g[$0] }),
                                      let w: Int = proxy.value(atX: pt.x - frame.minX, as: Double.self).map({ Int($0.rounded()) }),
                                      let d: Int = proxy.value(atY: pt.y - frame.minY, as: Double.self).map({ 6 - Int($0.rounded()) }),
                                      cols.indices.contains(w), (0..<cols[w].count).contains(d) else { hovered = nil; return }
                                hovered = cols[w][d]
                            }
                    }
                }
                .fixedSize()
                .accessibilityLabel("Focus activity, last 12 weeks. Streak \(streak) days, this week \(FocusLogic.minutes(week)).")
                Text(hovered.map { $0.future ? $0.day : "\($0.day): \(FocusLogic.minutes($0.minutes))" } ?? " ")
                    .font(.meta).monospacedDigit().foregroundStyle(Theme.muted).accessibilityHidden(true)
                Text("History starts when Life Desk first saw your sessions; days before that are empty.")
                    .font(.meta).foregroundStyle(Theme.muted)
            }
        }
    }
}
