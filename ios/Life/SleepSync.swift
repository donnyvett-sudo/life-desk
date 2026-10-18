import Foundation
import HealthKit

/// Sleep from Apple Health to the bot's sleep-webhook (replaces the Shortcuts automation).
/// Samples of the last 36 hours go as "start;end;value" lines; the server skips the night itself and keeps what it has.
@MainActor
final class SleepSync: ObservableObject {
    static let shared = SleepSync()
    @Published private(set) var status = "never synced"
    private let store = HKHealthStore()
    private let every: TimeInterval = 20 * 60
    private var last: Date { (UserDefaults.standard.object(forKey: "sleep.lastSync") as? Date) ?? .distantPast }

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func syncIfDue(force: Bool = false) async {
        guard Self.available, TokenStore.load() != nil else { return }
        if !force && Date().timeIntervalSince(last) < every { return }
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [type])
            let from = Date().addingTimeInterval(-36 * 3600)
            let samples = try await query(type, from: from)
            let lines = samples.compactMap(Self.line)
            guard !lines.isEmpty else { status = "no sleep samples"; return }
            let r = try await LifeAPI.functionPost("sleep-webhook", json: ["text": lines.joined(separator: "\n")])
            status = r.status == 200 ? "synced \(lines.count) samples" : "server answered \(r.status)"
            if r.status == 200 || r.status == 422 { UserDefaults.standard.set(Date(), forKey: "sleep.lastSync") }
        } catch {
            status = "Health: \(error.localizedDescription)"
        }
    }

    private func query(_ type: HKCategoryType, from: Date) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { cont in
            let p = HKQuery.predicateForSamples(withStart: from, end: Date(), options: [])
            let q = HKSampleQuery(sampleType: type, predicate: p, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, res, err in
                if let err { cont.resume(throwing: err) } else { cont.resume(returning: (res as? [HKCategorySample]) ?? []) }
            }
            store.execute(q)
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    /// One HealthKit sample as the server's text format; the stage names are the English ones `stageOf` knows.
    static func line(_ s: HKCategorySample) -> String? {
        guard let v = HKCategoryValueSleepAnalysis(rawValue: s.value) else { return nil }
        let name: String
        switch v {
        case .inBed: name = "In Bed"
        case .awake: name = "Awake"
        case .asleepCore: name = "Core"
        case .asleepDeep: name = "Deep"
        case .asleepREM: name = "REM"
        default: name = "Asleep"
        }
        return "\(iso.string(from: s.startDate));\(iso.string(from: s.endDate));\(name)"
    }
}
