import Foundation

/// Deadlines and exams as an iCalendar file (all-day events), importable into Calendar, Google, Outlook.
enum ICS {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "")
    }

    /// RFC 5545 section 3.1: lines of at most 75 octets, continuation lines start with one space.
    static func fold(_ line: String) -> String {
        var out = "", cur = "", bytes = 0
        for ch in line {
            let n = String(ch).utf8.count
            if bytes + n > 75 { out += cur + "\r\n "; cur = ""; bytes = 1 }
            cur.append(ch); bytes += n
        }
        return out + cur
    }

    private static func compact(_ iso: String) -> String { iso.replacingOccurrences(of: "-", with: "") }
    private static func uid(_ id: String) -> String {
        var h: UInt64 = 1469598103934665603   // FNV-1a: stable across runs (Hasher is seeded per launch)
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 16) + "@lifedesk"
    }

    /// `rows`: assignments with their done flag; `exams`: exam items. Undated and done items are left out.
    static func calendar(assignments: [Deadlines.Row], exams: [MarkdownTables.Item], label: (String) -> String,
                         now: Date = Date()) -> String {
        let stampF = DateFormatter()
        stampF.locale = Locale(identifier: "en_US_POSIX"); stampF.timeZone = TimeZone(identifier: "UTC")
        stampF.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = stampF.string(from: now)

        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Life Desk//Deadlines//EN", "CALSCALE:GREGORIAN",
                     "X-WR-CALNAME:Life Desk deadlines"]
        func event(id: String, date: String, summary: String, detail: String) {
            guard let next = QuickEntry.add(days: 1, to: date) else { return }
            lines += ["BEGIN:VEVENT", "UID:\(uid(id))", "DTSTAMP:\(stamp)",
                      "DTSTART;VALUE=DATE:\(compact(date))", "DTEND;VALUE=DATE:\(compact(next))",
                      "SUMMARY:\(escape(summary))"]
            if !detail.isEmpty { lines.append("DESCRIPTION:\(escape(detail))") }
            lines.append("END:VEVENT")
        }
        for r in assignments where !r.done {
            guard let d = r.item.date else { continue }
            event(id: r.item.id, date: d, summary: "\(label(r.item.course)): \(r.title)", detail: r.item.dueText)
        }
        for e in exams {
            guard let d = e.date else { continue }
            let tentative = Deadlines.isTentative(e) ? " (tentative)" : ""
            event(id: e.id, date: d, summary: "Exam \(label(e.course)): \(e.title)\(tentative)", detail: e.dueText)
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        if escape("a,b;c\\d\ne") != "a\\,b\\;c\\\\d\\ne" { f.append("escape \(escape("a,b;c\\d\ne"))") }
        let long = fold(String(repeating: "x", count: 200))
        if long.components(separatedBy: "\r\n").contains(where: { $0.utf8.count > 75 }) { f.append("fold length") }
        if long.replacingOccurrences(of: "\r\n ", with: "") != String(repeating: "x", count: 200) { f.append("fold roundtrip") }
        let a = MarkdownTables.Item(id: "hw:cpp:Lab 4", kind: .assignment, course: "cpp", num: "Lab 4", title: "Bank, deposit", details: "",
                                    dueText: "after the session", date: "2026-10-16", done: false)
        let b = MarkdownTables.Item(id: "hw:cpp:Lab 5", kind: .assignment, course: "cpp", num: "Lab 5", title: "x", details: "", dueText: "", date: nil, done: false)
        let ex = MarkdownTables.Item(id: "ex:cpp:final", kind: .exam, course: "cpp", num: "", title: "Final", details: "", dueText: "", date: "2026-12-31", done: false)
        let rows = [Deadlines.Row(item: a, botId: nil, done: false), Deadlines.Row(item: b, botId: nil, done: false),
                    Deadlines.Row(item: a, botId: nil, done: true)]
        let cal = calendar(assignments: Array(rows.prefix(2)), exams: [ex], label: { $0 }, now: Date(timeIntervalSince1970: 0))
        if cal.components(separatedBy: "BEGIN:VEVENT").count != 3 { f.append("event count") }
        if !cal.contains("DTSTART;VALUE=DATE:20261016\r\nDTEND;VALUE=DATE:20261017") { f.append("dates") }
        if !cal.contains("DTEND;VALUE=DATE:20270101") { f.append("year rollover") }
        if !cal.contains("SUMMARY:cpp: Lab 4: Bank\\, deposit") { f.append("summary escaped") }
        if calendar(assignments: [rows[2]], exams: [], label: { $0 }).contains("VEVENT") { f.append("done skipped") }
        if !cal.hasSuffix("END:VCALENDAR\r\n") { f.append("ends") }
        return f
    }
}
