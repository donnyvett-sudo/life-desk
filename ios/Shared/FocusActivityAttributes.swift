import ActivityKit
import Foundation

/// The running focus session as the lock screen and Dynamic Island show it.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var paused: Bool
        /// Seconds left when paused (the timer is frozen then).
        var remaining: TimeInterval
    }
    var label: String
    var plannedMin: Int
}
