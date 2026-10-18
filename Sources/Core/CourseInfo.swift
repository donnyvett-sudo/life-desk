import Foundation

/// Pure helpers for the Courses and Notices pages.
enum CourseInfo {
    /// Teacher line from course-info.md: a "**Instructor:** …" bullet, else the "teacher" row of the facts table.
    static func teacher(info: String) -> String? {
        var found: String?
        for line in info.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") || t.hasPrefix("* "),
                  let r = t.range(of: #"^[-*]\s*\*\*(Instructors?|Teachers?|Lecturers?):\*\*\s*"#, options: [.regularExpression, .caseInsensitive])
            else { continue }
            found = clean(String(t[r.upperBound...])); break
        }
        if found == nil {
            found = MarkdownTables.tables(info).lazy.flatMap { $0.rows }.first { $0["key"] == "teacher" }?["value"].map(MarkdownTables.clean)
        }
        guard let f = found, !f.isEmpty else { return nil }
        return f
    }

    /// Keeps the name; drops emails, offices and "(as written …)" remarks.
    private static func clean(_ s: String) -> String {
        var parts = MarkdownTables.clean(s).components(separatedBy: ", ")
        parts = parts.filter { !$0.contains("@") && !$0.lowercased().hasPrefix("office") }
        var out = parts.joined(separator: ", ")
        if let r = out.range(of: #"\s*\(as [^)]*\)"#, options: .regularExpression) { out.removeSubrange(r) }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
    }

    enum PolicyTone { case bad, warn }
    /// Built-in rules per course folder, a floor under what course-info.md says ("rewording a file never loosens a ban").
    /// Ships empty: add your own, e.g. ["stats101": ("Generative AI banned in all assessments", .bad)].
    nonisolated(unsafe) static var builtInPolicies: [String: (text: String, tone: PolicyTone)] = [:]
    static func policy(_ course: String) -> (text: String, tone: PolicyTone)? { builtInPolicies[course] }

    /// "File" column (relative to 2026/) -> one-line summary, from 2026/files.md.
    static func summaries(filesMd: String) -> [String: String] {
        var m: [String: String] = [:]
        if let t = MarkdownTables.tables(filesMd).first {
            for r in t.rows { if let f = r["file"], let s = r["summary"] { m[MarkdownTables.clean(f)] = MarkdownTables.clean(s) } }
        }
        return m
    }

    /// First path component below 2026/, or "Other" for files in the root.
    static func group(rel: String) -> String {
        let p = rel.split(separator: "/")
        return p.count > 1 ? String(p[0]) : "Other"
    }

    /// Whole days from `today` to `iso` (both yyyy-MM-dd).
    static func days(from today: String, to iso: String) -> Int? {
        DateFmt.days(from: today, to: iso)
    }

    static func dueLabel(date: String?, today: String) -> (text: String, tone: DueTone) {
        guard let date, let d = days(from: today, to: date) else { return ("no date", .neutral) }
        if d < 0 { return ("\(-d) d overdue", .bad) }
        if d == 0 { return ("today", .accent) }
        if d == 1 { return ("tomorrow", .accent) }
        return ("in \(d) d", .neutral)
    }
}

enum DueTone { case neutral, accent, bad }

enum NoticeLogic {
    static func key(date: String, course: String, title: String) -> String { "\(date)|\(course)|\(title)" }

    static func dayTitle(_ iso: String, today: String) -> String {
        if iso == today { return "Today" }
        if let d = CourseInfo.days(from: iso, to: today), d == 1 { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: iso) else { return iso }
        let o = DateFormatter(); o.locale = Locale(identifier: "en_US"); o.dateFormat = "EEEE, d MMMM"
        return o.string(from: d)
    }
}
