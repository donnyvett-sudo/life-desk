import ActivityKit
import Combine
import Foundation

/// Mirrors the running focus session on the lock screen and in the Dynamic Island.
/// Changes are applied one after another, always from the model's current state (never from a stale event).
@MainActor
final class FocusActivityController {
    static let shared = FocusActivityController()
    private var bag = Set<AnyCancellable>()
    private var chain: Task<Void, Never>?

    func endAll() {
        Task { for a in Activity<FocusActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }

    func start() {
        guard bag.isEmpty else { return }
        let f = FocusModel.shared
        f.$phase.removeDuplicates().sink { [weak self] _ in
            // @Published sends before the value is stored: queue on the next turn and read the live state then.
            DispatchQueue.main.async { self?.enqueue() }
        }.store(in: &bag)
        enqueue()
    }

    private func enqueue() {
        let previous = chain
        chain = Task { @MainActor [weak self] in
            await previous?.value
            await self?.apply()
        }
    }

    private func apply() async {
        let f = FocusModel.shared
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        switch f.phase {
        case .running, .paused:
            let paused = f.phase == .paused
            let state = FocusActivityAttributes.ContentState(endDate: f.endDate, paused: paused, remaining: f.remaining)
            let content = ActivityContent(state: state, staleDate: paused ? nil : f.endDate.addingTimeInterval(60))
            // Only a live activity can be reused: one the user swiped away or the system ended is replaced.
            if let a = Activity<FocusActivityAttributes>.activities.first(where: { $0.activityState == .active }) {
                await a.update(content)
            } else {
                _ = try? Activity.request(attributes: FocusActivityAttributes(label: f.label, plannedMin: f.plannedMin), content: content)
            }
        case .idle, .finished:
            for a in Activity<FocusActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
