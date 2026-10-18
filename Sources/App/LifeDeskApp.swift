import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    // Life: the bot's Mini App, one sidebar entry per tab (tab = the Mini App's own tab id).
    case coach, sleep, food, money, habits, health, projects
    // Study Workspace
    case today, inbox, focus, deadlines, courses, notices, chat, sync
    var id: String { rawValue }

    static let life: [Page] = [.coach, .sleep, .food, .money, .habits, .health, .projects]
    static let study: [Page] = [.today, .inbox, .focus, .deadlines, .courses, .notices, .chat, .sync]

    var title: String {
        switch self {
        case .coach: "Coach"
        case .health: "Health"
        case .food: "Food"
        case .sleep: "Sleep"
        case .money: "Finance"
        case .projects: "Projects"
        case .habits: "Habits"
        case .today: "Today"
        case .inbox: "Inbox"
        case .focus: "Focus"
        case .deadlines: "Deadlines"
        case .courses: "Courses"
        case .notices: "Notices"
        case .chat: "Agent"
        case .sync: "Sync"
        }
    }
    var icon: String {
        switch self {
        case .coach: "bubble.left.and.bubble.right"
        case .health: "heart.text.square"
        case .food: "fork.knife"
        case .sleep: "moon.stars"
        case .money: "creditcard"
        case .projects: "briefcase"
        case .habits: "repeat"
        case .today: "checkmark.circle"
        case .inbox: "tray"
        case .focus: "timer"
        case .deadlines: "calendar.badge.clock"
        case .courses: "books.vertical"
        case .notices: "bell"
        case .chat: "text.bubble"
        case .sync: "arrow.triangle.2.circlepath"
        }
    }
    /// The Mini App's tab id, nil for native pages.
    var miniTab: String? {
        switch self {
        case .health: "today"
        case .food: "food"
        case .sleep: "sleep"
        case .money: "money"
        case .projects: "work"
        case .habits: "habits"
        default: nil
        }
    }
}

@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published var page: Page = .today
    @Published var sidebarVisible = true
    /// One overlay at a time: opening one closes the others.
    @Published var paletteVisible = false { didSet { if paletteVisible { quickEntryVisible = false; prepExam = nil } } }
    @Published var quickEntryVisible = false { didSet { if quickEntryVisible { paletteVisible = false; prepExam = nil } } }
    /// Exam whose preparation sheet is open.
    @Published var prepExam: MarkdownTables.Item? { didSet { if prepExam != nil { paletteVisible = false; quickEntryVisible = false } } }
    /// Cached (a Keychain read per render could prompt); refreshed on Settings save and when a Life page opens without it.
    @Published var tokenPresent = Keychain.loadOrImport() != nil
    /// Deadlines row (Item.id) to open expanded when the page appears.
    @Published var focusDeadline: String?
    /// Bot course id the Focus page should preselect (consumed on appear).
    @Published var focusCourse: String?

    /// One place that knows where a tap goes (cards, notifications, lifedesk://route/... links).
    func go(_ route: AppRoute) {
        switch route {
        case .today: page = .today
        case .study(let p):
            switch p {
            case .deadlines, .exams: page = .deadlines
            case .courses: page = .courses
            case .notices: page = .notices
            }
        case .course(let id):
            let folder = BotStore.shared.study?.courses?.first(where: { $0.id == id }).map { Theme.folder(botShort: $0.short) } ?? id
            UserDefaults.standard.set(folder, forKey: "courses.selected")
            page = .courses
        case .exam(let id):
            focusDeadline = id; page = .deadlines
            if let e = DeadlineActions.loadItems().first(where: { $0.id == id && $0.kind == .exam }) { prepExam = e }
        case .life(let p):
            switch p {
            case .sleep: page = .sleep
            case .food: page = .food
            case .money: page = .money
            case .habits: page = .habits
            case .health: page = .health
            case .projects: page = .projects
            }
        case .focus(let c): focusCourse = c; page = .focus
        case .cards, .promises, .feed: page = .coach
        case .account:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

/// Dock click or `open` with the window closed: SwiftUI's single `Window` does not come back on its own.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var showMain: () -> Void = {}
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { Task { @MainActor in AppDelegate.showMain() } }
        return true
    }
}

