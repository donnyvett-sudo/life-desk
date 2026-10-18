import SwiftUI

// Components from docs/DESIGN.md. Pages are built from these only: no ad-hoc fills, radii or font sizes.

extension Font {
    #if os(iOS)
    // On the phone the tokens follow Dynamic Type (text styles); on the Mac they stay at their fixed point sizes.
    static let pageTitle = Font.system(.title, design: .serif).weight(.semibold)
    static let rowTitle = Font.subheadline.weight(.medium)
    static let body13 = Font.footnote
    static let meta = Font.caption
    static let chip = Font.caption2.weight(.medium)
    static let sectionLabel = Font.caption2.weight(.semibold)
    static let bigNumber = Font.system(.title, design: .serif).weight(.semibold)
    #else
    static let pageTitle = Font.system(size: 28, weight: .semibold, design: .serif)
    static let rowTitle = Font.system(size: 14, weight: .medium)
    static let body13 = Font.system(size: 13)
    static let meta = Font.system(size: 12)
    static let chip = Font.system(size: 11, weight: .medium)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let bigNumber = Font.system(size: 26, weight: .semibold, design: .serif)
    #endif
}

/// A page: scrolls, content column ≤ 780 pt centred, title in serif with an optional one-line summary under it.
struct PageView<Content: View, Trailing: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let title: String
    var summary: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.pageTitle).foregroundStyle(Theme.text)
                        if let summary { Text(summary).font(.body13).foregroundStyle(Theme.muted) }
                    }
                    Spacer(minLength: 12)
                    trailing()
                }
                content()
            }
            .padding(sizeClass == .compact ? 16 : 28)   // phone: tighter; Mac and iPad: 28
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
    }
}
extension PageView where Trailing == EmptyView {
    init(title: String, summary: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, summary: summary, trailing: { EmptyView() }, content: content)
    }
}

/// Section label + optional count; content below.
struct Section2<Content: View>: View {
    let title: String
    var count: Int? = nil
    var tone: Tone = .neutral
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title.uppercased()).font(.sectionLabel).tracking(0.6)
                    .foregroundStyle(tone == .neutral ? Theme.muted : tone.color)
                if let count { Text("\(count)").font(.chip).monospacedDigit().foregroundStyle(Theme.muted) }
            }
            content()
        }
    }
}

/// A group of related rows on one surface, hairline dividers between rows.
struct Group2<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct Hairline: View { var body: some View { Rectangle().fill(Theme.line).frame(height: 1) } }

/// A row inside a Group2: hover fill, optional click, divider is added by the caller via `Rows`.
struct RowButton<Content: View>: View {
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @State private var hover = false
    var body: some View {
        let inner = content().padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(hover && action != nil ? Theme.surface2 : .clear)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
        if let action { Button(action: action) { inner }.buttonStyle(.plain) } else { inner }
    }
}

/// Rows of a collection with hairlines between them.
struct Rows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row
    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
            if i > 0 { Hairline() }
            row(item)
        }
    }
}

enum Tone {
    case neutral, accent, good, warn, bad
    var color: Color {
        switch self {
        case .neutral: Theme.muted
        case .accent: Theme.accent
        case .good: Theme.good
        case .warn: Theme.warn
        case .bad: Theme.bad
        }
    }
}

/// Short state label: always words, tinted by tone.
struct Chip: View {
    let text: String
    var tone: Tone = .neutral
    var body: some View {
        Text(text).font(.chip).monospacedDigit().lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(tone.color)
            .background(tone.color.opacity(tone == .neutral ? 0.12 : 0.16), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// Course = coloured dot + name. Never a filled capsule.
struct CourseTag: View {
    let code: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.course(code)).frame(width: 7, height: 7)
            Text(Theme.short(code)).font(.meta).foregroundStyle(Theme.muted)
        }
    }
}

struct Stat: View {
    let value: String
    let label: String
    var tone: Tone = .neutral
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.bigNumber).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55).foregroundStyle(tone == .neutral ? Theme.text : tone.color)
            Text(label).font(.meta).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.muted)
            Text(title).font(.rowTitle).foregroundStyle(Theme.text)
            if let detail { Text(detail).font(.meta).foregroundStyle(Theme.muted).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}

/// Minimum tap size: 44 pt on the phone (Apple's guideline), unconstrained on the Mac.
enum Touch {
    #if os(iOS)
    static let minSize: CGFloat = 44
    #else
    static let minSize: CGFloat = 0
    #endif
}

struct PrimaryButton: ButtonStyle {
    static var minHeight: CGFloat { Touch.minSize }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(minHeight: Self.minHeight)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 6))
    }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(minHeight: Touch.minSize)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(Theme.text)
            .background(Theme.surface2.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
    }
}

/// Filter chip row item.
struct FilterChip: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.chip).padding(.horizontal, 9).padding(.vertical, 4)
                .frame(minHeight: Touch.minSize - 12)
                .foregroundStyle(on ? Theme.accent : Theme.muted)
                .background(on ? Theme.accent.opacity(0.15) : Theme.surface2.opacity(hover ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
            .onHover { hover = $0 }
            .focusable()
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Search box in tokens (surface fill, hairline, 6 pt radius).
struct DeskSearchField: View {
    let prompt: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.meta).foregroundStyle(Theme.muted)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.body13).foregroundStyle(Theme.text)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.meta).foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain).help("Clear")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
    }
}

/// Dismissible error line in the bad tone.
struct ErrorBanner: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.meta)
            Text(text).font(.body13).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark").font(.chip) }.buttonStyle(.plain).help("Dismiss")
        }
        .foregroundStyle(Tone.bad.color).padding(.horizontal, 12).padding(.vertical, 8)
        .background(Tone.bad.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Added by the Courses/Notices pass
extension Font {
    static let h2 = Font.system(size: 18, weight: .semibold, design: .serif)
}

/// Search box: icon + plain field on a quiet surface; clear button when filled.
struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.meta).foregroundStyle(Theme.muted)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.body13)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.meta).foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain).help("Clear")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
    }
}

/// Tinted notice strip (policy banners).
struct Banner: View {
    let icon: String
    let text: String
    var tone: Tone = .warn
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.body13)
            Text(text).font(.body13.weight(.medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tone.color.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Chat typography (agent page)
extension Font {
    static let chatBody = Font.system(size: 14)
    static let chatCode = Font.system(size: 12.5, design: .monospaced)
    static let chatH1 = Font.system(size: 20, weight: .semibold, design: .serif)
    static let chatH2 = Font.system(size: 17, weight: .semibold, design: .serif)
    static let chatH3 = Font.system(size: 15, weight: .semibold)
}
