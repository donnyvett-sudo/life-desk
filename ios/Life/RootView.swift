import SwiftUI

/// Four tabs on iOS 26 glass: Today, Study, Life, Feed. Quick entry lives in the glass accessory above the tab bar
/// (a running focus timer takes its place), and the bar shrinks while you scroll down.
struct RootView: View {
    enum TabID: Hashable { case today, study, life, feed }
    @ObservedObject private var nav = Navigator.shared
    var onDisconnect: () -> Void

    var body: some View {
        TabView(selection: $nav.tab) {
            Tab("Today", systemImage: "checkmark.circle", value: TabID.today) {
                TodayScreen(onDisconnect: onDisconnect)
            }
            Tab("Study", systemImage: "books.vertical", value: TabID.study) {
                NavigationStack(path: Binding(get: { nav.courseID.map { [$0] } ?? [] }, set: { nav.courseID = $0.last })) {
                    StudyScreen()
                        .navigationDestination(for: String.self) { id in
                            CourseDestination(id: id)
                        }
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            Tab("Life", systemImage: "heart.text.square", value: TabID.life) { LifeScreen() }
            Tab("Feed", systemImage: "bubble.left.and.text.bubble.right", value: TabID.feed) { FeedScreen(onDisconnect: onDisconnect) }
        }
        .tint(Theme.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: nav.tab != .feed) { BottomAccessory(openEntry: { nav.sheet = .entry }) }
        .overlay(alignment: .bottom) { ToastHost().padding(.bottom, 120) }
        .sheet(item: $nav.sheet) { sheet in sheetContent(sheet).interactiveDismissDisabled(FocusModel.shared.immersive && { if case .focus = sheet { true } else { false } }()) }
        .onOpenURL { if let r = AppRoute(url: $0) { nav.go(r) } }
    }

    /// Every "go to" that opens over the tabs (cards, promises, account, exam plan, focus) lives here, once.
    @ViewBuilder private func sheetContent(_ sheet: Navigator.Sheet) -> some View {
        switch sheet {
        case .entry: QuickEntrySheet()
        case .cards: CardsScreen()
        case .promises: PromisesScreen()
        case .account: AccountScreen(onDisconnect: onDisconnect)
        case .focus(let c): ZStack(alignment: .topTrailing) {
            FocusScreen(courseId: c)
            Button { nav.sheet = nil } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.muted).frame(width: Touch.minSize, height: Touch.minSize) }
                .padding().accessibilityLabel(L("Close"))
        }
        case .exam(let id): ExamSheetHost(examID: id)
        }
    }
}

/// The glass pill above the tab bar: "＋ Log" in calm times, the focus countdown with Stop while a session runs.
struct BottomAccessory: View {
    var openEntry: () -> Void
    @ObservedObject private var focus = FocusModel.shared
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if focus.immersive {
            HStack(spacing: 10) {
                Image(systemName: "timer").foregroundStyle(Theme.focus)
                Text(focus.phase == .paused ? L("Paused") : FocusLogic.clock(focus.remaining)).monospacedDigit().font(.subheadline.weight(.semibold))
                if placement != .inline { Text(focus.label).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 4)
                Button { Task { await focus.stop() } } label: { Image(systemName: "stop.fill") }.accessibilityLabel(L("Stop focus"))
            }
            .padding(.horizontal, 16)
        } else {
            Button(action: openEntry) {
                Label(L("Log something"), systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .accessibilityHint(L("Expense, meal, weight or a note for the coach"))
        }
    }
}

/// Life: sleep, food, money, habits natively; health (the web Day page, trimmed to supplements and body) and projects
/// (the web Work page) still come from the Mini App. Study things live on the Study tab, not here.
struct LifeScreen: View {
    struct Item: Identifiable { let part: AppRoute.LifePart; let title: String; let icon: String; var id: String { part.rawValue } }
    private let items = [Item(part: .sleep, title: "Sleep", icon: "moon.stars"), Item(part: .food, title: "Food", icon: "fork.knife"),
                         Item(part: .money, title: "Money", icon: "creditcard"), Item(part: .habits, title: "Habits", icon: "repeat"),
                         Item(part: .health, title: "Health", icon: "heart.text.square"), Item(part: .projects, title: "Projects", icon: "briefcase")]
    @ObservedObject private var nav = Navigator.shared

    /// The Mini App tab behind a web-backed part.
    private func webTab(_ p: AppRoute.LifePart) -> String? { p == .health ? "today" : p == .projects ? "work" : nil }

    var body: some View {
        let selected = nav.lifePart
        VStack(spacing: 0) {
            ScrollViewReader { chips in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { it in
                        Button { nav.lifePart = it.part } label: {
                            Label(LocalizedStringKey(it.title), systemImage: it.icon).font(.chip).padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(selected == it.part ? Theme.accent : Theme.muted)
                                .background(selected == it.part ? Theme.accent.opacity(0.15) : Theme.surface2.opacity(0.6), in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(selected == it.part ? .isSelected : []).id(it.id)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }
            // The chosen chip scrolls into view (Habits sits off-screen on a narrow phone).
            .onChange(of: nav.lifePart) { _, p in withAnimation { chips.scrollTo(p.rawValue, anchor: .center) } }
            .onAppear { chips.scrollTo(nav.lifePart.rawValue, anchor: .center) }
            }
            ZStack {
                // The web page stays loaded underneath; the native parts cover it.
                let web = webTab(selected)
                LifeWebView().opacity(web == nil ? 0 : 1).allowsHitTesting(web != nil).accessibilityHidden(web == nil)
                switch selected {
                case .sleep: SleepScreen().transition(.opacity)
                case .food: FoodScreen().transition(.opacity)
                case .money: MoneyScreen().transition(.opacity)
                case .habits: HabitsScreen().transition(.opacity)
                default: EmptyView()
                }
            }
            .onChange(of: nav.lifePart) { _, p in if let t = webTab(p) { LifeWebHolder.shared.show(tab: t) } }
            .onAppear { if let t = webTab(nav.lifePart) { LifeWebHolder.shared.show(tab: t) } }
        }
        .background(Theme.bg)
    }
}

/// Opens the preparation plan of an exam by id (a link from a card, a message or a course).
struct ExamSheetHost: View {
    let examID: String
    @ObservedObject private var bot = BotStore.shared
    @ObservedObject private var docs = StudyDocsStore.shared
    var body: some View {
        if let c = StudyData.exams(bot.study).first(where: { $0.id == examID }) {
            let f = Theme.folder(botShort: c.course)
            ExamPrepSheet(exam: c, folder: f, topics: docs.examTopics[f] ?? [])
        } else if bot.study == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                EmptyState(icon: "graduationcap", title: L("This exam is not available right now."))
                Button(L("Close")) { Navigator.shared.sheet = nil }.buttonStyle(QuietButton())
            }
        }
    }
}

/// The pushed course: observes the study data, so a link followed before the first refresh fills in once it arrives.
struct CourseDestination: View {
    let id: String
    @ObservedObject private var bot = BotStore.shared
    var body: some View {
        if let c = bot.study?.courses?.first(where: { $0.id == id }) { CourseDetailScreen(course: c) }
        else if bot.study == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        else { Text("This course is not available right now.").foregroundStyle(.secondary).padding() }
    }
}
