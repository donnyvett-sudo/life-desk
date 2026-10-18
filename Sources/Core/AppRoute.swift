import Foundation

/// Where a tap goes. One vocabulary for both apps: a card on Today, a message in the Feed, a notification or a widget
/// names a destination, and each app maps it to its own screens (iPhone tabs, Mac sidebar pages).
enum AppRoute: Hashable {
    enum StudyPart: String, CaseIterable { case deadlines, exams, courses, notices }
    enum LifePart: String, CaseIterable { case sleep, food, money, habits, health, projects }

    case today
    case study(StudyPart)
    case course(String)
    case exam(String)
    case life(LifePart)
    case focus(courseId: String?)
    case cards, promises, account, feed

    /// `lifedesk://route/life/sleep`, `lifedesk://route/study/exams`, `lifedesk://route/course/<id>` ...
    init?(url: URL) {
        guard url.scheme == "lifedesk", url.host == "route" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let head = parts.first else { return nil }
        let arg = parts.count > 1 ? parts[1] : nil
        switch head {
        case "today": self = .today
        case "study": self = .study(arg.flatMap(StudyPart.init(rawValue:)) ?? .deadlines)
        case "life": guard let p = arg.flatMap(LifePart.init(rawValue:)) else { return nil }; self = .life(p)
        case "course": guard let a = arg else { return nil }; self = .course(a)
        case "exam": guard let a = arg else { return nil }; self = .exam(a)
        case "focus": self = .focus(courseId: arg)
        case "cards": self = .cards
        case "promises": self = .promises
        case "account": self = .account
        case "feed": self = .feed
        default: return nil
        }
    }

    var url: URL {
        func u(_ path: String) -> URL { URL(string: "lifedesk://route/\(path)")! }
        switch self {
        case .today: return u("today")
        case .study(let p): return u("study/\(p.rawValue)")
        case .life(let p): return u("life/\(p.rawValue)")
        case .course(let id): return u("course/\(id)")
        case .exam(let id): return u("exam/\(id)")
        case .focus(let c): return u(c.map { "focus/\($0)" } ?? "focus")
        case .cards: return u("cards")
        case .promises: return u("promises")
        case .account: return u("account")
        case .feed: return u("feed")
        }
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let all: [AppRoute] = [.today, .study(.exams), .life(.sleep), .life(.health), .course("c1"), .exam("e1"), .focus(courseId: nil), .focus(courseId: "c2"), .cards, .promises, .account, .feed]
        for r in all where AppRoute(url: r.url) != r { f.append("round trip \(r)") }
        if AppRoute(url: URL(string: "https://x/life/sleep")!) != nil { f.append("wrong scheme") }
        if AppRoute(url: URL(string: "lifedesk://route/life/nonsense")!) != nil { f.append("unknown life part") }
        if AppRoute(url: URL(string: "lifedesk://route/study")!) != .study(.deadlines) { f.append("study default") }
        return f
    }
}
