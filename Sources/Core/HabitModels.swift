import Foundation

/// The bot's /habits overview.
struct HabitsOverview: Decodable {
    struct Habit: Decodable, Identifiable, Equatable {
        var id: String; var title: String; var kind: String; var target: Int
        var note: String?; var isHard: Bool; var active: Bool; var due: Bool
        var doneToday: Bool; var streak: Int; var weekDone: Int; var dates: [String]
    }
    var today: String
    var from: String
    var habits: [Habit]
    var dueCount: Int
}

enum HabitLogic {
    /// "3 of 5 this week" for weekly habits, "5 day streak" for daily ones.
    static func progress(_ h: HabitsOverview.Habit) -> String {
        h.kind == "weekly" ? "\(h.weekDone) of \(h.target) this week" : h.streak > 0 ? "\(h.streak) day streak" : "no streak yet"
    }

    /// The last `days` days ending today as done / not, newest last, for the little strip next to a habit.
    static func strip(_ h: HabitsOverview.Habit, today: String, days: Int = 14) -> [Bool] {
        let done = Set(h.dates)
        return (0..<days).reversed().map { back in
            guard let d = QuickEntry.add(days: -back, to: today) else { return false }
            return done.contains(d)
        }
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let j = Data(#"{"today":"2026-10-16","from":"2026-07-27","dueCount":1,"habits":[{"id":"h1","title":"Reading","kind":"daily","target":1,"note":null,"isHard":false,"active":true,"due":true,"doneToday":false,"streak":2,"weekDone":3,"lastDone":"2026-10-15","dates":["2026-10-15","2026-10-14","2026-10-10"]},{"id":"h2","title":"Gym","kind":"weekly","target":4,"days":null,"note":"hard","isHard":true,"active":true,"due":false,"doneToday":true,"streak":0,"weekDone":2,"lastDone":null,"dates":[]}]}"#.utf8)
        guard let o = try? JSONDecoder().decode(HabitsOverview.self, from: j) else { return ["decode"] }
        if progress(o.habits[0]) != "2 day streak" || progress(o.habits[1]) != "2 of 4 this week" { f.append("progress") }
        let s = strip(o.habits[0], today: "2026-10-16", days: 7)
        if s != [true, false, false, false, true, true, false] { f.append("strip \(s)") }
        return f
    }
}
