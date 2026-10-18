import Foundation
import Foundation

/// Pure helpers for the focus timer (tested in Sources/Tests).
enum FocusLogic {
    /// "24:07", or "1:05:09" from an hour up.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let (h, m, sec) = (s / 3600, (s % 3600) / 60, s % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
    static func minutes(_ m: Int) -> String {
        m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }
    /// Seconds of focus between two instants, never negative and capped at the planned length.
    static func elapsedSeconds(from start: Date, to end: Date, planned: Int) -> Double {
        min(Double(planned) * 60, max(0, end.timeIntervalSince(start)))
    }
    /// Minutes for display: rounded once, from the summed seconds of all segments of a sitting.
    static func minutes(fromSeconds s: Double) -> Int { max(0, Int((s / 60).rounded())) }
    static func parse(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }
    static func selfTest() -> [String] {
        var f: [String] = []
        if clock(1447) != "24:07" { f.append("clock") }
        if clock(3909) != "1:05:09" { f.append("clock hours") }
        if clock(-4) != "00:00" { f.append("clock negative") }
        if clock(0.2) != "00:01" { f.append("clock rounds up") }
        if minutes(25) != "25 min" || minutes(370) != "6 h 10 min" { f.append("minutes") }
        if parse("2026-10-09T10:15:30.123+00:00") == nil || parse("2026-10-09T10:15:30Z") == nil { f.append("parse") }
        return f
    }
}

/// A paused sitting, kept in UserDefaults so it survives a restart.
struct FocusPaused: Codable, Equatable {
    var label: String
    var courseId: String?
    var courseCode: String?
    var remaining: Double
    var plannedMin: Int
    /// Focus time of earlier segments, in seconds (rounded to minutes only once, at the end).
    var bankedSeconds: Double
    /// Bot session whose stop was not confirmed; it is closed again before the next resume.
    var pendingStopId: String?
    var savedAt: Date

    init(label: String, courseId: String?, courseCode: String?, remaining: Double, plannedMin: Int,
         bankedSeconds: Double, pendingStopId: String?, savedAt: Date) {
        self.label = label; self.courseId = courseId; self.courseCode = courseCode; self.remaining = remaining
        self.plannedMin = plannedMin; self.bankedSeconds = bankedSeconds; self.pendingStopId = pendingStopId
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey {
        case label, courseId, courseCode, remaining, plannedMin, bankedSeconds, bankedMin, pendingStopId, savedAt
    }

    /// Reads records written by earlier versions (whole minutes in `bankedMin`, no `pendingStopId`).
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        courseId = try c.decodeIfPresent(String.self, forKey: .courseId)
        courseCode = try c.decodeIfPresent(String.self, forKey: .courseCode)
        remaining = try c.decode(Double.self, forKey: .remaining)
        plannedMin = try c.decode(Int.self, forKey: .plannedMin)
        if let sec = try c.decodeIfPresent(Double.self, forKey: .bankedSeconds) { bankedSeconds = sec }
        else { bankedSeconds = Double(try c.decodeIfPresent(Int.self, forKey: .bankedMin) ?? 0) * 60 }
        pendingStopId = try c.decodeIfPresent(String.self, forKey: .pendingStopId)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(courseId, forKey: .courseId)
        try c.encodeIfPresent(courseCode, forKey: .courseCode)
        try c.encode(remaining, forKey: .remaining)
        try c.encode(plannedMin, forKey: .plannedMin)
        try c.encode(bankedSeconds, forKey: .bankedSeconds)
        try c.encodeIfPresent(pendingStopId, forKey: .pendingStopId)
        try c.encode(savedAt, forKey: .savedAt)
    }

    static let key = "focus.paused"
    static let maxAge: TimeInterval = 12 * 3600

    static func save(_ p: FocusPaused, to d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(p) { d.set(data, forKey: key) }
    }
    static func load(from d: UserDefaults = .standard, now: Date = Date()) -> FocusPaused? {
        guard let data = d.data(forKey: key), let p = try? JSONDecoder().decode(FocusPaused.self, from: data) else { return nil }
        guard now.timeIntervalSince(p.savedAt) < maxAge else { clear(in: d); return nil }
        return p
    }
    static func clear(in d: UserDefaults = .standard) { d.removeObject(forKey: key) }

    /// Focus seconds of earlier segments of a sitting whose current segment is a running bot session.
    static func saveBanked(_ seconds: Double, session: String, to d: UserDefaults = .standard) {
        d.set(seconds, forKey: "focus.bankedSec.\(session)")
    }
    static func banked(session: String, from d: UserDefaults = .standard) -> Double {
        if let v = d.object(forKey: "focus.bankedSec.\(session)") as? Double { return v }
        return Double(d.integer(forKey: "focus.banked.\(session)")) * 60  // earlier versions stored minutes
    }
    static func clearBanked(session: String, in d: UserDefaults = .standard) {
        d.removeObject(forKey: "focus.bankedSec.\(session)")
        d.removeObject(forKey: "focus.banked.\(session)")
    }
}