@main
struct LifeDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = Router.shared
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var focus = FocusModel.shared
    @ObservedObject private var chats = ChatModel.shared
    @ObservedObject private var bot = BotStore.shared
    @AppStorage(AccentTheme.key) private var theme = AccentTheme.all[0].id

    /// Brings the main window back: deminiaturizes a hidden one, reopens a closed one.
    private func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        // openWindow brings an open single Window forward and recreates a closed one; a minimized one needs a nudge first.
        NSApp.windows.filter { $0.isMiniaturized && $0.identifier?.rawValue.hasPrefix("main") == true }.forEach { $0.deminiaturize(nil) }
        openWindow(id: "main")
    }

    private var columns: Binding<NavigationSplitViewVisibility> {
        Binding(get: { router.sidebarVisible && !(focus.immersive && router.page == .focus) ? .all : .detailOnly },
                set: { v in if !(focus.immersive && router.page == .focus) { router.sidebarVisible = v != .detailOnly } })
    }

    var body: some Scene {
        Window("Life Desk", id: "main") {
            NavigationSplitView(columnVisibility: columns) {
                SidebarView(router: router)
                    .navigationSplitViewColumnWidth(min: 190, ideal: 212, max: 280)
            } detail: {
                detail.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
                    .scrollEdgeEffectStyle(.soft, for: .all)
            }
            .overlay(alignment: .bottom) { ToastView() }
            .task(id: StudyStore.shared.tick) { await ReminderScheduler.reschedule(); await InboxModel.shared.reload() }
            .task {
                // Hourly: "older than 24 h" changes with the clock, not only with files.
                while !Task.isCancelled {
                    await ReminderScheduler.reschedule()
                    await InboxModel.shared.reload()
                    try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                }
            }
            .onChange(of: bot.fetchedAt) { Task { await ReminderScheduler.reschedule() } }
            .onAppear {
                RelayWorker.shared.apply()
                AppDelegate.showMain = { showMain() }
                GlobalHotKey.shared.onFire = {
                    // Closed or minimized window: bring it back before showing the box.
                    showMain()
                    router.quickEntryVisible = true
                }
                GlobalHotKey.shared.register()
            }
            .onChange(of: chats.runningIDs) { old, new in
                if new.count < old.count, router.page != .chat || !NSApp.isActive {
                    SidebarBadges.shared.agentDone = true
                    NSApp.requestUserAttention(.informationalRequest)
                }
            }
            .onChange(of: router.page) { _, p in
                if p == .chat { SidebarBadges.shared.agentDone = false }
                if p == .sync { SidebarBadges.shared.syncAcked = SidebarBadges.shared.syncStale }
            }
            .overlay {
                if let exam = router.prepExam {
                    ZStack {
                        Color.black.opacity(0.25).onTapGesture { router.prepExam = nil }
                        ExamPrepView(exam: exam)
                    }
                } else if router.quickEntryVisible {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.2).onTapGesture { router.quickEntryVisible = false }
                        QuickEntryView().padding(.top, 80)
                    }
                } else if router.paletteVisible {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.2).onTapGesture { router.paletteVisible = false }
                        CommandPalette().padding(.top, 80)
                    }
                }
            }
            .frame(minWidth: 960, minHeight: 640)
            .id(theme)
            .tint(Theme.accent)
            .onOpenURL { if let r = AppRoute(url: $0) { showMain(); router.go(r) } }
            .onChange(of: theme) { LifeWeb.shared.applyAccent() }
            .toolbar(removing: .title)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandMenu("Go") {
                ForEach(Array(Page.study.prefix(9).enumerated()), id: \.element) { i, p in
                    Button(p.title) { router.page = p }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                Divider()
                ForEach(Array(Page.life.prefix(9).enumerated()), id: \.element) { i, p in
                    Button(p.title) { router.page = p }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
                }
                Divider()
                Button("Toggle sidebar") { router.sidebarVisible.toggle() }.keyboardShortcut("s", modifiers: [.command, .option])
            }
            CommandGroup(after: .toolbar) {
                Button("Quick add deadline") { router.quickEntryVisible.toggle() }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Command palette") { router.paletteVisible.toggle() }.keyboardShortcut("k")
            }
            CommandGroup(replacing: .newItem) {
                Button("New chat") { router.page = .chat; ChatModel.shared.newChat() }.keyboardShortcut("n")
            }
        }
        Settings { SettingsView() }
        MenuBarExtra {
            MenuBarButtons()
            Divider()
            Button("Quit Life Desk") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            if focus.immersive { Text(FocusLogic.clock(focus.remaining)).monospacedDigit() } else { Image(systemName: "book.closed") }
        }
    }

    @ViewBuilder private var detail: some View {
        switch router.page {
        case .coach: if router.tokenPresent { CoachView() } else { MissingToken() }
        case .health, .food, .sleep, .money, .projects, .habits:
            if router.tokenPresent { LifeWebView(tab: router.page.miniTab ?? "today") } else { MissingToken() }
        case .today: TodayView()
        case .inbox: InboxView()
        case .focus: FocusView()
        case .deadlines: DeadlinesView()
        case .courses: CoursesView()
        case .notices: NoticesView()
        case .chat: ChatView()
        case .sync: SyncView()
        }
    }
}

