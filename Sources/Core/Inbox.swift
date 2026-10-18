import Foundation

/// One list of what needs attention: overdue work, unseen notices, new files, stale sources, file/bot mismatches.
enum Inbox {
    enum Kind: Int { case overdue, notice, file, sync, diverged
        var label: String { ["Overdue", "Notice", "New file", "Sync", "Mismatch"][rawValue] }
    }
    struct Entry: Identifiable, Equatable {
        var id: String
        var kind: Kind
        var title: String
        var detail: String
        var course: String
        var ref: String      // deadline id, notice key or file path
    }
    struct NoticeRow: Equatable { var date: String, course: String, title: String }
    struct FileRow: Equatable { var path: String, course: String, modified: Date }

    static let newFileDays = 7.0, maxFiles = 15

    static func build(overdue: [Deadlines.Row], today: String, notices: [NoticeRow], seen: Set<String>,
                      files: [FileRow], staleSources: Int, diverged: [Deadlines.Row],
                      dismissed: Set<String>, now: Date = Date()) -> [Entry] {
        var out: [Entry] = []
        for r in overdue where !r.done {
            let d = r.item.date.flatMap { Deadlines.days(from: today, to: $0) } ?? 0
            out.append(Entry(id: "overdue:\(r.id)", kind: .overdue, title: r.title,
                             detail: d < 0 ? "Overdue \(-d) d" : "Due", course: r.item.course, ref: r.id))
        }
        for n in notices {
            let key = NoticeLogic.key(date: n.date, course: n.course, title: n.title)
            if seen.contains(key) || n.title.isEmpty { continue }
            out.append(Entry(id: "notice:\(key)", kind: .notice, title: n.title, detail: n.date, course: n.course, ref: key))
        }
        let recent = files.filter { now.timeIntervalSince($0.modified) <= newFileDays * 86400 }
            .sorted { $0.modified > $1.modified }.prefix(maxFiles)
        for f in recent {
            out.append(Entry(id: "file:\(f.path):\(Int(f.modified.timeIntervalSince1970))", kind: .file,
                             title: (f.path as NSString).lastPathComponent,
                             detail: SyncInfo.relative(f.modified, now: now), course: f.course, ref: f.path))
        }
        if staleSources > 0 {
            out.append(Entry(id: "sync:\(today)", kind: .sync, title: "\(staleSources) chat\(staleSources == 1 ? "" : "s") not read for over a day",
                             detail: "Run sync", course: "", ref: ""))
        }
        for r in diverged where !overdue.contains(where: { $0.id == r.id }) {
            out.append(Entry(id: "diverged:\(r.id):\(r.botDone == true)", kind: .diverged, title: r.title,
                             detail: r.botDone == true ? "Done in the bot, open in the file" : "Open in the bot, done in the file",
                             course: r.item.course, ref: r.id))
        }
        return out.filter { !dismissed.contains($0.id) }
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        func item(_ id: String, _ date: String?) -> MarkdownTables.Item {
            .init(id: id, kind: .assignment, course: "cpp", num: id, title: "T", details: "", dueText: "", date: date, done: false)
        }
        let od = Deadlines.Row(item: item("a", "2026-10-10"), botId: "b", done: false)
        let done = Deadlines.Row(item: item("d", "2026-10-10"), botId: nil, done: true)
        let dv = Deadlines.Row(item: item("v", "2026-10-30"), botId: "b2", done: true, botDone: true)
        let now = Date()
        let files = [FileRow(path: "/r/cpp/2026/new.pdf", course: "cpp", modified: now.addingTimeInterval(-86400)),
                     FileRow(path: "/r/cpp/2026/old.pdf", course: "cpp", modified: now.addingTimeInterval(-30 * 86400))]
        let notices = [NoticeRow(date: "2026-10-14", course: "cpp", title: "Room change"),
                       NoticeRow(date: "2026-10-13", course: "cpp", title: "Seen one")]
        let seen: Set<String> = [NoticeLogic.key(date: "2026-10-13", course: "cpp", title: "Seen one")]
        let e = build(overdue: [od, done], today: "2026-10-15", notices: notices, seen: seen, files: files,
                      staleSources: 2, diverged: [dv], dismissed: [], now: now)
        if e.map(\.kind) != [.overdue, .notice, .file, .sync, .diverged] { f.append("kinds \(e.map(\.kind))") }
        if e.first?.detail != "Overdue 5 d" { f.append("overdue detail") }
        let skip = build(overdue: [od], today: "2026-10-15", notices: [], seen: [], files: [], staleSources: 0, diverged: [], dismissed: ["overdue:a"], now: now)
        if !skip.isEmpty { f.append("dismissed") }
        return f
    }
}
