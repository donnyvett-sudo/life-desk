import Foundation

/// The bot's /sleep history: nights with bed and wake times as local "HH:mm".
struct SleepHistory: Decodable {
    struct Night: Decodable, Identifiable, Equatable {
        var date: String
        var bed: String
        var wake: String
        var asleepMin: Int
        var deepMin: Int?
        var remMin: Int?
        var coreMin: Int?
        var awakeMin: Int?
        var verdict: String
        var notes: [String]
        var id: String { date }
    }
    struct Target: Decodable { var bed: String; var wake: String }
    var target: Target
    var today: String
    var days: Int
    var nights: [Night]
}

enum SleepLogic {
    static func minutes(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
        return p[0] * 60 + p[1]
    }

    /// Minutes between a clock time and the target, wrapped to -720...720 (target 23:00, actual 01:40 → +160).
    static func clockDiff(_ actual: Int, _ target: Int) -> Int {
        var d = actual - target
        if d > 720 { d -= 1440 }
        if d < -720 { d += 1440 }
        return d
    }

    /// The target length of a night (bed to wake over midnight).
    static func targetSleep(_ t: SleepHistory.Target) -> Int {
        guard let b = minutes(t.bed), let w = minutes(t.wake) else { return 480 }
        return (w - b + 1440) % 1440
    }

    struct Summary: Equatable {
        var nights: Int
        var avgAsleep: Int?
        var avgBedDiff: Int?
        var onTrack: Int
    }

    static func summary(_ h: SleepHistory) -> Summary {
        let n = h.nights
        guard !n.isEmpty else { return Summary(nights: 0, avgAsleep: nil, avgBedDiff: nil, onTrack: 0) }
        let target = minutes(h.target.bed) ?? 23 * 60
        let diffs = n.compactMap { minutes($0.bed) }.map { clockDiff($0, target) }
        return Summary(nights: n.count, avgAsleep: n.reduce(0) { $0 + $1.asleepMin } / n.count,
                       avgBedDiff: diffs.isEmpty ? nil : diffs.reduce(0, +) / diffs.count,
                       onTrack: n.filter { $0.verdict == "good" }.count)
    }

    /// "7 h 05 m", "45 m".
    static func duration(_ m: Int) -> String { m >= 60 ? String(format: "%d h %02d m", m / 60, m % 60) : "\(m) m" }

    /// "+1 h 25 m later" / "20 m earlier" / "on time".
    static func diffLabel(_ d: Int) -> String {
        if abs(d) < 5 { return "on time" }
        return duration(abs(d)) + (d > 0 ? " later" : " earlier")
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        if clockDiff(100, 23 * 60) != 160 || clockDiff(22 * 60 + 30, 23 * 60) != -30 { f.append("clockDiff") }
        if targetSleep(.init(bed: "23:00", wake: "07:00")) != 480 || minutes("25:00") != nil || minutes("7:05") != 425 { f.append("minutes") }
        let j = Data(#"{"target":{"bed":"23:00","wake":"07:00"},"today":"2026-10-16","days":14,"nights":[{"date":"2026-10-15","bed":"02:35","wake":"08:51","asleepMin":373,"deepMin":60,"remMin":117,"coreMin":null,"awakeMin":10,"verdict":"bad","notes":["late"]},{"date":"2026-10-14","bed":"23:10","wake":"07:00","asleepMin":450,"deepMin":null,"remMin":null,"coreMin":null,"awakeMin":null,"verdict":"good","notes":[]}]}"#.utf8)
        guard let h = try? JSONDecoder().decode(SleepHistory.self, from: j) else { return ["decode"] }
        let s = summary(h)
        if s.nights != 2 || s.avgAsleep != 411 || s.onTrack != 1 { f.append("summary \(s)") }
        if diffLabel(85) != "1 h 25 m later" || diffLabel(-20) != "20 m earlier" || diffLabel(3) != "on time" || duration(425) != "7 h 05 m" { f.append("labels") }
        return f
    }
}
