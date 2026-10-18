import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var connected = TokenStore.load() != nil
    @State private var verifying = false
    @Environment(\.scenePhase) private var phase
    @AppStorage(AppLanguage.key, store: AppLanguage.store) private var lang = "system"
    @ObservedObject private var nav = Navigator.shared
    @State private var appliedTheme = AccentTheme.current.id   // the tree rebuilds when a theme change settles (sheet closed), not under your finger

    var body: some View {
        // .id(lang) rebuilds the tree when the language changes, so every String built with L() is evaluated again.
        content.environment(\.locale, AppLanguage.locale).tint(Theme.accent).id(lang + appliedTheme)
            
            .onChange(of: nav.sheet) { _, s in if s == nil { appliedTheme = AccentTheme.current.id } }
            .onChange(of: lang) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
    }

    @ViewBuilder private var content: some View {
        if connected {
            RootView(onDisconnect: { disconnect() })
                .onReceive(NotificationCenter.default.publisher(for: LifeAPI.tokenRejected)) { _ in
                    // A single 401 may be a proxy or a deploy in flight: ask once more before dropping the token.
                    guard !verifying else { return }
                    verifying = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        let r = try? await BotAPI.raw("GET", "/settings")
                        verifying = false
                        if r?.status == 401 { disconnect() }
                    }
                }
                .task { ReminderPlanner.shared.setUp(); FocusActivityController.shared.start(); await SleepSync.shared.syncIfDue(); await ReminderPlanner.shared.refresh() }
                .onReceive(BotStore.shared.$study) { WidgetFeed.publish($0) }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await TimeZoneSync.run(); await LanguageSync.syncIfNeeded(); await SleepSync.shared.syncIfDue(); await ReminderPlanner.shared.refresh() } }
                }
        } else {
            ConnectView { connected = true }
        }
    }

    private func disconnect() {
        TokenStore.clear()
        WidgetFeed.clear()
        ReminderPlanner.wipe()
        BotStore.shared.reset()
        StudyDocsStore.shared.reset()
        UserDefaults.standard.removeObject(forKey: "sleep.lastSync")
        FocusActivityController.shared.endAll()
        connected = false
    }
}

/// First launch: a pairing code from Life Desk (Settings → Connect iPhone) or, until pairing is live, the token itself.
struct ConnectView: View {
    var done: () -> Void
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Life").font(.system(size: 44, weight: .semibold, design: .serif))
            Text("Connect this iPhone to your account.").foregroundStyle(.secondary)
            SecureField("Pairing code or token", text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.none)
                .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            Button(busy ? L("Connecting…") : L("Connect")) { Task { await connect() } }
                .buttonStyle(.borderedProminent).disabled(busy || text.trimmingCharacters(in: .whitespaces).count < 8)
            Spacer()
        }
        .padding(24)
    }

    private func connect() async {
        busy = true; error = nil; defer { busy = false }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 32 {                                   // a token: check it before keeping it
            guard let r = try? await LifeAPI.raw("GET", "/settings", token: t), r.status == 200 else {
                error = L("The token was not accepted."); return
            }
            if TokenStore.save(t) { done() } else { error = L("Could not save to the Keychain.") }
        } else {                                              // a one-time code
            let paired: String?
            do { paired = try await LifeAPI.pair(code: t, deviceName: "iPhone") }
            catch LifeAPI.Err.rateLimited { error = L("Too many attempts. Wait 10 minutes."); return }
            catch let e { _ = e; self.error = L("No connection."); return }
            guard let token = paired else { error = L("The code is wrong or has expired."); return }
            if TokenStore.save(token) { done() } else { error = L("Could not save to the Keychain.") }
        }
    }
}

/// Pushes the freshest study data to the home-screen widget through the App Group.
enum WidgetFeed {
    @MainActor static func publish(_ study: BotStudy?) {
        guard let study else { return }
        let items = StudyData.open(study).prefix(5).map { WidgetSnapshot.Item(title: $0.a.title, course: $0.course, date: $0.a.dueDate ?? "") }
            .filter { !$0.date.isEmpty }
        let exam = StudyData.exams(study, limit: 1).first.map { WidgetSnapshot.Item(title: $0.title, course: $0.course, date: $0.date) }
        let snap = WidgetSnapshot(updated: Date(), deadlines: Array(items), exam: exam)
        guard snap != WidgetSnapshot.load().map({ var o = $0; o.updated = snap.updated; return o }) else { return }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        UserDefaults(suiteName: WidgetSnapshot.group)?.removeObject(forKey: WidgetSnapshot.key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
