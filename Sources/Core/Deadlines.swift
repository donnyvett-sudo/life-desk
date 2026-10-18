import Foundation

/// Pure deadline logic (tested in Sources/Tests).
enum Deadlines {
    struct Row: Identifiable {
        var item: MarkdownTables.Item
        var botId: String?
        var done: Bool
        /// The bot's own flag when the row matched a bot assignment.
        var botDone: Bool? = nil
        /// File and bot disagree about done.
        var diverges: Bool { botDone.map { $0 != item.done } ?? false }
        var id: String { item.id }
        /// Only in the bot (announced in a chat, added from the phone): there is no row in assignments.md to edit.
        var botOnly: Bool { item.id.hasPrefix("bot:") }
        var title: String { (item.num.isEmpty ? "" : item.num + ": ") + shortText(item.title) }
        /// Full text, when the short title hides something.
        var full: String { [item.title, item.details].filter { !$0.isEmpty }.joined(separator: "\n\n") }
    }
    enum Bucket: String, CaseIterable { case overdue = "Overdue", week = "This week", later = "Later", undated = "No date" }

    /// First sentence (<= limit chars) or a truncated start, like life_sync.first_clause.
    static func shortText(_ s: String, limit: Int = 90) -> String {
        var t = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = (t + " ").range(of: ". "), t.distance(from: t.startIndex, to: r.lowerBound) + 1 <= limit { t = String(t[..<r.lowerBound]) }
        return t.count <= limit ? t : String(t.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// File rows with the bot's done flag merged in (matched by "<#>: <title>" as life_sync.py builds it).
    static func rows(_ items: [MarkdownTables.Item], study: BotStudy?) -> [Row] {
        let bot = (study?.assignments ?? []) + (study?.recentlyDone ?? [])
        var matched = Set<String>()
        var out: [Row] = items.filter { $0.kind == .assignment }.map { it in
            let key = norm("\(it.num): \(it.title)")
            let hit = bot.first { norm($0.title) == key || norm($0.title) == norm("\(it.num): \(shortText(it.title))") }
            if let h = hit { matched.insert(h.id) }
            return Row(item: it, botId: hit?.id, done: it.done || hit?.done == true, botDone: hit?.done)
        }
        // Open bot assignments that no file row matches (HW10 announced in a chat, a task added on the phone) still show here.
        for a in study?.assignments ?? [] where !a.done && !matched.contains(a.id) {
            let item = MarkdownTables.Item(id: "bot:\(a.id)", kind: .assignment, course: a.course?.short ?? "", num: "", title: a.title,
                                           details: a.details ?? "", dueText: a.dueNote ?? a.dueDate ?? "", date: a.dueDate, done: false)
            out.append(Row(item: item, botId: a.id, done: false, botDone: false))
        }
        return out
    }
    private static func norm(_ s: String) -> String { MarkdownTables.clean(s).lowercased() }

    static func days(from today: String, to date: String) -> Int? {
        DateFmt.days(from: today, to: date)
    }
    static func chip(_ d: Int) -> String {
        d == 0 ? "today" : d == 1 ? "tomorrow" : d > 0 ? "in \(d) d" : "\(-d) d ago"
    }
    /// Due chip text + tone for a day offset: "Overdue 3 d", "Today", "Tomorrow", "in 5 d".
    static func dueLabel(_ d: Int) -> (text: String, urgent: Int) {
        d < 0 ? ("Overdue \(-d) d", 2) : d == 0 ? ("Today", 1) : d == 1 ? ("Tomorrow", 1) : ("in \(d) d", 0)
    }
    static func bucket(_ date: String?, today: String) -> Bucket {
        guard let date, let d = days(from: today, to: date) else { return .undated }
        return d < 0 ? .overdue : d <= 7 ? .week : .later
    }
    static func isTentative(_ it: MarkdownTables.Item) -> Bool {
        let t = it.dueText.lowercased()
        return t.contains("tentative") || t.contains("unknown") || t.contains("not held")
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        if shortText("Problems 16.28 (x). Then more. And more") != "Problems 16.28 (x)." .dropLast() { f.append("shortText sentence") }
        if shortText(String(repeating: "a", count: 200)).count != 90 { f.append("shortText limit") }
        if days(from: "2026-10-09", to: "2026-10-12") != 3 || chip(-2) != "2 d ago" || chip(0) != "today" { f.append("days/chip") }
        if bucket("2026-10-16", today: "2026-10-09") != .week || bucket("2026-10-08", today: "2026-10-09") != .overdue || bucket(nil, today: "x") != .undated { f.append("bucket") }
        if dueLabel(-3).text != "Overdue 3 d" || dueLabel(0).text != "Today" || dueLabel(1).text != "Tomorrow" || dueLabel(5).text != "in 5 d" { f.append("dueLabel") }
        let it = MarkdownTables.Item(id: "hw:cpp:Lab 3", kind: .assignment, course: "cpp", num: "Lab 3", title: "TBA", details: "", dueText: "", date: nil, done: false)
        let s = BotStudy(today: "2026-10-09", assignments: [.init(id: "b1", course: nil, title: "Lab 3: TBA", dueDate: nil, done: false)], recentlyDone: [], sessions: [])
        let r = rows([it], study: s)
        if r.first?.botId != "b1" || r.first?.done != false { f.append("rows match") }
        let s2 = BotStudy(today: "x", assignments: [.init(id: "b1", course: nil, title: "Lab 3: TBA", dueDate: nil, done: true)], recentlyDone: [], sessions: [])
        if rows([it], study: s2).first?.diverges != true || r.first?.diverges != false { f.append("rows diverge") }
        let only = BotStudy(today: "x", assignments: [.init(id: "b9", course: nil, title: "HW10", dueDate: "2026-10-19", done: false)], recentlyDone: [], sessions: [])
        if rows([], study: only).first?.botOnly != true || rows([it], study: s).count != 1 { f.append("bot-only rows") }
        return f
    }
}
