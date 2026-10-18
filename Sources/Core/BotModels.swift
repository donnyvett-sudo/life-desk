import Foundation
import Combine

/// The bot's /study overview (only the fields Life Desk uses).
struct BotStudy: Codable {
    struct Course: Codable { var id: String; var short: String; var title: String? = nil; var aiPolicy: String? = nil }
    struct Assignment: Codable {
        var id: String; var course: Course?; var title: String; var dueDate: String?; var done: Bool
        var details: String? = nil; var dueNote: String? = nil; var fromStudyAgent: Bool? = nil
    }
    struct Exam: Codable, Identifiable {
        var id: String; var course: Course?; var kind: String; var title: String; var topic: String?
        var date: String?; var dateTo: String?; var tentative: Bool?; var notes: String?
    }
    struct Session: Codable, Identifiable { var id: String; var course: Course?; var kind: String; var title: String?; var date: String; var start: String; var end: String; var room: String? }
    var today: String
    var assignments: [Assignment]
    var recentlyDone: [Assignment]
    var sessions: [Session]
    var exams: [Exam]? = nil
    var courses: [Course]?
    var focus: Focus?

    /// Missing lists are empty and unknown fields are ignored, so a bot update does not break the app.
    init(today: String, assignments: [Assignment], recentlyDone: [Assignment], sessions: [Session], courses: [Course]? = nil, focus: Focus? = nil) {
        self.today = today; self.assignments = assignments; self.recentlyDone = recentlyDone
        self.sessions = sessions; self.courses = courses; self.focus = focus
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        today = try c.decodeIfPresent(String.self, forKey: .today) ?? ""
        assignments = try c.decodeIfPresent([Assignment].self, forKey: .assignments) ?? []
        recentlyDone = try c.decodeIfPresent([Assignment].self, forKey: .recentlyDone) ?? []
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        exams = try c.decodeIfPresent([Exam].self, forKey: .exams)
        courses = try c.decodeIfPresent([Course].self, forKey: .courses)
        focus = try c.decodeIfPresent(Focus.self, forKey: .focus)
    }
    private enum Keys: String, CodingKey { case today, assignments, recentlyDone, sessions, exams, courses, focus }

    /// Focus-session totals and the running session, as the bot reports them.
    struct Focus: Codable {
        struct ByCourse: Codable { var course: Course?; var minutes: Int }
        struct Running: Codable { var id: String; var plannedMin: Int; var startedAt: String; var course: Course? }
        var weekMin: Int
        var todayMin: Int
        var byCourse: [ByCourse]
        var running: Running?
    }
}
