import Foundation

/// Pure helpers for the SYNC page: "last read" ages and `git show --stat` parsing.
enum SyncInfo {
    enum Level { case ok, warn, never }

    static func parseDate(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        return nil
    }

    static func daysWord(_ n: Int) -> String { n == 0 ? "today" : "\(n) d ago" }

    /// "read N d ago", orange (warn) when more than 3 days, red (never) when there is no date.
    static func ago(_ d: Date?, now: Date = Date()) -> (text: String, level: Level) {
        guard let d else { return ("never read", .never) }
        let n = max(0, Int(now.timeIntervalSince(d) / 86400))
        return (n == 0 ? "read today" : "read \(daysWord(n))", n > 3 ? .warn : .ok)
    }

    /// Oldest "Last read" among the rows of an app (nil app = all rows). Rows marked `skip` are ignored;
    /// a row without a date means "never" (nil).
    static func lastRead(rows: [[String: String]], app: String?) -> Date? {
        let rel = rows.filter {
            (app == nil || $0["app"]?.lowercased() == app) && !($0["notes"] ?? "").lowercased().hasPrefix("skip")
        }
        let dates = rel.map { parseDate($0["last read"] ?? "") }
        if rel.isEmpty || dates.contains(where: { $0 == nil }) { return nil }
        return dates.compactMap { $0 }.min()
    }

    /// Chats (rows not marked skip) whose "Last read" is older than `hours` or missing.
    static func staleRows(_ rows: [[String: String]], hours: Double = 24, now: Date = Date()) -> Int {
        rows.filter { !($0["notes"] ?? "").lowercased().hasPrefix("skip") }.filter { r in
            guard let d = parseDate(r["last read"] ?? "") else { return true }
            return now.timeIntervalSince(d) > hours * 3600
        }.count
    }

    /// File lines of `git show --stat`: " path/to/file | 12 +++--".
    static func parseStat(_ out: String) -> [(path: String, changes: String)] {
        out.components(separatedBy: "\n").compactMap { line in
            guard let r = line.range(of: " | ") else { return nil }
            let path = line[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let ch = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : (path, ch)
        }
    }

    // MARK: freshness chip (good <= 1 d, warn 2-3 d, bad > 3 d or never)
    enum Fresh { case good, warn, bad }

    static func freshness(_ d: Date?, now: Date = Date()) -> (text: String, fresh: Fresh) {
        guard let d else { return ("never read", .bad) }
        let n = max(0, Int(now.timeIntervalSince(d) / 86400))
        return (n == 0 ? "read today" : "read \(n) d ago", n <= 1 ? .good : n <= 3 ? .warn : .bad)
    }

    /// "just now", "5 min ago", "3 h ago", "2 d ago".
    static func relative(_ d: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(d)))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }

    enum Source: Int, CaseIterable { case qq, wechat, fileTransfer
        var title: String { ["QQ", "WeChat", "File Transfer (WeChat)"][rawValue] }
    }

    /// Which source block a row of resources/sources.md belongs to.
    static func source(of row: [String: String]) -> Source {
        if (row["app"] ?? "").lowercased() == "qq" { return .qq }
        let name = row.first { $0.key.hasPrefix("chat name") }?.value.lowercased() ?? ""
        return name.contains("file transfer") ? .fileTransfer : .wechat
    }

    /// `git show --numstat` lines: "12<TAB>3<TAB>path" (binary files show "-").
    static func parseNumstat(_ out: String) -> [(path: String, added: Int, deleted: Int)] {
        out.components(separatedBy: "\n").compactMap { line in
            let p = line.components(separatedBy: "\t")
            guard p.count == 3, !p[2].isEmpty, p[0] == "-" || Int(p[0]) != nil else { return nil }
            return (p[2], Int(p[0]) ?? 0, Int(p[1]) ?? 0)
        }
    }
}
