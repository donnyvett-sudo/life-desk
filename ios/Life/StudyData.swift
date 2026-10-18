import Foundation

/// Phone-side views of the bot's study overview, built on the same Core logic as Life Desk.
enum StudyData {
    struct DueRow: Identifiable {
        var a: BotStudy.Assignment
        var id: String { a.id }
        var course: String { a.course?.short ?? "" }
    }

    static func today() -> String { DateFmt.today() }

    static func open(_ s: BotStudy?) -> [DueRow] {
        (s?.assignments ?? []).filter { !$0.done }.map(DueRow.init)
            .sorted { ($0.a.dueDate ?? "9999") < ($1.a.dueDate ?? "9999") }
    }

    static func days(_ date: String?, today: String = today()) -> Int? { date.flatMap { Deadlines.days(from: today, to: $0) } }

    struct ExamCard: Identifiable, Equatable, Hashable {
        var id: String; var course: String; var title: String; var date: String; var days: Int; var tentative: Bool
        var label: String { days == 0 ? L("today") : days == 1 ? L("tomorrow") : (tentative ? L("~\(days) d") : L("\(days) d")) }
    }

    /// Upcoming exams, soonest first; past and undated ones are left out.
    static func exams(_ s: BotStudy?, limit: Int = 50) -> [ExamCard] {
        let t = today()
        return (s?.exams ?? []).compactMap { e -> ExamCard? in
            guard let d = e.date, let n = Deadlines.days(from: t, to: d), n >= 0 else { return nil }
            return ExamCard(id: e.id, course: e.course?.short ?? "", title: e.title, date: d, days: n, tentative: e.tentative ?? false)
        }.sorted { ($0.days, $0.id) < ($1.days, $1.id) }.prefix(limit).map { $0 }
    }

    static func classesToday(_ s: BotStudy?) -> [BotStudy.Session] {
        (s?.sessions ?? []).filter { $0.date == today() }.sorted { $0.start < $1.start }
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let s = BotStudy(today: "2026-10-16", assignments: [
            .init(id: "b", course: nil, title: "later", dueDate: "2026-10-30", done: false),
            .init(id: "a", course: nil, title: "soon", dueDate: "2026-10-17", done: false),
            .init(id: "d", course: nil, title: "done", dueDate: "2026-10-10", done: true)], recentlyDone: [], sessions: [])
        if open(s).map(\.id) != ["a", "b"] { f.append("open order") }
        return f
    }
}
