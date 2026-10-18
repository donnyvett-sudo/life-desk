import Foundation
import Combine

/// Shared live state: bot overview (cached; offline falls back to the cache/files).
@MainActor
final class BotStore: ObservableObject {
    static let shared = BotStore()
    @Published var study: BotStudy? = BotAPI.cachedStudy()
    @Published var fetchedAt: Date? = BotAPI.cacheDate()
    @Published var error: BotAPI.Err?
    @Published private(set) var focusLog = FocusLogStore.load()
    var offline: Bool { error != nil }

    /// Drops everything of the previous account (disk cache included).
    func reset() { BotAPI.clearCache(); study = nil; fetchedAt = nil; error = nil }
    private var inflight: Task<Void, Never>?

    /// One request at a time: callers that arrive while it runs wait for the same answer.
    /// `afterWrite`: a request already in flight may predate the change, so wait for it and ask again.
    func refresh(afterWrite: Bool = false) async {
        if let t = inflight {
            await t.value
            if !afterWrite { return }
            if let again = inflight { return await again.value }
        }
        let t = Task { @MainActor in
            defer { inflight = nil }
            let dayBefore = DateFmt.today()
            do {
                study = try await BotAPI.fetchStudy(); fetchedAt = Date(); self.error = nil
                // A request that straddled midnight cannot be told apart from yesterday's total: skip it.
                if let m = study?.focus?.todayMin, DateFmt.today() == dayBefore {
                    focusLog.record(day: dayBefore, minutes: m); FocusLogStore.save(focusLog)
                }
            } catch let e as BotAPI.Err { self.error = e } catch is CancellationError { } catch { self.error = .network }
        }
        inflight = t
        await t.value
    }

    /// Chip text for a page header: why the data may be stale ("No connection · 12 min ago"), nil when fresh.
    var statusText: String? {
        guard let error else { return nil }
        guard let at = fetchedAt else { return error.message }
        let m = max(0, Int(Date().timeIntervalSince(at) / 60))
        let age = m < 1 ? "just now" : m < 60 ? "\(m) min ago" : m < 1440 ? "\(m / 60) h ago" : "\(m / 1440) d ago"
        return error.message + " · data from " + age
    }
}
