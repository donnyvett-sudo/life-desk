import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LifeWidgetsBundle: WidgetBundle {
    var body: some Widget { FocusLiveActivity(); DueWidget() }
}

private func clock(_ s: TimeInterval) -> String {
    let n = max(0, Int(s.rounded(.up)))
    return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, (n % 3600) / 60, n % 60) : String(format: "%02d:%02d", n / 60, n % 60)
}

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            // Lock screen and notification banner
            HStack(spacing: 14) {
                Image(systemName: "timer").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.label.isEmpty ? L("Focus") : AppLanguage.tr(context.attributes.label)).font(.headline).lineLimit(1)
                    Text(context.state.paused ? L("Paused") : L("Until \(context.state.endDate.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.locale)))"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if context.state.paused {
                    Text(clock(context.state.remaining)).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                } else {
                    Text(timerInterval: Date()...max(Date(), context.state.endDate), countsDown: true)
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().multilineTextAlignment(.trailing).lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: 140)
                }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "timer").foregroundStyle(.orange) }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.paused { Text(clock(context.state.remaining)).monospacedDigit() }
                    else { Text(timerInterval: Date()...max(Date(), context.state.endDate), countsDown: true).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: 90) }
                }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.label.isEmpty ? L("Focus") : AppLanguage.tr(context.attributes.label)).lineLimit(1) }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.orange)
            } compactTrailing: {
                if context.state.paused { Text(clock(context.state.remaining)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: 56) }
                else { Text(timerInterval: Date()...max(Date(), context.state.endDate), countsDown: true).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: 56) }
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.orange)
            }
        }
    }
}
