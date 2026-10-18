import Foundation

/// What the home-screen widget shows. The app writes it into the App Group after every refresh; the widget only reads it
/// (no token, no network in the extension).
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable { var title: String; var course: String; var date: String }   // date: yyyy-MM-dd
    var updated: Date
    var deadlines: [Item]
    var exam: Item?

    /// App Group id, injected at build time (APP_GROUP_ID in Config.local.xcconfig -> Info.plist key LifeAppGroup).
    static let group = (Bundle.main.object(forInfoDictionaryKey: "LifeAppGroup") as? String) ?? "group.local.lifedesk.life"
    static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot? {
        guard let d = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults(suiteName: Self.group)?.set(d, forKey: Self.key) }
    }

    /// Whole days from today to a yyyy-MM-dd date in the user's calendar; nil when unparsable.
    static func days(to date: String, from now: Date = Date()) -> Int? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: date) else { return nil }
        let c = Calendar.current
        return c.dateComponents([.day], from: c.startOfDay(for: now), to: c.startOfDay(for: d)).day
    }
}
