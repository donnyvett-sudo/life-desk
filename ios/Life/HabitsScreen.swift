import SwiftUI
import UIKit

/// Habits: tick today, see the streak and the last two weeks.
struct HabitsScreen: View {
    @State private var data: HabitsOverview?
    @State private var error: String?
    @State private var busy: Set<String> = []

    var body: some View {
        PageView(title: L("Habits"), summary: data.map { $0.dueCount == 0 ? L("All done for today") : L("\($0.dueCount) left today") }, trailing: { TodayChip() }) {
            VStack(alignment: .leading, spacing: 18) {
                if let error { ErrorBanner(text: error) { self.error = nil } }
                if let d = data {
                    let active = d.habits.filter(\.active)
                    if active.isEmpty {
                        Group2 { EmptyState(icon: "repeat", title: L("No habits yet"), detail: L("Add one in the Life Desk Mini App or tell the coach «add a habit: reading».")) }
                    } else {
                        Group2 { Rows(items: active) { h in row(h, today: d.today) } }
                    }
                } else if error == nil { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
            }
        }
        .celebrates()
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        let r: (status: Int, data: Data)
        do { r = try await BotAPI.raw("GET", "/habits") }
        catch is CancellationError { return }
        catch { self.error = L("No connection."); return }
        guard r.status == 200, let d = try? JSONDecoder().decode(HabitsOverview.self, from: r.data) else { error = L("Could not load habits (\(r.status))."); return }
        data = d; error = nil
    }

    private func row(_ h: HabitsOverview.Habit, today: String) -> some View {
        HStack(spacing: 12) {
            Button { Task { await toggle(h) } } label: {
                Image(systemName: h.doneToday ? "checkmark.circle.fill" : "circle").font(.system(size: 28))
                    .foregroundStyle(h.doneToday ? Theme.accent : Theme.muted)
            }
            .buttonStyle(.plain).disabled(busy.contains(h.id))
            .accessibilityLabel("\(h.title), \(h.doneToday ? L("done today") : L("not done today"))").accessibilityHint("Toggles today")
            VStack(alignment: .leading, spacing: 5) {
                Text(h.title).font(.rowTitle).foregroundStyle(Theme.text).strikethrough(h.doneToday)
                Text(Loc.habitProgress(h)).font(.meta).foregroundStyle(Theme.muted)
                HStack(spacing: 3) {
                    ForEach(Array(HabitLogic.strip(h, today: today).enumerated()), id: \.offset) { _, on in
                        RoundedRectangle(cornerRadius: 2).fill(on ? Theme.accent : Theme.surface2).frame(width: 10, height: 10)
                    }
                }.accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            if h.isHard { Chip(text: L("hard"), tone: .warn) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func toggle(_ h: HabitsOverview.Habit) async {
        busy.insert(h.id); defer { busy.remove(h.id) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let r = try? await BotAPI.raw("POST", "/habits/\(h.id)/toggle", body: Data("{}".utf8)), r.status == 200 {
            await load()
            if !h.doneToday, data?.habits.first(where: { $0.id == h.id })?.doneToday == true { Celebrate.shared.fire() }
        }
        else { error = L("Could not update. Check the connection.") }
    }
}
