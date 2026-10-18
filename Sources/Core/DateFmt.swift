import Foundation

/// The app's date strings (yyyy-MM-dd, HH:mm) in one place. Formatters are built once.
enum DateFmt {
    private static func make(_ format: String, tz: TimeZone?) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        if let tz { f.timeZone = tz }
        return f
    }
    private static let dayLocal = make("yyyy-MM-dd", tz: nil)
    private static let dayUTC = make("yyyy-MM-dd", tz: TimeZone(identifier: "UTC"))
    private static let clockLocal = make("HH:mm", tz: nil)
    private static let lock = NSLock()

    /// Calendar day of `date` as yyyy-MM-dd in the Mac's time zone.
    static func today(_ date: Date = Date()) -> String {
        lock.lock(); defer { lock.unlock() }
        dayLocal.timeZone = .current
        return dayLocal.string(from: date)
    }
    /// yyyy-MM-dd at 00:00 UTC (day arithmetic that DST cannot disturb), nil if malformed.
    static func parseDay(_ s: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return dayUTC.date(from: s)
    }
    static func clock(_ date: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        clockLocal.timeZone = .current
        return clockLocal.string(from: date)
    }
    /// Whole days from one yyyy-MM-dd to another.
    static func days(from a: String, to b: String) -> Int? {
        guard let x = parseDay(a), let y = parseDay(b) else { return nil }
        return Int((y.timeIntervalSince(x) / 86400).rounded())
    }
}
