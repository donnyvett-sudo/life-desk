import SwiftUI
import Charts

/// Sleep: average, last-night details, a bar chart of the nights against the goal, bedtime drift.
struct SleepScreen: View {
    @State private var days = 14
    @State private var history: SleepHistory?
    @State private var selected: String?   // the night shown below; stays after the finger lifts
    @State private var scrub: String?      // the night under the finger right now
    @State private var error: String?
    @State private var logging = false

    var body: some View {
        PageView(title: L("Sleep"), summary: history.map { L("Goal \($0.target.bed)–\($0.target.wake)") }, trailing: {
            TodayChip()
            Button { logging = true } label: { Image(systemName: "plus.circle") }.accessibilityLabel(L("Log a night"))
            Picker("", selection: $days) { Text("14 d").tag(14); Text("30 d").tag(30) }.pickerStyle(.segmented).frame(width: 120)
        }) {
            VStack(alignment: .leading, spacing: 20) {
                if let error { ErrorBanner(text: error) { self.error = nil } }
                if let h = history { content(h) } else if error == nil { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            }
        }
        .refreshable { await load() }
        .task(id: days) { await load() }
        .sheet(isPresented: $logging) { LogNightSheet { Task { await load() } } }
        .onChange(of: scrub) { _, d in if let d { selected = d } }
    }

    private func load() async {
        let r: (status: Int, data: Data)
        do { r = try await BotAPI.raw("GET", "/sleep?days=\(days)") }
        catch is CancellationError { return }            // switching 14 d / 30 d cancels the old load: not an error
        catch { self.error = L("No connection."); return }
        guard r.status == 200 else { error = L("Could not load sleep (\(r.status))."); return }
        guard let h = try? JSONDecoder().decode(SleepHistory.self, from: r.data) else { error = L("The sleep data could not be read."); return }
        history = h; error = nil
    }

    @ViewBuilder private func content(_ h: SleepHistory) -> some View {
        let s = SleepLogic.summary(h)
        let goal = SleepLogic.targetSleep(h.target)
        let current = h.nights.first { $0.date == selected } ?? h.nights.last
        HStack(alignment: .top, spacing: 12) {
            Stat(value: s.avgAsleep.map(Loc.duration) ?? "—", label: L("average sleep"))
            Stat(value: s.avgBedDiff.map { Loc.bedDiff($0) } ?? "—", label: L("bedtime vs goal"))
            Stat(value: L("\(s.onTrack) of \(s.nights)"), label: L("on track"), tone: s.nights > 0 && s.onTrack * 2 >= s.nights ? .good : .neutral)
        }
        if h.nights.isEmpty {
            Group2 { EmptyState(icon: "moon.stars", title: L("No nights yet"), detail: L("Sleep arrives from Apple Health when you open the app in the morning.")) }
        } else {
            Section2(title: L("Duration")) {
                Chart {
                    ForEach(h.nights) { n in
                        BarMark(x: .value("Night", n.date), y: .value("Hours", Double(n.asleepMin) / 60))
                            .foregroundStyle(n.date == current?.date ? Theme.sleep : Theme.sleep.opacity(0.45))
                            .cornerRadius(3)
                            .accessibilityLabel(Loc.dayTitle(n.date, today: h.today))
                            .accessibilityValue(Loc.duration(n.asleepMin))
                    }
                    RuleMark(y: .value("Goal", Double(goal) / 60)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Theme.muted)
                        .accessibilityLabel(L("Goal")).accessibilityValue(Loc.duration(goal))
                    if let d = scrub, let n = h.nights.first(where: { $0.date == d }) {
                        RuleMark(x: .value("Night", d)).foregroundStyle(Theme.muted.opacity(0.35))
                            .annotation(position: .top, spacing: 0, overflowResolution: .inside) {
                                ChartCallout(value: Loc.duration(n.asleepMin), caption: ChartFmt.md(n.date))
                            }
                    }
                }
                .chartYScale(domain: 0...10)
                .chartYAxis { AxisMarks(values: [0, 4, 8]) { v in AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel { Text("\(v.as(Int.self) ?? 0) h").font(.chip).foregroundStyle(Theme.muted) } } }
                .chartXAxis { nightLabels(h) }
                .chartXSelection(value: $scrub)
                .frame(height: 170)
                Text("Dashed line is your goal. Touch a bar to open that night.").font(.meta).foregroundStyle(Theme.muted)
            }
            if let n = current { night(n, goal: goal, target: h.target) }
            Section2(title: L("Bed and wake times")) { times(h) }
        }
    }

    /// Every few nights only: 14 or 30 labels side by side run into each other.
    @AxisContentBuilder private func nightLabels(_ h: SleepHistory) -> some AxisContent {
        let step = h.nights.count > 16 ? 6 : 3
        AxisMarks(values: h.nights.enumerated().filter { $0.offset % step == 0 }.map(\.element.date)) { v in
            AxisValueLabel { if let d = v.as(String.self) { Text(ChartFmt.md(d)).font(.chip).lineLimit(1).fixedSize().foregroundStyle(Theme.muted) } }
        }
    }

    /// Hours since 18:00, so a night that crosses midnight is one unbroken bar (23:00 → 5, 07:00 → 13).
    private func since18(_ hhmm: String) -> Double? { SleepLogic.minutes(hhmm).map { Double((($0 - 18 * 60) + 1440) % 1440) / 60 } }

    /// Bed → wake as a range bar per night, the goal times dashed; earlier times on top.
    @ViewBuilder private func times(_ h: SleepHistory) -> some View {
        let spans = h.nights.compactMap { n -> (night: SleepHistory.Night, bed: Double, wake: Double)? in
            guard let b = since18(n.bed), let w = since18(n.wake), w > b else { return nil }
            return (n, b, w)
        }
        Chart {
            ForEach(spans, id: \.night.date) { s in
                BarMark(x: .value("Night", s.night.date), yStart: .value("Bed", s.bed), yEnd: .value("Wake", s.wake), width: .ratio(0.6))
                    .foregroundStyle(s.night.date == selected ? Theme.sleep : Theme.sleep.opacity(0.6))
                    .cornerRadius(3)
                    .accessibilityLabel(Loc.dayTitle(s.night.date, today: h.today))
                    .accessibilityValue("\(s.night.bed)–\(s.night.wake)")
            }
            ForEach([h.target.bed, h.target.wake].compactMap(since18), id: \.self) { t in
                RuleMark(y: .value("Goal", t)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxis { AxisMarks(values: .stride(by: 2)) { v in AxisGridLine().foregroundStyle(Theme.line)
            AxisValueLabel { if let x = v.as(Double.self) { Text(clock(Int(x * 60) + 18 * 60)).font(.chip).foregroundStyle(Theme.muted) } } } }
        .chartXAxis { nightLabels(h) }
        .chartXSelection(value: $scrub)
        .frame(height: 190)
    }

    private func clock(_ m: Int) -> String { let x = ((m % 1440) + 1440) % 1440; return String(format: "%02d:%02d", x / 60, x % 60) }

    private func night(_ n: SleepHistory.Night, goal: Int, target: SleepHistory.Target) -> some View {
        Section2(title: n.date) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Loc.duration(n.asleepMin)).font(.bigNumber).foregroundStyle(Theme.text)
                    Chip(text: n.verdict == "good" ? L("On track") : n.verdict == "meh" ? String(localized: "sleep.close", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : L("Off track"), tone: n.verdict == "good" ? .good : n.verdict == "meh" ? .warn : .bad)
                }
                ProgressView(value: Double(min(n.asleepMin, goal)), total: Double(max(goal, 1))).tint(Theme.sleep)
                HStack(spacing: 16) {
                    detail(L("Fell asleep"), n.bed); detail(L("Woke up"), n.wake)
                    if let d = n.deepMin { detail(L("Deep"), Loc.duration(d)) }
                    if let r = n.remMin { detail(L("REM"), Loc.duration(r)) }
                }
                ForEach(n.notes, id: \.self) { Text($0).font(.body13).foregroundStyle(Theme.muted) }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        }
    }

    private func detail(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(v).font(.rowTitle).foregroundStyle(Theme.text).monospacedDigit(); Text(k).font(.chip).foregroundStyle(Theme.muted) }
    }
}


/// /sleep 00:10 08:40 in the bot: a night by hand when the watch gave Health nothing.
struct LogNightSheet: View {
    var saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var bed = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var wake = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var earlier = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L("Went to bed"), selection: $bed, displayedComponents: .hourAndMinute)
                DatePicker(L("Woke up"), selection: $wake, displayedComponents: .hourAndMinute)
                Picker("", selection: $earlier) { Text(L("Last night")).tag(false); Text(L("The night before")).tag(true) }.pickerStyle(.segmented)
                if let error { Text(error).foregroundStyle(Theme.warn) }
            }
            .navigationTitle(L("Log a night")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("Save night")) { Task { await save() } } }
            }
        }
    }

    private func save() async {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        let body = try? JSONSerialization.data(withJSONObject: ["bed": f.string(from: bed), "wake": f.string(from: wake), "daysBack": earlier ? 1 : 0])
        if let r = try? await LifeAPI.raw("PUT", "/sleep", body: body), r.status == 200 {
            if let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any], let m = (j["messages"] as? [String])?.first { Toasts.shared.show(m) }
            saved(); dismiss()
        } else { error = L("Could not save the night.") }
    }
}
