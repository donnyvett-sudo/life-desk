import Foundation
import UserNotifications

/// Shows banners even while Life Desk is the frontmost app.
final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotifications()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

/// Keeps the system's pending notifications equal to `Reminders.plan` (rebuilt whenever files or the bot change).
@MainActor
enum ReminderScheduler {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "reminders") }

    /// Asks for permission when switching on; returns whether notifications are allowed.
    static func enable() async -> Bool {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(ok, forKey: "reminders")
        if ok { await reschedule() } else { await clear() }
        return ok
    }

    static func disable() async {
        UserDefaults.standard.set(false, forKey: "reminders")
        await clear()
    }

    private static func clear() async {
        let c = UNUserNotificationCenter.current()
        let ids = await c.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("reminder.") }
        c.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Sources not read for over 24 h: updates the sidebar badge, returns the count.
    @discardableResult
    static func refreshSyncBadge() -> Int {
        let rows = MarkdownTables.tables(MarkdownTables.read("\(Config.resources)/sources.md")).first?.rows ?? []
        let n = SyncInfo.staleRows(rows)
        SidebarBadges.shared.syncStale = n
        return n
    }

    private static var running = false
    private static var again = false

    /// One rebuild at a time: a call that arrives meanwhile asks for one more pass instead of interleaving.
    static func reschedule() async {
        UNUserNotificationCenter.current().delegate = ForegroundNotifications.shared
        if running { again = true; return }
        running = true
        repeat {
            again = false
            await rebuild()
        } while again
        running = false
    }

    private static func rebuild() async {
        let stale = refreshSyncBadge()
        guard enabled else { return }
        let items = DeadlineActions.loadItems()
        let rows = Deadlines.rows(items, study: BotStore.shared.study)
        let doneIDs = Set(rows.filter(\.done).map(\.id))
        let plan = Reminders.plan(items, done: { $0.done || doneIDs.contains($0.id) }, label: Theme.short, now: Date())
        await clear()
        let c = UNUserNotificationCenter.current()
        for r in plan {
            let content = UNMutableNotificationContent()
            content.title = r.title; content.body = r.body; content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.fire)
            let req = UNNotificationRequest(identifier: r.id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await c.add(req)
        }
        if stale > 0 {
            // One nudge at the next 09:00 (nothing if the app is told fresh data arrived: the next rebuild removes it).
            var comps = DateComponents(); comps.hour = 9; comps.minute = 0
            let content = UNMutableNotificationContent()
            content.title = "Sync is out of date"
            content.body = "\(stale) chat\(stale == 1 ? "" : "s") not read for over a day."
            content.sound = .default
            let req = UNNotificationRequest(identifier: "reminder.sync", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await c.add(req)
        }
    }
}
