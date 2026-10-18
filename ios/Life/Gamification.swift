import SwiftUI

// Streaks, badges, goal rings, the course path and the small celebration. Calm, opaque, built from existing data only.

// MARK: celebration
/// One place to say "that was a win": a short spark burst (skipped with Reduce Motion) and a success haptic.
@MainActor
final class Celebrate: ObservableObject {
    static let shared = Celebrate()
    @Published private(set) var tick = 0
    func fire() { tick += 1; UINotificationFeedbackGenerator().notificationOccurred(.success) }

    /// Marks a deadline done (with Undo) and celebrates only when it really left the open list.
    static func deadline(id: String, done: Bool, title: String) async {
        await DeadlineActions.toggle(id: id, done: done, title: title)
        if done, !StudyData.open(BotStore.shared.study).contains(where: { $0.id == id }) { shared.fire() }
    }
}

private struct Sparks: View {
    @State private var go = false
    private let colors: [Color] = [Theme.accent, Theme.focus, Theme.money, Theme.food, Theme.sleep]
    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { i in
                let a = Double(i) / 18 * 2 * .pi
                let d = 70 + Double((i * 37) % 60)
                Capsule().fill(colors[i % colors.count]).frame(width: 6, height: 12)
                    .rotationEffect(.radians(a + (go ? 2 : 0)))
                    .offset(x: go ? cos(a) * d : 0, y: go ? sin(a) * d : 0)
                    .opacity(go ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).offset(y: -60)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { go = true } }
    }
}

private struct CelebrationHost: ViewModifier {
    @ObservedObject private var c = Celebrate.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var live = false
    @State private var stop: Task<Void, Never>?
    @State private var token = 0
    func body(content: Content) -> some View {
        content
            .overlay { if live { Sparks().id(token).allowsHitTesting(false).accessibilityHidden(true).transition(.opacity) } }
            .onChange(of: c.tick) { _, _ in
                guard !reduceMotion else { return }
                token += 1; live = true
                stop?.cancel(); stop = Task { try? await Task.sleep(for: .milliseconds(900)); if !Task.isCancelled { live = false } }
            }
    }
}

extension View {
    /// Shows the spark burst on this screen when something is celebrated.
    func celebrates() -> some View { modifier(CelebrationHost()) }

    /// Makes a Today card a link: pressed state, a chevron in the corner, link trait.
    func cardLink(_ route: AppRoute) -> some View {
        Button { Navigator.shared.go(route) } label: {
            self.overlay(alignment: .topTrailing) {
                Image(systemName: "chevron.right").font(.chip).foregroundStyle(Theme.muted).padding(10).accessibilityHidden(true)
            }.contentShape(Rectangle())
        }
        .buttonStyle(CardLinkStyle()).accessibilityAddTraits(.isLink)
    }
}

struct CardLinkStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// "‹ Today" back-link for the Life headers.
struct TodayChip: View {
    var body: some View {
        Button { Navigator.shared.go(.today) } label: { Label(L("Today"), systemImage: "chevron.left").labelStyle(.titleAndIcon) }
            .buttonStyle(QuietButton()).accessibilityHint(L("Back to Today"))
    }
}

// MARK: streaks
/// A flame and a count; muted at 0. A link to where the streak lives.
struct FlameChip: View {
    let count: Int
    let label: String
    let tint: Color
    let route: AppRoute
    var body: some View {
        Button { Navigator.shared.go(route) } label: {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill").foregroundStyle(count > 0 ? tint : Theme.muted)
                Text("\(count)").font(.rowTitle).monospacedDigit().foregroundStyle(Theme.text)
                Text(label).font(.chip).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10).frame(minHeight: Touch.minSize)
            .background(Theme.surface, in: Capsule()).overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(CardLinkStyle())
        .accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(count)").accessibilityAddTraits(.isLink)
    }
}

enum Streaks {
    /// Latest nights in a row that were on target.
    static func nights(_ h: SleepHistory?) -> Int { h.map { $0.nights.reversed().prefix { $0.verdict == "good" }.count } ?? 0 }
    static func habit(_ h: HabitsOverview?) -> Int { h?.habits.filter(\.active).map(\.streak).max() ?? 0 }
}

// MARK: weekly goals
struct WeeklyGoalsCard: View {
    let focusMin: Int
    let focusGoal: Int
    let nightsOn: Int
    let nights: Int
    let habitsDone: Int
    let habitsTotal: Int
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("This week").uppercased()).font(.sectionLabel).tracking(0.6).foregroundStyle(Theme.muted)
            HStack(alignment: .top, spacing: 8) {
                goal(L("Focus"), value: Loc.minutes(focusMin), progress: Double(focusMin) / Double(max(focusGoal, 1)), tint: Theme.focus, route: .focus(courseId: nil),
                     a11y: L("Focus \(Loc.minutes(focusMin)) of \(Loc.minutes(focusGoal))"))
                goal(L("Nights"), value: "\(nightsOn)/\(max(nights, 7))", progress: Double(nightsOn) / 7, tint: Theme.sleep, route: .life(.sleep),
                     a11y: L("\(nightsOn) nights on target"))
                goal(L("Habits"), value: "\(habitsDone)/\(habitsTotal)", progress: habitsTotal == 0 ? 0 : Double(habitsDone) / Double(habitsTotal), tint: Theme.accent, route: .life(.habits),
                     a11y: L("\(habitsDone) of \(habitsTotal) habits done today"))
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }

    private func goal(_ title: String, value: String, progress: Double, tint: Color, route: AppRoute, a11y: String) -> some View {
        Button { Navigator.shared.go(route) } label: {
            VStack(spacing: 6) {
                Ring(progress: progress, tint: tint, lineWidth: 6) {
                    Image(systemName: progress >= 1 ? "checkmark" : "circle.dotted").font(.meta.weight(.semibold)).foregroundStyle(progress >= 1 ? tint : Theme.muted)
                }.frame(width: min(size, 96), height: min(size, 96))
                Text(value).font(.rowTitle).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(.chip).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, minHeight: Touch.minSize).contentShape(Rectangle())
        }
        .buttonStyle(CardLinkStyle()).accessibilityElement(children: .ignore).accessibilityLabel("\(title): \(a11y)").accessibilityAddTraits(.isLink)
    }
}

