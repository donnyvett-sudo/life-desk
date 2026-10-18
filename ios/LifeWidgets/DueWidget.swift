import SwiftUI
import WidgetKit

struct DueEntry: TimelineEntry { let date: Date; let snap: WidgetSnapshot? }

struct DueProvider: TimelineProvider {
    func placeholder(in context: Context) -> DueEntry {
        DueEntry(date: Date(), snap: .init(updated: Date(), deadlines: [.init(title: "Lab report", course: "PHYS", date: "2099-01-01")], exam: nil))
    }
    func getSnapshot(in context: Context, completion: @escaping (DueEntry) -> Void) { completion(DueEntry(date: Date(), snap: WidgetSnapshot.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DueEntry>) -> Void) {
        let now = Date()
        // Day counts change at midnight; the app also reloads the widget whenever it fetches fresh data.
        let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [DueEntry(date: now, snap: WidgetSnapshot.load())], policy: .after(next)))
    }
}

private func when(_ date: String) -> (text: String, urgent: Bool) {
    guard let n = WidgetSnapshot.days(to: date) else { return (date, false) }
    switch n {
    case ..<0: return (L("overdue"), true)
    case 0: return (L("today"), true)
    case 1: return (L("tomorrow"), true)
    default: return (L("\(n) d"), false)
    }
}

struct DueWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DueEntry

    var body: some View {
        let snap = entry.snap
        let rows = (snap?.deadlines ?? []).prefix(family == .systemSmall ? 3 : 4)
        VStack(alignment: .leading, spacing: 6) {
            if let e = snap?.exam, let n = WidgetSnapshot.days(to: e.date), n >= 0 {
                HStack(spacing: 6) {
                    Image(systemName: "graduationcap.fill").foregroundStyle(.orange)
                    Text(L("\(e.course) exam")).font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(n == 0 ? L("today") : L("\(n) d")).font(.caption.weight(.bold)).foregroundStyle(.orange)
                }
            }
            if snap == nil { Text(L("Open Life to load your deadlines")).font(.caption).foregroundStyle(.secondary) }
            else if rows.isEmpty { Text(L("Nothing due 🎉")).font(.subheadline) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                let w = when(r.date)
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.title).font(.caption.weight(.medium)).lineLimit(1)
                        if !r.course.isEmpty { Text(r.course).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 4)
                    Text(w.text).font(.caption.weight(.semibold)).foregroundStyle(w.urgent ? Color.red : Color.secondary)
                }
            }
            Spacer(minLength: 0)
            if let u = snap?.updated, Date().timeIntervalSince(u) > 86_400 {
                Text(L("Updated \(Int(Date().timeIntervalSince(u) / 86_400)) d ago")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct DueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DueWidget", provider: DueProvider()) { DueWidgetView(entry: $0) }
            .configurationDisplayName("Next deadlines")
            .description("Your closest deadlines and the next exam.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
