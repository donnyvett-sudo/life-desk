import Foundation

/// Search over everything Life Desk knows: deadlines, notices, course files, chats, courses (⌘K).
enum SearchIndex {
    enum Kind: Int { case deadline, notice, file, chat, course
        var label: String { ["Deadline", "Notice", "File", "Chat", "Course"][rawValue] }
    }
    struct Doc: Equatable {
        var id: String
        var kind: Kind
        var title: String
        var body: String = ""
        var ref: String = ""      // what to open: a path, an id
        fileprivate var lowerTitle: String { title.lowercased() }
        fileprivate var lowerBody: String { body.lowercased() }
    }

    /// Every query word must occur in title or body. Title hits rank first, then prefix hits, then newer documents
    /// (input order) and kind order.
    static func search(_ docs: [Doc], query: String, limit: Int = 12) -> [Doc] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        var scored: [(Int, Int, Doc)] = []
        for (i, d) in docs.enumerated() {
            let t = d.title.lowercased(), b = d.body.lowercased()
            var score = 0, ok = true
            for w in words {
                if t.contains(w) { score += t.hasPrefix(w) || t.contains(" " + w) ? 5 : 3 }
                else if b.contains(w) { score += 1 }
                else { ok = false; break }
            }
            if ok { scored.append((score, i, d)) }
        }
        scored.sort { a, b in a.0 != b.0 ? a.0 > b.0 : a.2.kind.rawValue != b.2.kind.rawValue ? a.2.kind.rawValue < b.2.kind.rawValue : a.1 < b.1 }
        return scored.prefix(limit).map(\.2)
    }

    /// A short excerpt of `body` around the first query word, for the result row.
    static func snippet(_ body: String, query: String, radius: Int = 40) -> String {
        let flat = body.replacingOccurrences(of: "\n", with: " ")
        guard let w = query.split(whereSeparator: { $0.isWhitespace }).first,
              let r = flat.range(of: String(w), options: [.caseInsensitive, .diacriticInsensitive]) else { return String(flat.prefix(radius * 2)) }
        let lo = flat.index(r.lowerBound, offsetBy: -radius, limitedBy: flat.startIndex) ?? flat.startIndex
        let hi = flat.index(r.upperBound, offsetBy: radius, limitedBy: flat.endIndex) ?? flat.endIndex
        return (lo > flat.startIndex ? "…" : "") + flat[lo..<hi] + (hi < flat.endIndex ? "…" : "")
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let docs = [
            Doc(id: "1", kind: .chat, title: "Bayes question", body: "we talked about priors and the Normal distribution"),
            Doc(id: "2", kind: .file, title: "Normal distribution slides.pdf", body: "stats101 2026"),
            Doc(id: "3", kind: .notice, title: "Quiz moved", body: "normal schedule resumes monday"),
            Doc(id: "4", kind: .deadline, title: "HW4: normal approximation"),
        ]
        let r = search(docs, query: "normal")
        if r.map(\.id) != ["4", "2", "3", "1"] && r.map(\.id) != ["2", "4", "3", "1"] { f.append("rank \(r.map(\.id))") }
        if r.last?.id != "1" && r.last?.id != "3" { f.append("body hits last") }
        if search(docs, query: "normal distribution").map(\.id) != ["2", "1"] { f.append("all words \(search(docs, query: "normal distribution").map(\.id))") }
        if !search(docs, query: "zzz").isEmpty || !search(docs, query: "  ").isEmpty { f.append("no match / blank") }
        if !snippet("aaa bbb ccc normal ddd eee", query: "normal", radius: 4).contains("normal") { f.append("snippet") }
        return f
    }
}
