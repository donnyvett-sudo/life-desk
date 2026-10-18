import BackgroundTasks
import SwiftUI

@main
struct LifeApp: App {
    @Environment(\.scenePhase) private var phase
    init() { BackgroundRefresh.register() }
    var body: some Scene {
        WindowGroup { ContentView() }
            .onChange(of: phase) { _, p in if p == .background { BackgroundRefresh.schedule() } }
    }
}

/// iOS wakes the app now and then (about every few hours, its choice) to renew the 48-hour notification plan and sync sleep,
/// so reminders keep coming even when the app has not been opened for a day.
enum BackgroundRefresh {
    static let id = "local.lifedesk.life.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            schedule()   // chain the next wake-up first
            let work = Task { @MainActor in
                await SleepSync.shared.syncIfDue()
                await ReminderPlanner.shared.refresh()
                await BotStore.shared.refresh()           // the widget shows fresh deadlines without opening the app
                WidgetFeed.publish(BotStore.shared.study)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(r)
    }
}
