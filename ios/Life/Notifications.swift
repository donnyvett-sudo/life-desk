import Foundation
import UserNotifications

/// Local notifications from the server's plan: the phone schedules the next 48 hours, buttons call POST /actions.
/// Refreshed whenever the app opens; the plan is stable per event and day, so a refresh replaces, never duplicates.
@MainActor
final class ReminderPlanner: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderPlanner()
    /// Only planned reminders carry this prefix; the focus-end alarm (life.focus.end) is not ours to remove.
    private let prefix = "life.plan."
    private var refreshing = false
    nonisolated private static let pendingKey = "pending.actions"

    struct Planned: Decodable {
        struct Action: Decodable { var id: String; var label: String }
        var id: String
        var at: String
        var title: String
        var body: String
        var actions: [Action]
    }

    /// The server also says whether Telegram still delivers (then the list is empty by design).
    private struct PlanResponse: Decodable { var notifications: [Planned] }

    /// Forget everything scheduled for the previous account.
    static func wipe() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    /// Deleting or confirming something needs the phone unlocked; a supplement tick from the lock screen does not.
    nonisolated static func destructive(_ id: String) -> Bool { ["x", "ay", "an", "az", "prs", "prv", "prx"].contains(String(id.split(separator: ":").first ?? "")) }

    func setUp() {
        UNUserNotificationCenter.current().delegate = self
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        await Self.flushPending()
        let center = UNUserNotificationCenter.current()
        // Ask once (when never asked); a denial is respected, not re-requested on every launch.
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
        } else if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional { return }
        guard let r = try? await LifeAPI.raw("GET", "/notifications/plan?hours=72"), r.status == 200,
              let plan = (try? JSONDecoder().decode(PlanResponse.self, from: r.data))?.notifications else { return }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()

        // One category per distinct button set; the button identifier is the server's action id.
        var categories: [String: UNNotificationCategory] = [:]
        for p in plan where !p.actions.isEmpty {
            let key = p.actions.map(\.id).joined(separator: ",")
            if categories[key] == nil {
                let acts = p.actions.map { a in UNNotificationAction(identifier: a.id, title: a.label, options: Self.destructive(a.id) ? [.authenticationRequired] : []) }
                categories[key] = UNNotificationCategory(identifier: prefix + key, actions: acts, intentIdentifiers: [])
            }
        }
        // Keep categories of notifications already delivered, so their buttons survive a refresh.
        let existing = await center.notificationCategories()
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0.identifier, $0) })
        for c in categories.values { merged[c.identifier] = c }
        center.setNotificationCategories(Set(merged.values))

        var wanted = Set<String>()
        for p in plan {
            guard let date = iso.date(from: p.at) ?? iso2.date(from: p.at), date > Date() else { continue }
            let c = UNMutableNotificationContent()
            c.title = p.title; c.body = p.body; c.sound = .default
            if !p.actions.isEmpty { c.categoryIdentifier = prefix + p.actions.map(\.id).joined(separator: ",") }
            // An interval from now is an absolute instant: it does not move when the phone changes time zone.
            wanted.insert(prefix + p.id)
            try? await center.add(UNNotificationRequest(identifier: prefix + p.id, content: c,
                                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)))
        }
        // New ones first (the same id replaces), then drop what the plan no longer has: an interrupted refresh loses nothing.
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) && !wanted.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    // Banners also while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // A button on a notification: run that action on the server.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.actionIdentifier
        guard id != UNNotificationDefaultActionIdentifier, id != UNNotificationDismissActionIdentifier else { return }
        await Self.send(action: id)
    }

    /// Run an action; if the network fails, keep it (with the time) and try again at the next foreground.
    /// A queued action is dropped after 6 hours: replayed later it would mean something else.
    nonisolated static func send(action id: String, queuedAt: Date = Date()) async {
        let body = try? JSONSerialization.data(withJSONObject: ["id": id])
        if let r = try? await LifeAPI.raw("POST", "/actions", body: body), r.status != 0, r.status < 500, r.status != 429, r.status != 401 { return }
        enqueue(id, at: queuedAt)
    }

    nonisolated private static func enqueue(_ id: String, at: Date) {
        var q = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        let entry = "\(Int(at.timeIntervalSince1970))|\(id)"
        if !q.contains(where: { $0.hasSuffix("|" + id) }) { q.append(entry) }
        UserDefaults.standard.set(Array(q.suffix(20)), forKey: pendingKey)
    }

    static func flushPending() async {
        let q = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        guard !q.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        for e in q {
            let parts = e.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let t = TimeInterval(parts[0]), Date().timeIntervalSince1970 - t < 6 * 3600 else { continue }
            await send(action: parts[1], queuedAt: Date(timeIntervalSince1970: t))
        }
    }
}
