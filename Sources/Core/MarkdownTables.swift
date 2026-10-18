import Foundation

/// Pure markdown parsing for the Study Workspace files. Mirrors tools/life_sync.py (tables, assignments, exams).
enum MarkdownTables {
    struct Table {
        var heading: String
        var header: [String]        // cleaned, lowercased column names
        var rows: [[String: String]]
        var rawHeader: [String]     // as written (emphasis kept) for display
        var rawRows: [[String]]
    }

    struct Item: Identifiable {
        enum Kind { case assignment, exam }
        var id: String
        var kind: Kind
        var course: String
        var num: String
        var title: String
        var details: String
        var dueText: String
        var date: String?           // first ISO date in dueText
        var done: Bool
        var submission = ""
        var file = ""              // path relative to resources/<course>/, "" if none
    }

    enum Block {
        case heading(Int, String)
        case bullet(String)
        case paragraph(String)
        case table(Table)
    }

    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isoDates(_ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "\\d{4}-\\d{2}-\\d{2}") else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return splitPipes(t).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Splits on `|` that isn't escaped as `\|`.
    static func splitPipes(_ s: String) -> [String] {
        var out: [String] = [], cur = "", prevBackslash = false
        for ch in s {
            if ch == "|" && !prevBackslash { out.append(cur); cur = "" } else { cur.append(ch) }
            prevBackslash = ch == "\\"
        }
        out.append(cur)
        return out
    }

    private static func isSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("|") && t.hasSuffix("|") && t.count > 1 && t.allSatisfy { "|:- \t".contains($0) }
    }

    /// Markdown split into headings, bullets, paragraphs and tables (also used by the renderer).
    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        let lines = text.components(separatedBy: .newlines)
        var heading = ""
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let level = line.prefix { $0 == "#" }.count
                heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                out.append(.heading(min(level, 4), heading))
            } else if line.hasPrefix("|"), i + 1 < lines.count, isSeparator(lines[i + 1]) {
                let raw = cells(line)
                let header = raw.map { clean($0).lowercased() }
                var t = Table(heading: heading, header: header, rows: [], rawHeader: raw, rawRows: [])
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    var c = cells(lines[i])
                    while c.count < header.count { c.append("") }
                    t.rawRows.append(c)
                    t.rows.append(Dictionary(zip(header, c), uniquingKeysWith: { a, _ in a }))
                    i += 1
                }
                out.append(.table(t))
                continue
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                out.append(.bullet(String(line.dropFirst(2))))
            } else if !line.isEmpty {
                out.append(.paragraph(line))
            }
            i += 1
        }
        return out
    }

    static func tables(_ text: String) -> [Table] {
        blocks(text).compactMap { if case .table(let t) = $0 { return t } else { return nil } }
    }

    static func read(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

    static func courseFolders(resources: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: resources)) ?? []
        return names.sorted().filter {
            var isDir: ObjCBool = false
            return !$0.hasPrefix(".") && FileManager.default.fileExists(atPath: "\(resources)/\($0)", isDirectory: &isDir) && isDir.boolValue
        }
    }

    static func assignments(resources: String) -> [Item] {
        var out: [Item] = []
        for code in courseFolders(resources: resources) {
            for t in tables(read("\(resources)/\(code)/assignments.md")) {
                for r in t.rows {
                    let num = clean(r["#"] ?? "")
                    if num.isEmpty { continue }
                    let title = clean(r["title"] ?? "")
                    let task = clean(r["task"] ?? "")
                    let due = clean(r["due"] ?? "")
                    let status = clean(r["status"] ?? "").lowercased()
                    out.append(Item(id: "hw:\(code):\(num)", kind: .assignment, course: code, num: num,
                                    title: title.isEmpty ? task : title,
                                    details: title.isEmpty ? "" : (task.isEmpty ? clean(r["topics"] ?? "") : task),
                                    dueText: due, date: isoDates(due).first,
                                    done: status.hasPrefix("done") || status.hasPrefix("✅"),
                                    submission: clean(r["submission"] ?? ""),
                                    file: clean(r["file"] ?? "")))
                }
            }
        }
        return out
    }

    static func exams(resources: String) -> [Item] {
        var out: [Item] = []
        for t in tables(read("\(resources)/exam-dates.md")) {
            for r in t.rows {
                let code = clean(r["course"] ?? ""), type = clean(r["type"] ?? "")
                if code.isEmpty || type.isEmpty { continue }
                let date = clean(r["date"] ?? "")
                out.append(Item(id: "exam:\(code):\(type)", kind: .exam, course: code, num: "", title: type,
                                details: [clean(r["topic/chapters"] ?? ""), clean(r["notes"] ?? "")].filter { !$0.isEmpty }.joined(separator: " · "),
                                dueText: date, date: isoDates(date).first, done: false))
            }
        }
        return out
    }

    /// Upcoming first by first ISO date, undated last; stable on ties.
    static func sorted(_ items: [Item]) -> [Item] {
        items.enumerated().sorted { a, b in
            switch (a.element.date, b.element.date) {
            case let (x?, y?): return x != y ? x < y : a.offset < b.offset
            case (nil, nil): return a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            }
        }.map(\.element)
    }

    /// folder -> course title from the "| Folder | Course |" table of the workspace CLAUDE.md.
    static func courseTitles(workspace: String) -> [String: String] {
        var m: [String: String] = [:]
        for t in tables(read("\(workspace)/CLAUDE.md")) {
            for r in t.rows { if let f = r["folder"], let c = r["course"] { m[clean(f)] = clean(c) } }
        }
        return m
    }

    /// Tiny self-check, run by `./build.sh --test`. Returns failure messages (empty = ok).
    static func selfTest(resources: String) -> [String] {
        var fails: [String] = []
        func check(_ ok: Bool, _ msg: String) { if !ok { fails.append(msg) } }
        let md = "# Head\n\n| # | Title | Due | Status |\n|---|---|---|---|\n| HW1 | **Intro** | 2026-10-16 22:00 | done |\n| HW2 | Next | TBA | todo |\n"
        let ts = tables(md)
        check(ts.count == 1, "inline: one table")
        check(ts.first?.rows.count == 2, "inline: two rows")
        check(ts.first?.heading == "Head", "inline: heading")
        check(clean(ts.first?.rows.first?["title"] ?? "") == "Intro", "inline: clean title")
        check(isoDates("by 2026-10-16 22:00").first == "2026-10-16", "iso date")
        let undated = Item(id: "a", kind: .exam, course: "x", num: "", title: "", details: "", dueText: "", date: nil, done: false)
        var dated = undated; dated.id = "b"; dated.date = "2026-01-01"
        check(sorted([undated, dated]).first?.id == "b", "undated last")
        let a = assignments(resources: resources)
        check(!a.isEmpty, "workspace: assignments count > 0 (\(a.count))")
        check(!exams(resources: resources).isEmpty, "workspace: exams count > 0")
        check(a.contains { $0.date != nil }, "workspace: some dated assignment")
        return fails
    }
}
