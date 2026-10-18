import Foundation

/// Daily focus minutes kept locally (the bot reports today's total on every refresh; the app keeps the history).
struct FocusLog: Codable, Equatable {
    var days: [String: Int] = [:]   // yyyy-MM-dd -> minutes

    /// Today's total only grows during the day, so the larger value wins (a refresh after a stop cannot lower it).
    mutating func record(day: String, minutes: Int) {
        guard minutes > 0 else { return }
        days[day] = max(days[day] ?? 0, minutes)
    }
}

enum FocusStats {
    struct Cell: Equatable { var day: String; var minutes: Int; var level: Int; var future: Bool }

    /// Consecutive days with focus up to today; a day that has not started yet does not break the streak.
    static func streak(_ log: FocusLog, today: String) -> Int {
        var n = 0
        var day = today
        if (log.days[day] ?? 0) == 0, let y = QuickEntry.add(days: -1, to: day) { day = y }
        while (log.days[day] ?? 0) > 0 {
            n += 1
            guard let p = QuickEntry.add(days: -1, to: day) else { break }
            day = p
        }
        return n
    }

    /// Monday of the week containing `day`.
    static func monday(of day: String) -> String? {
        guard let d = DateFmt.parseDay(day) else { return nil }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let wd = c.component(.weekday, from: d)           // 1 = Sunday
        return QuickEntry.add(days: -((wd + 5) % 7), to: day)
    }

    static func weekMinutes(_ log: FocusLog, today: String) -> Int {
        guard let mon = monday(of: today) else { return 0 }
        return (0..<7).reduce(0) { $0 + (log.days[QuickEntry.add(days: $1, to: mon) ?? ""] ?? 0) }
    }

    /// `weeks` columns, Monday first, oldest week first. Level 0 = none, 1...4 by minutes (30/60/120/+).
    static func heatmap(_ log: FocusLog, today: String, weeks: Int = 12) -> [[Cell]] {
        guard let mon = monday(of: today), let start = QuickEntry.add(days: -7 * (weeks - 1), to: mon) else { return [] }
        return (0..<weeks).map { w in
            (0..<7).map { d in
                let day = QuickEntry.add(days: w * 7 + d, to: start) ?? ""
                let m = log.days[day] ?? 0
                return Cell(day: day, minutes: m, level: m == 0 ? 0 : m < 30 ? 1 : m < 60 ? 2 : m < 120 ? 3 : 4, future: day > today)
            }
        }
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        // 2026-10-15 is a Thursday; its Monday is 10-12.
        if monday(of: "2026-10-15") != "2026-10-12" || monday(of: "2026-10-18") != "2026-10-12" || monday(of: "2026-10-12") != "2026-10-12" { f.append("monday") }
        var log = FocusLog()
        log.record(day: "2026-10-15", minutes: 25); log.record(day: "2026-10-15", minutes: 10)
        if log.days["2026-10-15"] != 25 { f.append("max wins") }
        log.record(day: "2026-10-14", minutes: 50); log.record(day: "2026-10-13", minutes: 5); log.record(day: "2026-10-11", minutes: 90)
        if streak(log, today: "2026-10-15") != 3 { f.append("streak \(streak(log, today: "2026-10-15"))") }
        var noToday = log; noToday.days["2026-10-15"] = nil
        if streak(noToday, today: "2026-10-15") != 2 { f.append("streak keeps yesterday") }
        if weekMinutes(log, today: "2026-10-15") != 80 { f.append("week \(weekMinutes(log, today: "2026-10-15"))") }
        let h = heatmap(log, today: "2026-10-15")
        if h.count != 12 || h.contains(where: { $0.count != 7 }) { f.append("shape") }
        if h.last?[3].day != "2026-10-15" || h.last?[3].level != 1 || h.last?[4].future != true { f.append("last week cells") }
        if h.last?.first?.day != "2026-10-12" || h[0][0].day != "2026-07-27" { f.append("first cells \(h[0][0].day)") }
        return f
    }
}
