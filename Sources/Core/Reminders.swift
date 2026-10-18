import Foundation

/// When to nudge about deadlines. Due dates carry no time of day, so: the evening before (18:00) and the morning of
/// the day (09:00). Pure; the app turns the plan into notifications.
enum Reminders {
    struct Reminder: Equatable {
        var id: String
        var fire: Date
        var title: String
        var body: String
    }
    static let eveningHour = 18, morningHour = 9
    static let horizonDays = 14, maxCount = 40   // the system keeps at most 64 pending notifications

    /// `items`: open assignments/exams with their `date` (yyyy-MM-dd); `course` label via `label`.
    static func plan(_ items: [MarkdownTables.Item], done: (MarkdownTables.Item) -> Bool, label: (String) -> String,
                     now: Date, calendar: Calendar = .current) -> [Reminder] {
        var out: [Reminder] = []
        let today = DateFmt.today(now)
        for it in items {
            guard let date = it.date, !done(it), !Deadlines.isTentative(it),
                  let d = DateFmt.days(from: today, to: date), d >= 0, d <= horizonDays,
                  let day = DateFmt.parseDay(date) else { continue }
            let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: day)
            func at(_ dayOffset: Int, hour: Int) -> Date? {
                var comp = DateComponents(); comp.year = parts.year; comp.month = parts.month; comp.day = parts.day.map { $0 + dayOffset }
                comp.hour = hour; comp.minute = 0
                return calendar.date(from: comp)
            }
            let what = (it.kind == .exam ? "Exam: " : "") + (it.num.isEmpty ? it.title : "\(it.num): \(Deadlines.shortText(it.title))")
            let course = label(it.course)
            if let eve = at(-1, hour: eveningHour), eve > now {
                out.append(Reminder(id: "reminder.\(it.id).eve", fire: eve, title: "Due tomorrow · \(course)", body: what))
            }
            if let morn = at(0, hour: morningHour), morn > now {
                out.append(Reminder(id: "reminder.\(it.id).day", fire: morn, title: "Due today · \(course)", body: what))
            }
        }
        return Array(out.sorted { $0.fire < $1.fire }.prefix(maxCount))
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
        func item(_ id: String, _ date: String?, kind: MarkdownTables.Item.Kind = .assignment, due: String = "") -> MarkdownTables.Item {
            .init(id: id, kind: kind, course: "cpp", num: "Lab 4", title: "TBA", details: "", dueText: due, date: date, done: false)
        }
        let r = plan([item("a", "2026-10-16"), item("b", "2026-10-20"), item("old", "2026-10-10"), item("far", "2027-03-01"),
                      item("t", "2026-10-17", due: "tentative 2026-10-17"), item("n", nil), item("d", "2026-10-18")],
                     done: { $0.id == "d" }, label: { $0 }, now: now, calendar: cal)
        // a: evening before (15th 18:00) and morning (16th 09:00); b: both, in the future
        if r.map(\.id) != ["reminder.a.eve", "reminder.a.day", "reminder.b.eve", "reminder.b.day"] { f.append("plan ids \(r.map(\.id))") }
        if cal.component(.hour, from: r[0].fire) != 18 || cal.component(.day, from: r[0].fire) != 15 { f.append("evening time") }
        if cal.component(.hour, from: r[1].fire) != 9 || cal.component(.day, from: r[1].fire) != 16 { f.append("morning time") }
        // due today but after 09:00 already: no morning reminder, evening-before is past too
        let late = plan([item("x", "2026-10-15")], done: { _ in false }, label: { $0 }, now: now, calendar: cal)
        if !late.isEmpty { f.append("nothing after the time has passed") }
        let exam = plan([item("e", "2026-10-16", kind: .exam)], done: { _ in false }, label: { $0 }, now: now, calendar: cal)
        if exam.first?.body.hasPrefix("Exam: ") != true { f.append("exam label") }
        return f
    }
}
