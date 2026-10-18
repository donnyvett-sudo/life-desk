import SwiftUI

/// Pieces of the Feed: message text, quotes, record cards, action and choice chips, swipe to reply.
extension FeedModel.Item {
    var attributed: AttributedString {
        (try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(body)
    }
    /// The body without markdown escapes, for copying and quoting.
    var plain: String { String(attributed.characters) }
    /// A question from the coach: its buttons are answers sent back as my next line.
    var isChoice: Bool { actions.contains { $0.id.hasPrefix("ch:") } }
    var undo: Action? { actions.first { $0.id.hasPrefix("x:") || $0.id.hasPrefix("ml:del:") } }
    /// Records (expense, meal, check) are shown as cards: icon and colour of their area.
    var record: (icon: String, color: Color)? {
        if actions.contains(where: { $0.id.hasPrefix("x:") }) { return ("creditcard.fill", Theme.money) }
        if actions.contains(where: { $0.id.hasPrefix("ml:") }) { return ("fork.knife", Theme.food) }
        if actions.contains(where: { $0.id.hasPrefix("c:") }) { return ("checkmark.circle.fill", Theme.accent) }
        return nil
    }
}

/// Coach text that folds after 8 lines with "Show more".
struct MessageText: View {
    let item: FeedModel.Item
    var color: Color = Theme.text
    @State private var expanded = false

    // ponytail: guesses length from characters and newlines; measure the text if folding misfires.
    private var long: Bool { !item.isMine && item.body.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { $0 + 1 + $1.count / 45 } > 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.attributed).font(.body13).foregroundStyle(color)
                .lineLimit(long && !expanded ? 8 : nil)
            if long {
                Button(expanded ? L("Show less") : L("Show more")) { expanded.toggle() }
                    .font(.meta.weight(.semibold)).foregroundStyle(Theme.accent).frame(minHeight: 44, alignment: .leading)
            }
        }
    }
}

/// The small quote inside a reply bubble; tapping it scrolls to the original.
struct QuoteLine: View {
    let original: FeedModel.Item
    var mine: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1).fill(mine ? Theme.onAccent.opacity(0.7) : Theme.accent).frame(width: 2)
                Text(original.plain).font(.meta).lineLimit(2).multilineTextAlignment(.leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(mine ? Theme.onAccent.opacity(0.85) : Theme.muted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Replying to \(original.plain)"))
    }
}

/// Glass bar above the composer while replying: two lines of the original and ✕.
struct QuoteBar: View {
    let original: FeedModel.Item
    var onTap: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(original.isMine ? L("You") : L("Coach")).font(.chip).foregroundStyle(Theme.accent)
                        Text(original.plain).font(.meta).foregroundStyle(Theme.text).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Replying to \(original.plain)"))
            Button(action: onCancel) { Image(systemName: "xmark").font(.meta.weight(.semibold)).frame(width: 44, height: 44) }
                .foregroundStyle(Theme.muted).accessibilityLabel(L("Cancel reply"))
        }
        .padding(.leading, 12).padding(.vertical, 2)
        .glassRounded(16)
    }
}

/// The buttons under a coach message; "danger" is red, "primary" prominent.
struct ActionChips: View {
    let actions: [FeedModel.Item.Action]
    var run: (FeedModel.Item.Action) -> Void

    /// A money or meal record links to its screen.
    private var openRoute: AppRoute? {
        actions.contains { $0.id.hasPrefix("x:") } ? .life(.money) : actions.contains { $0.id.hasPrefix("ml:") } ? .life(.food) : nil
    }

    var body: some View {
        FlowChips {
            if let r = openRoute {
                Button { Navigator.shared.go(r) } label: { Label(L("Open"), systemImage: "arrow.up.right").font(.meta.weight(.medium)).frame(minHeight: 44) }.buttonStyle(.glass)
            }
            ForEach(actions, id: \.self) { a in
                if a.style == "primary" {
                    Button { run(a) } label: { label(a) }.buttonStyle(.glassProminent)
                } else {
                    Button { run(a) } label: { label(a).foregroundStyle(a.style == "danger" ? Theme.bad : Theme.text) }.buttonStyle(.glass)
                }
            }
        }
    }
    private func label(_ a: FeedModel.Item.Action) -> some View { Text(a.label).font(.meta.weight(.medium)).lineLimit(1).truncationMode(.tail).frame(maxWidth: 260, minHeight: 44) }
}

/// Answers to a coach question: one glass row, the likely (first) option prominent, plus "Other…".
struct ChoiceChips: View {
    let actions: [FeedModel.Item.Action]
    var choose: (FeedModel.Item.Action) -> Void
    var other: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(actions.filter { !Self.isOther($0.label) }.enumerated()), id: \.element) { i, a in
                        if i == 0 { Button { choose(a) } label: { label(a.label) }.buttonStyle(.glassProminent) }
                        else { Button { choose(a) } label: { label(a.label) }.buttonStyle(.glass) }
                    }
                    Button(action: other) { label(L("Other…")) }.buttonStyle(.glass)
                }
            }
        }
        .scrollClipDisabled()
    }
    private func label(_ s: String) -> some View { Text(s).font(.meta.weight(.medium)).lineLimit(1).truncationMode(.tail).frame(maxWidth: 260, minHeight: 44) }
    static func isOther(_ l: String) -> Bool { let x = l.lowercased(); return x.hasPrefix("другое") || x.hasPrefix("other") }
}

/// Swipe a bubble right to reply. Vertical drags keep scrolling; Reduce Motion keeps the bubble still.
struct SwipeToReply: ViewModifier {
    var onReply: () -> Void
    @State private var dx: CGFloat = 0
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let threshold: CGFloat = 60

    func body(content: Content) -> some View {
        content
            .offset(x: reduceMotion ? 0 : dx)
            .background(alignment: .leading) {
                Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 18)).foregroundStyle(Theme.accent)
                    .opacity(reduceMotion ? 0 : min(1, dx / threshold)).accessibilityHidden(true)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { v in
                        guard v.translation.width > 0, v.translation.width > abs(v.translation.height) * 2.5 else { dx = 0; armed = false; return }
                        dx = min(v.translation.width, threshold + 20)
                        armed = dx >= threshold   // dragging back below the line cancels
                    }
                    .onEnded { _ in
                        if armed { onReply() }
                        armed = false
                        if reduceMotion { dx = 0 } else { withAnimation(.spring(duration: 0.25)) { dx = 0 } }
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, now in now }
            .onDisappear { dx = 0; armed = false }
    }
}

extension View {
    func swipeToReply(_ onReply: @escaping () -> Void) -> some View { modifier(SwipeToReply(onReply: onReply)) }
}