// MARK: badges
struct Badge: Identifiable {
    let id: String
    let icon: String
    let title: String
    let tint: Color
    let unlocked: Bool
}

enum Badges {
    /// All derived from data the app already has; nothing is stored.
    static func all(log: FocusLog, today: String, sleep: SleepHistory?, habits: HabitsOverview?, study: BotStudy?) -> [Badge] {
        let doneToday = habits?.habits.filter { $0.active && $0.doneToday }.count ?? 0
        return [
            Badge(id: "focus1", icon: "timer", title: L("First focus"), tint: Theme.focus, unlocked: log.days.values.contains { $0 > 0 }),
            Badge(id: "focus3", icon: "flame.fill", title: L("3-day focus"), tint: Theme.focus, unlocked: FocusStats.streak(log, today: today) >= 3),
            Badge(id: "sleep7", icon: "moon.stars.fill", title: L("7 good nights"), tint: Theme.sleep, unlocked: Streaks.nights(sleep) >= 7),
            Badge(id: "habit5", icon: "checkmark.seal.fill", title: L("5 habits a day"), tint: Theme.accent, unlocked: doneToday >= 5),
            Badge(id: "clear", icon: "tray.fill", title: L("All clear"), tint: Theme.good, unlocked: study != nil && StudyData.open(study).isEmpty),
        ]
    }
}

struct BadgeRow: View {
    let badges: [Badge]
    @ScaledMetric(relativeTo: .caption) private var disc: CGFloat = 44
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(badges) { b in
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(b.unlocked ? b.tint : Color.clear)
                            Circle().stroke(b.unlocked ? b.tint : Theme.line, lineWidth: 2)
                            Image(systemName: b.unlocked ? b.icon : "lock.fill").font(.body.weight(.semibold))
                                .foregroundStyle(b.unlocked ? Theme.onAccent : Theme.muted)
                        }.frame(width: min(disc, 72), height: min(disc, 72))
                        Text(b.title).font(.chip).foregroundStyle(b.unlocked ? Theme.text : Theme.muted).multilineTextAlignment(.center).lineLimit(2)
                            .frame(width: 78)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(b.title), \(b.unlocked ? L("unlocked") : L("locked"))")
                }
            }.padding(.vertical, 2)
        }
    }
}

// MARK: course path
/// A vertical learning path: done = filled node with a check, next = highlighted and pulsing, later = outlined. Tap toggles.
struct LearningPath: View {
    let topics: [String]
    let done: Set<String>
    let tint: Color
    var toggle: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @ScaledMetric(relativeTo: .body) private var node: CGFloat = 30

    var body: some View {
        let next = topics.first { !done.contains($0) }
        VStack(spacing: 0) {
            ForEach(Array(topics.enumerated()), id: \.offset) { i, t in
                let isDone = done.contains(t), isNext = t == next
                Button { toggle(t) } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            VStack(spacing: 0) {
                                Rectangle().fill(i == 0 ? Color.clear : (isDone || isNext ? tint : Theme.line)).frame(width: 3)
                                Rectangle().fill(i == topics.count - 1 ? Color.clear : (isDone ? tint : Theme.line)).frame(width: 3)
                            }
                            nodeView(done: isDone, next: isNext)
                        }.frame(width: min(node, 48) + 12)
                        Text(t).font(isNext ? .rowTitle : .body13).foregroundStyle(isDone ? Theme.muted : Theme.text).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(t), \(isDone ? L("done") : isNext ? L("next") : L("not started"))")
                .accessibilityHint(isDone ? L("Marks as not done") : L("Marks as done"))
                .accessibilityAddTraits(isDone ? .isSelected : [])
            }
        }
        .onAppear { if !reduceMotion { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } } }
    }

    @ViewBuilder private func nodeView(done: Bool, next: Bool) -> some View {
        let s = min(node, 48)
        ZStack {
            if next && !reduceMotion {
                Circle().stroke(tint, lineWidth: 2).scaleEffect(pulse ? 1.5 : 1).opacity(pulse ? 0 : 0.6)
            }
            Circle().fill(done ? tint : next ? tint.opacity(0.18) : Theme.bg)
            Circle().stroke(done || next ? tint : Theme.line, lineWidth: next ? 3 : 2)
            if done { Image(systemName: "checkmark").font(.meta.weight(.bold)).foregroundStyle(.white) }
            else if next { Image(systemName: "star.fill").font(.chip).foregroundStyle(tint) }
        }.frame(width: s, height: s)
    }
}

/// A course tile with a progress ring around it (done of total).
struct CourseRing<Icon: View>: View {
    let progress: Double
    let tint: Color
    let size: CGFloat
    @ViewBuilder var icon: () -> Icon
    var body: some View {
        Ring(progress: progress, tint: tint, lineWidth: 3) { icon().padding(5) }
            .frame(width: size + 10, height: size + 10)
    }
}
