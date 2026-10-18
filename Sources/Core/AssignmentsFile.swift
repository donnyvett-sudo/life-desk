import Foundation

/// Edits the Status cell of one row in resources/<course>/assignments.md, nothing else.
enum AssignmentsFile {
    /// New file text with the row `num` marked done/todo; the same text if already so; nil unless exactly one row matches.
    static func setStatus(in text: String, num: String, done: Bool) -> String? {
        var lines = text.components(separatedBy: "\n")
        var statusCol: Int? = nil, headerCount = 0
        var hit: Int? = nil, hitCol = 0, hits = 0
        for i in lines.indices {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("|") else { statusCol = nil; continue }
            let cells = MarkdownTables.splitPipes(String(t.dropFirst())).map { MarkdownTables.clean($0).lowercased() }
            if i + 1 < lines.count, lines[i + 1].allSatisfy({ "|:- \t\r".contains($0) }), lines[i + 1].contains("-") {
                statusCol = cells.firstIndex(of: "status"); headerCount = cells.count; continue
            }
            if let c = statusCol, cells.first == MarkdownTables.clean(num).lowercased(), c < cells.count - 1, cells.count == headerCount { hit = i; hitCol = c; hits += 1 }
        }
        guard hits == 1, let i = hit else { return nil }
        let col = hitCol
        var parts = MarkdownTables.splitPipes(lines[i])           // parts[0] is the text before the first "|"
        let old = MarkdownTables.clean(parts[col + 1]).lowercased()
        if old.hasPrefix("done") == done { return text }
        parts[col + 1] = done ? " done " : " todo "
        lines[i] = parts.joined(separator: "|")
        return lines.joined(separator: "\n")
    }

    /// New file text with a row added to the first table that has a "#" and a "Status" column; nil if there is none
    /// or the key is already used. Other columns get "—", Due gets the date or "TBA".
    static func appendRow(to text: String, num: String, title: String, due: String?) -> String? {
        var lines = text.components(separatedBy: "\n")
        var header: [String]?, lastRow: Int?
        for i in lines.indices {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("|") else { if header != nil, lastRow != nil { break }; continue }
            let cells = MarkdownTables.splitPipes(String(t.dropFirst())).map { MarkdownTables.clean($0).lowercased() }
            if header == nil {
                if i + 1 < lines.count, lines[i + 1].allSatisfy({ "|:- \t\r".contains($0) }), lines[i + 1].contains("-"),
                   cells.first == "#", cells.contains("status") { header = cells }
                continue
            }
            if lines[i].allSatisfy({ "|:- \t\r".contains($0) }) { lastRow = i; continue }
            if cells.first == MarkdownTables.clean(num).lowercased() { return nil }
            lastRow = i
        }
        guard let h = header, let at = lastRow else { return nil }
        let cleanNum = num.replacingOccurrences(of: "|", with: "/")
        // The header's trailing pipe leaves an empty last cell; a header without it keeps all its columns.
        let cols = h.last == "" ? Array(h.dropLast()) : h
        let cells = cols.map { name -> String in
            if name == "#" { return cleanNum }
            if name == "title" { return title.replacingOccurrences(of: "|", with: "/") }
            if name.hasPrefix("due") || name == "deadline" { return due ?? "TBA" }
            if name == "status" { return "todo" }
            return "—"
        }
        let cr = lines[at].hasSuffix("\r") ? "\r" : ""
        lines.insert("| " + cells.joined(separator: " | ") + " |" + cr, at: at + 1)
        return lines.joined(separator: "\n")
    }

    @discardableResult
    static func add(course: String, num: String, title: String, due: String?, resources: String = Config.resources) -> Bool {
        let path = "\(resources)/\(course)/assignments.md"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let new = appendRow(to: text, num: num, title: title, due: due) else { return false }
        // Someone else (the sync, the Agent) may have edited the file meanwhile: write only onto what was read.
        guard (try? String(contentsOfFile: path, encoding: .utf8)) == text else { return false }
        return (try? new.write(toFile: path, atomically: true, encoding: .utf8)) != nil
    }

    /// Writes the change to disk. False if the row can't be matched uniquely or the write fails.
    @discardableResult
    static func markDone(course: String, num: String, done: Bool = true, resources: String = Config.resources) -> Bool {
        let path = "\(resources)/\(course)/assignments.md"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let new = setStatus(in: text, num: num, done: done) else { return false }
        if new == text { return true }
        guard (try? String(contentsOfFile: path, encoding: .utf8)) == text else { return false }
        return (try? new.write(toFile: path, atomically: true, encoding: .utf8)) != nil
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let md = "# T\n\n| # | Title | Due | Status | File |\n|---|---|---|---|---|\n| HW1 | A | x | todo | — |\n| HW2 | B | x | done, submitted | — |\n| HW1x | C | x | todo | — |\n"
        let a = setStatus(in: md, num: "HW1", done: true)
        if a?.contains("| HW1 | A | x | done | — |") != true { f.append("markDone row") }
        if a?.contains("| HW1x | C | x | todo |") != true { f.append("markDone leaves other rows") }
        if setStatus(in: md, num: "HW2", done: true) != md { f.append("already done unchanged") }
        if setStatus(in: md, num: "HW9", done: true) != nil { f.append("missing row nil") }
        if setStatus(in: md + "| HW1 | dup | x | todo | — |\n", num: "HW1", done: true) != nil { f.append("ambiguous nil") }
        let esc = "| # | Title | Due | Status |\n|---|---|---|---|\n| HW1 | a \\| b | x | todo |\n"
        if setStatus(in: esc, num: "HW1", done: true)?.contains("| HW1 | a \\| b | x | done |") != true { f.append("escaped pipe") }
        if setStatus(in: "| # | Title | Status |\n|---|---|---|\n| HW1 | a | b | todo |\n", num: "HW1", done: true) != nil { f.append("cell count mismatch") }
        if setStatus(in: a ?? "", num: "HW1", done: false)?.contains("| HW1 | A | x | todo |") != true { f.append("undo") }
        let crlf = md.replacingOccurrences(of: "\n", with: "\r\n")
        if setStatus(in: crlf, num: "HW1", done: true)?.contains("| HW1 | A | x | done | — |\r\n") != true { f.append("CRLF file") }
        let noPipe = "| # | Title | Due date | Status\n|---|---|---|---\n| HW1 | A | x | todo\n"
        if appendRow(to: noPipe, num: "HW2", title: "B", due: "2026-11-01")?.contains("| HW2 | B | 2026-11-01 | todo |") != true { f.append("append: due date column, no trailing pipe") }
        let added = appendRow(to: md, num: "HW9", title: "New", due: "2026-11-01")
        if added?.contains("| HW9 | New | 2026-11-01 | todo | — |\n") != true { f.append("append row") }
        if appendRow(to: md, num: "hw1", title: "x", due: nil) != nil { f.append("append duplicate refused") }
        if appendRow(to: "no table", num: "HW9", title: "x", due: nil) != nil { f.append("append without table") }
        return f
    }
}
