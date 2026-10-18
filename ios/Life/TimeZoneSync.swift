import Foundation

/// The schedule, quiet hours and "today" on the server follow the time zone in the user's settings. When the phone is
/// somewhere else (a trip home, winter break), tell the server once so reminders keep to local time.
enum TimeZoneSync {
    static func run() async {
        let zone = TimeZone.current.identifier
        guard UserDefaults.standard.string(forKey: "tz.sent") != zone,
              let r = try? await LifeAPI.raw("GET", "/settings"), r.status == 200,
              let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any], let server = j["tz"] as? String else { return }
        if server == zone { UserDefaults.standard.set(zone, forKey: "tz.sent"); return }
        let body = try? JSONSerialization.data(withJSONObject: ["tz": zone])
        if let p = try? await LifeAPI.raw("PUT", "/settings", body: body), p.status == 200 {
            UserDefaults.standard.set(zone, forKey: "tz.sent")
            await ReminderPlanner.shared.refresh()
        }
    }
}