struct MissingToken: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Bot not connected").font(.headline)
            Text("The Life pages need your bot's token. Paste it in Settings (⌘,), then switch pages. The Study pages work without it.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            SettingsLink { Text("Open Settings") }
        }.padding()
    }
}

struct MenuBarButtons: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var badges = SidebarBadges.shared
    @ObservedObject private var focus = FocusModel.shared
    private func go(_ p: Page) { Router.shared.page = p; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
    var body: some View {
        Button("Open Life Desk") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        if badges.overdue > 0 {
            Button("\(badges.overdue) overdue…") { go(.deadlines) }
        }
        Button("Today") { go(.today) }
        Button(focus.immersive ? "Focus: \(FocusLogic.clock(focus.remaining)) left" : "Start focus…") { go(.focus) }
        Button("Sync…") { go(.sync) }
    }
}

/// System sidebar list (Liquid Glass on macOS 26): two sections, count badges for what needs attention.
struct SidebarView: View {
    @ObservedObject var router: Router
    @ObservedObject private var badges = SidebarBadges.shared
    @ObservedObject private var chats = ChatModel.shared

    var body: some View {
        List(selection: Binding<Page?>(get: { router.page }, set: { if let p = $0 { router.page = p } })) {
            Section("Study Workspace") { ForEach(Page.study) { row($0) } }
            Section("Life") { ForEach(Page.life) { row($0) } }
        }
        .listStyle(.sidebar)
    }

    private func row(_ p: Page) -> some View {
        HStack(spacing: 6) {
            Label(p.title, systemImage: p.icon)
            Spacer(minLength: 4)
            if p == .chat, !chats.runningIDs.isEmpty { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16) }
            else if p == .chat, badges.agentDone, router.page != p { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
            if let b = badges.value(for: p), b.count > 0 { Chip(text: "\(b.count)", tone: b.tone) }
        }
        .tag(p)
        .accessibilityLabel(badges.value(for: p).map { $0.count > 0 ? "\(p.title), \($0.count) \(p == .deadlines ? "overdue" : p == .sync ? "out of date" : p == .inbox ? "to review" : "new")" : p.title } ?? p.title)
    }
}

/// Counts shown next to sidebar rows; pages that know the numbers set them.
@MainActor
final class SidebarBadges: ObservableObject {
    static let shared = SidebarBadges()
    @Published var overdue = 0
    @Published var newNotices = 0
    /// An agent answer finished while the Agent page was not open.
    @Published var agentDone = false
    /// Chats not read for over 24 h (sources.md).
    @Published var syncStale = 0 { didSet { if syncStale < syncAcked { syncAcked = syncStale } } }
    /// How many stale chats the user has already looked at (opening Sync); the badge shows only when there are more.
    @Published var syncAcked = 0
    @Published var inbox = 0
    func value(for p: Page) -> (count: Int, tone: Tone)? {
        switch p {
        case .deadlines: (overdue, .bad)
        case .notices: (newNotices, .accent)
        case .sync: (syncStale > syncAcked ? syncStale : 0, .warn)
        case .inbox: (inbox, .accent)
        default: nil
        }
    }
}
