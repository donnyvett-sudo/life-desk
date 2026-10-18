import Foundation

/// "cpp lab 3 fri" / "stats101 hw4 пт" / "lang1 quiz 2026-10-30" -> a new assignments.md row.
enum QuickEntry {
    struct Parsed: Equatable {
        var course: String
        var num: String
        var title: String
        var date: String?   // yyyy-MM-dd
    }
    enum Failure: Error, Equatable { case noCourse, empty }

    private static let weekdays: [String: Int] = [   // Calendar weekday: 1 = Sunday
        "sun": 1, "sunday": 1, "вс": 1, "воскресенье": 1,
        "mon": 2, "monday": 2, "пн": 2, "понедельник": 2,
        "tue": 3, "tuesday": 3, "вт": 3, "вторник": 3,
        "wed": 4, "wednesday": 4, "ср": 4, "среда": 4,
        "thu": 5, "thursday": 5, "чт": 5, "четверг": 5,
        "fri": 6, "friday": 6, "пт": 6, "пятница": 6,
        "sat": 7, "saturday": 7, "сб": 7, "суббота": 7,
    ]
    private static let kinds = ["lab", "hw", "homework", "quiz", "project", "report", "essay", "test"]

    /// `label(folder)` is the short name shown in the app ("Stats 101"); both it and the folder name are accepted.
    static func parse(_ input: String, courses: [String], label: (String) -> String, today: String) -> Result<Parsed, Failure> {
        var words = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.isEmpty { return .failure(.empty) }

        // course: the first word (or two words, "prob & stats") that names a course
        var course: String?
        outer: for len in [3, 2, 1] where words.count >= len {
            let head = words.prefix(len).joined(separator: " ").lowercased()
            for c in courses where c.lowercased() == head || label(c).lowercased() == head {
                course = c; words.removeFirst(len); break outer
            }
        }
        guard let course else { return .failure(.noCourse) }

        // date: iso, dd.mm, today/tomorrow, weekday (next one, strictly after today)
        var date: String?
        for (i, w) in words.enumerated().reversed() {
            let l = w.lowercased()
            if let d = isoDate(l) { date = d }
            else if i == words.count - 1, let d = dayMonth(l, today: today) { date = d }   // "section 3.5" is not a date
            else if ["today", "сегодня"].contains(l) { date = today }
            else if ["tomorrow", "завтра"].contains(l) { date = add(days: 1, to: today) }
            else if let wd = weekdays[l] { date = next(weekday: wd, after: today) }
            if date != nil { words.remove(at: i); break }
        }

        // number: "lab 3" / "hw4"
        var num = "", rest = words
        for (i, w) in words.enumerated() {
            let l = w.lowercased()
            if let k = kinds.first(where: { l.hasPrefix($0) }) {
                let tail = String(l.dropFirst(k.count))
                if !tail.isEmpty, tail.allSatisfy(\.isNumber) {
                    num = pretty(k) + " " + tail; rest.remove(at: i); break
                }
                if tail.isEmpty, i + 1 < words.count, words[i + 1].allSatisfy(\.isNumber) {
                    num = pretty(k) + " " + words[i + 1]; rest.removeSubrange(i...(i + 1)); break
                }
            }
        }
        var title = rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if num.isEmpty { num = title.isEmpty ? "Task" : String(title.prefix(24)) }
        if title.isEmpty { title = "TBA" }
        return .success(Parsed(course: course, num: num, title: title, date: date))
    }

    private static func pretty(_ k: String) -> String {
        k == "homework" ? "HW" : k == "hw" ? "HW" : k.prefix(1).uppercased() + k.dropFirst()
    }
    private static func isoDate(_ s: String) -> String? {
        s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil && DateFmt.parseDay(s) != nil ? s : nil
    }
    private static func dayMonth(_ s: String, today: String) -> String? {
        let p = s.split(separator: ".").map(String.init)
        guard p.count == 2, p[0].count == 2, p[1].count == 2, let d = Int(p[0]), let m = Int(p[1]), (1...31).contains(d), (1...12).contains(m),
              let year = Int(today.prefix(4)) else { return nil }
        let cand = String(format: "%04d-%02d-%02d", year, m, d)
        guard DateFmt.parseDay(cand) != nil else { return nil }
        return cand < today ? String(format: "%04d-%02d-%02d", year + 1, m, d) : cand
    }
    private static var utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private static func format(_ d: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func add(days: Int, to iso: String) -> String? {
        DateFmt.parseDay(iso).flatMap { utc.date(byAdding: .day, value: days, to: $0) }.map(format)
    }
    static func next(weekday: Int, after iso: String) -> String? {
        guard let d = DateFmt.parseDay(iso) else { return nil }
        let cur = utc.component(.weekday, from: d)
        var delta = (weekday - cur + 7) % 7
        if delta == 0 { delta = 7 }
        return add(days: delta, to: iso)
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let courses = ["cpp", "stats101", "lang1"]
        func p(_ s: String) -> Parsed? { try? parse(s, courses: courses, label: { $0 == "stats101" ? "Stats 101" : $0 }, today: "2026-10-15").get() }
        // 2026-10-15 is a Thursday
        if p("cpp lab 3 fri") != Parsed(course: "cpp", num: "Lab 3", title: "TBA", date: "2026-10-16") { f.append("lab fri \(String(describing: p("cpp lab 3 fri")))") }
        if p("cpp lab 3 пт")?.date != "2026-10-16" { f.append("ru weekday") }
        if p("cpp hw4 thu")?.date != "2026-10-22" { f.append("same weekday = next week") }
        if p("stats101 HW5 2026-11-02 chapter 7")?.title != "chapter 7" || p("stats101 HW5 2026-11-02")?.num != "HW 5" { f.append("iso/num") }
        if p("Stats 101 quiz 2 tomorrow")?.course != "stats101" || p("Stats 101 quiz 2 tomorrow")?.date != "2026-10-16" { f.append("label course") }
        if p("cpp hw 4 section 3.5 fri")?.date != "2026-10-16" || p("cpp hw 4 section 3.5")?.date != nil { f.append("decimal is not a date") }
        if p("lang1 essay 20.10")?.date != "2026-10-20" || p("lang1 essay 01.10")?.date != "2027-10-01" { f.append("dd.mm") }
        if (try? parse("math hw 1", courses: courses, label: { $0 }, today: "2026-10-15").get()) != nil { f.append("unknown course") }
        if (try? parse("   ", courses: courses, label: { $0 }, today: "2026-10-15").get()) != nil { f.append("empty") }
        if next(weekday: 2, after: "2026-12-31") != "2027-01-04" { f.append("year rollover") }
        return f
    }
}
