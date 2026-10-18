import Foundation

/// Collects the documents for ⌘K search from the workspace and the app's own state.
enum SearchSources {
    /// First 6000 characters of a chat, built message by message (never the whole text).
    private static func chatBody(_ c: ChatState) -> String {
        var out = ""
        for m in c.messages {
            out += m.text.prefix(6000 - out.count) + " "
            if out.count >= 6000 { break }
        }
        return out
    }

    @MainActor static func collect() async -> [SearchIndex.Doc] {
        let res = Config.resources
        let chats = ChatModel.shared.chats.sorted { $0.updated > $1.updated }.map { c in
            SearchIndex.Doc(id: "chat:\(c.id)", kind: .chat, title: c.title.isEmpty ? "New chat" : c.title,
                            body: chatBody(c), ref: c.id.uuidString)
        }
        let study = BotStore.shared.study
        let items = DeadlineActions.loadItems()
        let deadlines = Deadlines.rows(items, study: study).map {
            SearchIndex.Doc(id: "dl:\($0.id)", kind: .deadline, title: $0.title,
                            body: [$0.item.details, $0.item.dueText, Theme.short($0.item.course)].joined(separator: " "), ref: $0.id)
        } + items.filter { $0.kind == .exam }.map {
            SearchIndex.Doc(id: "dl:\($0.id)", kind: .deadline, title: "Exam: " + $0.title,
                            body: [$0.dueText, Theme.short($0.course)].joined(separator: " "), ref: $0.id)
        }
        let notices = (MarkdownTables.tables(MarkdownTables.read("\(res)/notices.md")).first?.rows ?? []).enumerated().compactMap { (i, r) -> SearchIndex.Doc? in
            guard let t = r["title"], !t.isEmpty else { return nil }
            return SearchIndex.Doc(id: "notice:\(i)", kind: .notice, title: t,
                                   body: [r["date"], r["course"], r["source"]].compactMap { $0 }.joined(separator: " "))
        }
        let heavy = await Task.detached { () -> [SearchIndex.Doc] in
            var out: [SearchIndex.Doc] = []
            let fm = FileManager.default
            for course in MarkdownTables.courseFolders(resources: res) {
                let info = (try? String(contentsOfFile: "\(res)/\(course)/course-info.md", encoding: .utf8)) ?? ""
                out.append(SearchIndex.Doc(id: "course:\(course)", kind: .course, title: Theme.short(course), body: String(info.prefix(3000)), ref: course))
                let root = "\(res)/\(course)/2026"
                let summaries = CourseInfo.summaries(filesMd: (try? String(contentsOfFile: "\(root)/files.md", encoding: .utf8)) ?? "")
                guard let en = fm.enumerator(atPath: root) else { continue }
                var n = 0
                while let rel = en.nextObject() as? String, n < 1500 {
                    var isDir: ObjCBool = false
                    guard !(rel as NSString).lastPathComponent.hasPrefix("."), fm.fileExists(atPath: "\(root)/\(rel)", isDirectory: &isDir), !isDir.boolValue else { continue }
                    n += 1
                    out.append(SearchIndex.Doc(id: "file:\(course)/\(rel)", kind: .file, title: (rel as NSString).lastPathComponent,
                                               body: Theme.short(course) + " " + (summaries[rel] ?? ""), ref: "\(root)/\(rel)"))
                }
            }
            return out
        }.value
        return deadlines + notices + heavy + chats
    }
}
