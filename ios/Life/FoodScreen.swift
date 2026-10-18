import SwiftUI
import Charts

/// Food: today's calories and macros against the targets, the meals, a week of calories, a camera shortcut.
struct FoodScreen: View {
    @State private var day: FoodDay?
    @State private var history: FoodHistory?
    @State private var date: String?
    @State private var error: String?
    @State private var camera = false
    @State private var note: String?
    @State private var scrub: String?
    // Rings grow with Dynamic Type, capped so three still fit across a phone.
    @ScaledMetric(relativeTo: .title) private var bigBase: CGFloat = 128
    @ScaledMetric(relativeTo: .caption) private var smallBase: CGFloat = 56
    private var big: CGFloat { min(bigBase, 190) }
    private var small: CGFloat { min(smallBase, 90) }

    var body: some View {
        PageView(title: L("Food"), summary: day.map { Loc.remaining($0).text }, trailing: {
            TodayChip()
            Button { camera = true } label: { Label("Photo", systemImage: "camera") }.buttonStyle(QuietButton())
        }) {
            VStack(alignment: .leading, spacing: 20) {
                if let error { ErrorBanner(text: error) { self.error = nil } }
                if let note { Banner(icon: "fork.knife", text: note, tone: .warn) }
                if let d = day { content(d) } else if error == nil { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $camera) {
            CameraPicker { data in Task { await sendPhoto(data) } }
        }
    }

    private func load() async {
        let q = date.map { "?date=\($0)" } ?? ""
        guard let r = try? await BotAPI.raw("GET", "/food\(q)") else { error = L("No connection."); return }
        guard r.status == 200, let d = try? JSONDecoder().decode(FoodDay.self, from: r.data) else { error = L("Could not load food (\(r.status))."); return }
        day = d; error = nil
        if let h = try? await BotAPI.raw("GET", "/food/history?days=7"), h.status == 200 { history = try? JSONDecoder().decode(FoodHistory.self, from: h.data) }
    }

    private func sendPhoto(_ jpeg: Data) async {
        note = L("Counting…")
        let body = try? JSONSerialization.data(withJSONObject: ["image": jpeg.base64EncodedString()])
        if let r = try? await LifeAPI.raw("POST", "/meals/photo", body: body), r.status == 200 {
            note = QuickEntryModel.render(r.data)
            await load()
        } else { note = L("Could not count that photo. Try again closer and in good light.") }
    }

    @ViewBuilder private func content(_ d: FoodDay) -> some View {
        let rem = Loc.remaining(d)
        Section2(title: L("Day total")) {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Ring(progress: FoodLogic.share(d.totals.kcal, of: d.targets.kcal), tint: rem.over ? Theme.warn : Theme.food, lineWidth: 12) {
                        VStack(spacing: 0) {
                            Text(verbatim: "\(Int(d.totals.kcal))").font(.bigNumber).monospacedDigit().foregroundStyle(Theme.text)
                            Text("of \(Int(d.targets.kcal)) kcal").font(.chip).foregroundStyle(Theme.muted)
                        }.lineLimit(1).minimumScaleFactor(0.5).padding(16)
                    }
                    .frame(width: big, height: big)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("Calories")).accessibilityValue(L("\(Int(d.totals.kcal)) of \(Int(d.targets.kcal)) kcal"))
                    Spacer(minLength: 0)
                    Chip(text: rem.text, tone: rem.over ? .warn : .good)
                }
                HStack(alignment: .top, spacing: 8) {
                    macro(L("Protein"), d.totals.protein, d.targets.protein)
                    macro(L("Fat"), d.totals.fat, d.targets.fat)
                    macro(L("Carbs"), d.totals.carbs, d.targets.carbs)
                }
            }
            .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        }
        Section2(title: L("Meals"), count: d.meals.isEmpty ? nil : d.meals.count) {
            if d.meals.isEmpty {
                Group2 { EmptyState(icon: "fork.knife", title: L("Nothing logged yet"), detail: L("Take a photo of your plate, or type «съел 2 яйца и банан» in Quick entry.")) }
            } else {
                Group2 { Rows(items: d.meals) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(m.title).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(2)
                            Spacer()
                            Text("\(Int(m.kcal))").font(.rowTitle).monospacedDigit().foregroundStyle(Theme.text)
                        }
                        HStack(spacing: 10) {
                            Text(m.time).font(.meta).foregroundStyle(Theme.muted)
                            Text("P \(Int(m.protein)) · F \(Int(m.fat)) · C \(Int(m.carbs))").font(.meta).foregroundStyle(Theme.muted).monospacedDigit()
                            if m.status == "pending" { Chip(text: L("to confirm"), tone: .warn) }
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 10).accessibilityElement(children: .combine)
                } }
            }
        }
        if let h = history, !h.series.isEmpty {
            Section2(title: L("Last 7 days")) {
                Chart {
                    ForEach(h.series) { s in
                        BarMark(x: .value("Day", s.date), y: .value("kcal", s.kcal))
                            .foregroundStyle(Theme.food.opacity(s.date == scrub || s.date == d.today ? 1 : 0.6)).cornerRadius(3)
                            .accessibilityLabel(Loc.dayTitle(s.date, today: d.today)).accessibilityValue(L("\(Int(s.kcal)) kcal"))
                    }
                    RuleMark(y: .value("Target", h.targets.kcal)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Theme.muted)
                        .accessibilityLabel(L("Target")).accessibilityValue(L("\(Int(h.targets.kcal)) kcal"))
                    if let day = scrub, let s = h.series.first(where: { $0.date == day }) {
                        RuleMark(x: .value("Day", day)).foregroundStyle(Theme.muted.opacity(0.35))
                            .annotation(position: .top, spacing: 0, overflowResolution: .inside) {
                                ChartCallout(value: L("\(Int(s.kcal)) kcal"), caption: ChartFmt.md(s.date))
                            }
                    }
                }
                .chartXAxis { AxisMarks { v in AxisValueLabel { if let x = v.as(String.self) { Text(ChartFmt.md(x)).font(.chip).foregroundStyle(Theme.muted) } } } }
                .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel().font(.chip).foregroundStyle(Theme.muted) } }
                .chartXSelection(value: $scrub)
                .frame(height: 150)
                Text("Dashed line is your target.").font(.meta).foregroundStyle(Theme.muted)
            }
        }
    }

    private func macro(_ name: String, _ value: Double, _ target: Double) -> some View {
        let share = FoodLogic.share(value, of: target)
        return VStack(spacing: 6) {
            Ring(progress: share, tint: Theme.food, lineWidth: 6) {
                Text(verbatim: "\(Int((share * 100).rounded()))%").font(.chip).monospacedDigit().foregroundStyle(Theme.text).minimumScaleFactor(0.6)
            }.frame(width: small, height: small)
            Text(name).font(.meta).foregroundStyle(Theme.muted)
            Text("\(Int(value)) / \(Int(target)) g").font(.chip).monospacedDigit().foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name).accessibilityValue(L("\(Int(value)) of \(Int(target)) g"))
    }
}
