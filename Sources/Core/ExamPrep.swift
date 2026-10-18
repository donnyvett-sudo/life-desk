import Foundation

/// Exam preparation: topics from the course's archive index, spread over the days that are left.
enum ExamPrep {
    struct Day: Equatable {
        var number: Int          // 1-based
        var topics: [String]
        var review: Bool         // last day: review and a timed practice paper
    }

    /// "Topic" column of the first table of resources/<course>/archive-2025.md that has one.
    static func topics(archiveMd: String) -> [String] {
        for t in MarkdownTables.tables(archiveMd) where t.rows.contains(where: { $0["topic"] != nil }) {
            return t.rows.compactMap { $0["topic"].map(MarkdownTables.clean) }.filter { !$0.isEmpty }
        }
        return []
    }

    /// New topics get days 1..n-1, the last day is review. One day left: everything is review.
    static func plan(topics: [String], daysLeft: Int) -> [Day] {
        guard daysLeft >= 1 else { return [] }
        if daysLeft == 1 || topics.isEmpty { return [Day(number: 1, topics: topics, review: true)] }
        let learnDays = daysLeft - 1
        var days: [Day] = (1...learnDays).map { Day(number: $0, topics: [], review: false) }
        // spread evenly: topic i goes to day floor(i * learnDays / count)
        for (i, t) in topics.enumerated() { days[i * learnDays / topics.count].topics.append(t) }
        days.append(Day(number: daysLeft, topics: [], review: true))
        return days.filter { !$0.topics.isEmpty || $0.review }
    }

    /// The question sent to the Agent for one topic (the course's AI rule is added by ChatModel).
    static func explainPrompt(topic: String, course: String, exam: String) -> String {
        "I am preparing for \(exam). Explain the topic “\(topic)” using my slides in resources/\(course)/2026 and the archive index "
            + "(resources/\(course)/archive-2025.md): the key ideas, one short example of your own, then three questions to check my understanding. "
            + "Do not give the answers to the questions until I try."
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let md = "# C\n\n| # | Topic | 2025 slide |\n|---|---|---|\n| 1 | Intro | a |\n| 2 | **Syntax** | b |\n| 3 | Pointers | c |\n| 4 | Classes | d |\n"
        let t = topics(archiveMd: md)
        if t != ["Intro", "Syntax", "Pointers", "Classes"] { f.append("topics \(t)") }
        let p = plan(topics: t, daysLeft: 3)
        if p.map(\.number) != [1, 2, 3] || p.last?.review != true || p.dropLast().flatMap(\.topics) != t { f.append("plan 3 \(p)") }
        if plan(topics: t, daysLeft: 1) != [Day(number: 1, topics: t, review: true)] { f.append("one day") }
        if !plan(topics: t, daysLeft: 0).isEmpty { f.append("no days") }
        let long = plan(topics: ["a", "b"], daysLeft: 10)
        if long.count != 3 || long.last?.number != 10 || long.last?.review != true { f.append("more days than topics \(long)") }
        if !explainPrompt(topic: "Pointers", course: "cpp", exam: "Final").contains("resources/cpp/2026") { f.append("prompt") }
        return f
    }
}
