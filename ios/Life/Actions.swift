import Foundation

/// Writes the user does from several screens: mark a deadline done (with Undo), refresh afterwards.
@MainActor
enum DeadlineActions {
    static func toggle(id: String, done: Bool, title: String) async {
        do {
            try await BotAPI.setDone(id: id, done: done)
            await BotStore.shared.refresh(afterWrite: true)
            Toasts.shared.show(done ? L("Marked done") : L("Reopened")) { Task { await toggle(id: id, done: !done, title: title) } }
        } catch {
            Toasts.shared.show(L("Could not update. Check the connection."))
        }
    }
}
