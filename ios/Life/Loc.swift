import SwiftUI

/// Localized versions of the hand-built English labels that Core and Shared produce for the Mac app.
enum Loc {
    static func days(_ n: Int) -> String { L("\(n) d") }
    static func minutes(_ m: Int) -> String { m >= 60 ? L("\(m / 60) h \(m % 60) min") : L("\(m) min") }
    static func duration(_ m: Int) -> String { m >= 60 ? L("\(m / 60) h \(String(format: "%02d", m % 60)) m") : L("\(m) m") }
    static func bedDiff(_ d: Int) -> String {
        if abs(d) < 5 { return L("on time") }
        return d > 0 ? L("\(duration(abs(d))) later") : L("\(duration(abs(d))) earlier")
    }
    static func dueLabel(_ d: Int) -> (text: String, urgent: Int) {
        d < 0 ? (L("Overdue \(-d) d"), 2) : d == 0 ? (L("Today"), 1) : d == 1 ? (L("Tomorrow"), 1) : (L("in \(d) d"), 0)
    }
    static func remaining(_ t: FoodDay) -> (text: String, over: Bool) {
        let d = t.targets.kcal - t.totals.kcal
        return d >= 0 ? (L("\(Int(d.rounded())) kcal left"), false) : (L("\(Int((-d).rounded())) kcal over"), true)
    }
    static func habitProgress(_ h: HabitsOverview.Habit) -> String {
        h.kind == "weekly" ? L("\(h.weekDone) of \(h.target) this week") : h.streak > 0 ? L("\(h.streak) day streak") : L("no streak yet")
    }
    /// "2026-10" → "October 2026" / "Октябрь 2026".
    static func monthTitle(_ key: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: key) else { return key }
        let o = DateFormatter(); o.dateFormat = "LLLL yyyy"; o.locale = AppLanguage.locale
        let s = o.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
    /// Notices day heading: "Today" / "Yesterday" / "Wednesday, 7 October".
    static func dayTitle(_ iso: String, today: String) -> String {
        if iso == today { return L("Today") }
        if let d = CourseInfo.days(from: iso, to: today), d == 1 { return L("Yesterday") }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: iso) else { return iso }
        let o = DateFormatter(); o.locale = AppLanguage.locale
        o.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return o.string(from: d)
    }
    static func bucket(_ b: Deadlines.Bucket) -> String { AppLanguage.tr(b.rawValue) }
}

/// Like the shared DueChip, with the label in the chosen language.
struct LocalDueChip: View {
    let date: String?
    let today: String
    var body: some View {
        if let d = date.flatMap({ Deadlines.days(from: today, to: $0) }) {
            let l = Loc.dueLabel(d)
            Chip(text: l.text, tone: l.urgent == 2 ? .bad : l.urgent == 1 ? .accent : .neutral)
        } else {
            Chip(text: L("No date"))
        }
    }
}

