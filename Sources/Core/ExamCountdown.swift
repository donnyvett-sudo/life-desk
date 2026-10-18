import Foundation

/// The next exams as countdown cards on Today.
enum ExamCountdown {
    struct Card: Equatable {
        var id: String
        var course: String
        var title: String
        var date: String
        var days: Int
        var tentative: Bool
        /// "today", "tomorrow", "12 d" (a tentative date reads "~12 d").
        var label: String {
            let base = days == 0 ? "today" : days == 1 ? "tomorrow" : "\(days) d"
            return tentative && days > 1 ? "~" + base : base
        }
    }

    static func upcoming(_ exams: [MarkdownTables.Item], today: String, limit: Int = 3) -> [Card] {
        exams.compactMap { e -> Card? in
            guard e.kind == .exam, let date = e.date, let d = DateFmt.days(from: today, to: date), d >= 0 else { return nil }
            return Card(id: e.id, course: e.course, title: e.title, date: date, days: d, tentative: Deadlines.isTentative(e))
        }.sorted { ($0.days, $0.id) < ($1.days, $1.id) }.prefix(limit).map { $0 }
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        func ex(_ id: String, _ date: String?, due: String = "") -> MarkdownTables.Item {
            .init(id: id, kind: .exam, course: "cpp", num: "", title: "Final", details: "", dueText: due, date: date, done: false)
        }
        let c = upcoming([ex("c", "2026-12-20"), ex("a", "2026-10-16"), ex("past", "2026-10-01"), ex("none", nil),
                          ex("t", "2026-11-05", due: "tentative week 9"), ex("far", "2027-01-10")], today: "2026-10-15")
        if c.map(\.id) != ["a", "t", "c"] { f.append("order/limit \(c.map(\.id))") }
        if c.map(\.label) != ["tomorrow", "~21 d", "66 d"] { f.append("labels \(c.map(\.label))") }
        if upcoming([ex("x", "2026-10-15")], today: "2026-10-15").first?.label != "today" { f.append("today") }
        return f
    }
}
