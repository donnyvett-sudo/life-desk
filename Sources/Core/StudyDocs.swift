import Foundation
import Combine

/// Read-only copies of the Study Workspace files, sent by the Mac's sync: notices, course info, files, exam topics.
@MainActor
final class StudyDocsStore: ObservableObject {
    static let shared = StudyDocsStore()

    struct Notice: Identifiable, Equatable {
        var key: String; var date: String; var course: String; var title: String; var source: String; var seen: Bool
        var id: String { key }
    }
    struct File: Identifiable, Equatable {
        var key: String; var course: String; var path: String; var size: Int; var modified: String; var summary: String
        var id: String { key }
    }

    @Published private(set) var notices: [Notice] = []
    @Published private(set) var courseInfo: [String: String] = [:]
    @Published private(set) var files: [File] = []
    @Published private(set) var examTopics: [String: [String]] = [:]
    @Published private(set) var loaded = false
    @Published private(set) var unsupported = false
    @Published private(set) var failed = false

    func reset() { notices = []; courseInfo = [:]; files = []; examTopics = [:]; loaded = false; unsupported = false; failed = false }

    var unreadNotices: Int { notices.filter { !$0.seen }.count }

    nonisolated static func parse(_ data: Data) -> (notices: [Notice], info: [String: String], files: [File], topics: [String: [String]])? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = j["docs"] as? [[String: Any]] else { return nil }
        var notices: [Notice] = [], files: [File] = []
        var info: [String: String] = [:], topics: [String: [String]] = [:]
        for d in list {
            guard let kind = d["kind"] as? String, let key = d["key"] as? String, let v = d["data"] as? [String: Any] else { continue }
            switch kind {
            case "notice":
                notices.append(Notice(key: key, date: v["date"] as? String ?? "", course: v["course"] as? String ?? "",
                                      title: v["title"] as? String ?? "", source: v["source"] as? String ?? "", seen: !(d["seen_at"] is NSNull) && d["seen_at"] != nil))
            case "course_info": if let m = v["markdown"] as? String { info[key] = m }
            case "exam_topics": if let t = v["topics"] as? [String] { topics[key] = t }
            case "file":
                files.append(File(key: key, course: v["course"] as? String ?? "", path: v["path"] as? String ?? key,
                                  size: v["size"] as? Int ?? 0, modified: v["modified"] as? String ?? "", summary: v["summary"] as? String ?? ""))
            default: break
            }
        }
        notices.sort { ($0.date, $0.key) > ($1.date, $1.key) }
        files.sort { ($0.modified, $0.key) > ($1.modified, $1.key) }
        return (notices, info, files, topics)
    }

    func refresh() async {
        guard let r = try? await BotAPI.raw("GET", "/study/docs") else { failed = !loaded; return }
        if r.status == 404 { unsupported = true; loaded = true; failed = false; return }
        guard r.status == 200, let p = Self.parse(r.data) else { failed = !loaded; return }
        notices = p.notices; courseInfo = p.info; files = p.files; examTopics = p.topics
        loaded = true; unsupported = false; failed = false
    }

    func markAllSeen() async {
        for i in notices.indices { notices[i].seen = true }
        _ = try? await BotAPI.raw("POST", "/study/notices/seen", body: Data("{}".utf8))
    }

    nonisolated static func selfTest() -> [String] {
        var f: [String] = []
        let d = Data(##"{"docs":[{"kind":"notice","key":"k1","data":{"date":"2026-10-09","course":"cpp","title":"Room","source":"QQ"},"seen_at":null},{"kind":"notice","key":"k2","data":{"date":"2026-10-12","title":"New"},"seen_at":"2026-10-13T00:00:00Z"},{"kind":"course_info","key":"cpp","data":{"markdown":"# C++"}},{"kind":"exam_topics","key":"cpp","data":{"topics":["a","b"]}},{"kind":"file","key":"cpp/x.pdf","data":{"course":"cpp","path":"x.pdf","size":10,"modified":"2026-10-10T10:00:00","summary":"slides"}},{"kind":"bad"}]}"##.utf8)
        guard let p = parse(d) else { return ["parse"] }
        if p.notices.map(\.key) != ["k2", "k1"] || p.notices[0].seen != true || p.notices[1].seen != false { f.append("notices \(p.notices)") }
        if p.info["cpp"] != "# C++" || p.topics["cpp"] != ["a", "b"] || p.files.first?.summary != "slides" { f.append("docs") }
        return f
    }
}
