import SwiftUI
import Charts

/// Small pieces shared by the Sleep, Food, Money, Focus and Today charts. Content stays opaque (no glass).

/// A progress ring: a hairline track and a trimmed arc in the area colour, a label in the middle. Past the target it stays full.
struct Ring<Label: View>: View {
    let progress: Double
    var tint: Color
    var lineWidth: CGFloat = 8
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
    }
}

/// The bubble a scrubbing finger shows inside a chart: the value, and what it belongs to under it.
struct ChartCallout: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.rowTitle).monospacedDigit().foregroundStyle(Theme.text)
            Text(caption).font(.chip).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
    }
}

extension AnnotationOverflowResolution {
    /// Keeps a callout inside the plot at both edges.
    static let inside = AnnotationOverflowResolution(x: .fit(to: .chart), y: .fit(to: .chart))
}

/// A tiny bar strip for the Today cards; the last bar (today / last night) is solid. Decorative: the card says the numbers.
struct MiniBars: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Chart {
            ForEach(values.indices, id: \.self) { i in
                BarMark(x: .value("Day", String(i)), y: .value("Value", values[i]))
                    .foregroundStyle(tint.opacity(i == values.count - 1 ? 1 : 0.45)).cornerRadius(2)
            }
        }
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

enum ChartFmt {
    /// "2026-10-15" → "10/15", the short label under a bar.
    static func md(_ iso: String) -> String { String(iso.suffix(5)).replacingOccurrences(of: "-", with: "/") }

    /// A calendar day at local midnight, so Swift Charts bins it into the right day.
    static func date(_ iso: String) -> Date? { parser.date(from: iso) }
    private static let parser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        return f
    }()

    /// "18 Oct" / "18 окт." in the app language.
    static func dayMonth(_ d: Date) -> String { d.formatted(Date.FormatStyle().day().month(.abbreviated).locale(AppLanguage.locale)) }
}
