import SwiftUI
import UserNotifications

/// What the Telegram bot's /export and /friends did: save a copy of all data, and (for the owner) switch friends on and off.
@MainActor
final class AccountModel: ObservableObject {
    struct Friend: Decodable, Identifiable { var id: String; var name: String; var allowed: Bool }
    struct Invite: Decodable, Identifiable { var code: String; var expiresAt: String; var id: String { code } }
    struct Friends: Decodable { var friends: [Friend]; var invites: [Invite] }

    @Published var friends: Friends?
    @Published var exportURL: URL?
    @Published var note: String?
    @Published var busy = false
    @Published var friendsLocked = false
    @Published var friendCode: (name: String, code: String)?
    @Published var telegram: Bool?      // nil: unknown or no Telegram account

    @Published var notificationsDenied = false

    func checkNotifications() async {
        let st = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = (st == .denied)
    }

    func cleanUp() { if let u = exportURL { try? FileManager.default.removeItem(at: u); exportURL = nil } }

    func loadSettings() async {
        if let r = try? await LifeAPI.raw("GET", "/settings"), r.status == 200,
           let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any], let v = j["notifyTelegram"] as? Bool { telegram = v }
    }

    /// Off: reminders come as notifications from this phone and the Feed, not from the bot.
    func setTelegram(_ on: Bool) async {
        let body = try? JSONSerialization.data(withJSONObject: ["notifyTelegram": on])
        if let r = try? await LifeAPI.raw("PUT", "/settings", body: body), r.status == 200 { telegram = on; await ReminderPlanner.shared.refresh() }
        else { note = on ? L("This account has no Telegram.") : L("That did not work.") }
    }

    func load() async {
        guard let r = try? await LifeAPI.raw("GET", "/friends") else { return }
        if r.status == 200 { friends = try? JSONDecoder().decode(Friends.self, from: r.data); friendsLocked = false }
        else if r.status == 403 { friendsLocked = true }   // an older pairing without the admin right (or a friend's account)
    }

    func export() async {
        busy = true; defer { busy = false }
        if let old = exportURL { try? FileManager.default.removeItem(at: old); exportURL = nil }
        guard let r = try? await LifeAPI.raw("GET", "/export"), r.status == 200,
              let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: String],
              let name = j["filename"], let content = j["content"] else { note = L("Could not prepare the export."); return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        do { try Data(content.utf8).write(to: url, options: .completeFileProtection); exportURL = url; note = nil }
        catch { note = L("Could not save the file.") }
    }

    func setAccess(_ f: Friend, _ on: Bool) async {
        let body = try? JSONSerialization.data(withJSONObject: ["allowed": on])
        if let r = try? await LifeAPI.raw("POST", "/friends/\(f.id)", body: body), r.status == 200 { friends = try? JSONDecoder().decode(Friends.self, from: r.data) }
        else { note = L("That did not work.") }
    }

    func code(for f: Friend) async {
        if let r = try? await LifeAPI.raw("POST", "/friends/\(f.id)/code", body: Data("{}".utf8)), r.status == 200,
           let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any], let c = j["code"] as? String { friendCode = (f.name, c) }
        else { note = L("That did not work.") }
    }

    func revoke(_ i: Invite) async {
        if let r = try? await LifeAPI.raw("DELETE", "/invites/\(i.code)"), r.status == 200 { friends = try? JSONDecoder().decode(Friends.self, from: r.data) }
    }
}

struct AccountScreen: View {
    var onDisconnect: () -> Void = {}
    @State private var confirmDisconnect = false
    @StateObject private var model = AccountModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.key, store: AppLanguage.store) private var lang = "system"
    @AppStorage(AccentTheme.key) private var theme = "coral"

    var body: some View {
        NavigationStack {
            List {
                Section("Language / Язык") {
                    Picker("Language / Язык", selection: $lang) {
                        Text("System / Системный").tag("system")
                        Text("English").tag("en")
                        Text("Русский").tag("ru")
                    }
                }
                Section(L("Colour theme")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(AccentTheme.all) { t in
                                Button { AccentTheme.choose(t.id); theme = t.id; LifeWebHolder.shared.applyAccent() } label: {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            Circle().fill(Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: t.accent.dark) : UIColor(rgb: t.accent.light) })).frame(width: 44, height: 44)
                                            if theme == t.id { Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white) }
                                        }
                                        Text(L(String.LocalizationValue(t.title))).font(.caption2).foregroundStyle(.secondary)
                                    }.frame(minWidth: 60, minHeight: 60)
                                }.buttonStyle(.plain).accessibilityLabel(t.title).accessibilityAddTraits(theme == t.id ? .isSelected : [])
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("My data") {
                    Button(model.busy ? L("Preparing…") : L("Prepare a copy of all my data")) { Task { await model.export() } }.disabled(model.busy)
                    if let u = model.exportURL { ShareLink(item: u) { Label("Share or save the file", systemImage: "square.and.arrow.up") } }
                    Text("A JSON file with everything stored about you. Access tokens are not included.").font(.caption).foregroundStyle(.secondary)
                }
                if model.notificationsDenied {
                    Section { Text(L("Notifications are off for Life in iOS Settings, so reminders will not appear on this phone.")).foregroundStyle(Theme.warn) }
                }
                if let tg = model.telegram {
                    Section("Reminders") {
                        Toggle("Also send reminders to Telegram", isOn: Binding(get: { tg }, set: { on in Task { await model.setTelegram(on) } }))
                        Text(tg ? L("Reminders come from the Telegram bot. Turn this off to get them as notifications from this phone.") : L("Reminders are scheduled on this phone and appear in the Feed."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let f = model.friends {
                    Section("Friends") {
                        if f.friends.isEmpty && f.invites.isEmpty { Text("No friends yet. Make an invite link in Life Desk on the Mac.").foregroundStyle(.secondary) }
                        ForEach(f.friends) { fr in
                            Toggle(fr.name, isOn: Binding(get: { fr.allowed }, set: { on in Task { await model.setAccess(fr, on) } }))
                            if fr.allowed { Button(L("Reconnect code")) { Task { await model.code(for: fr) } } }
                        }
                        ForEach(f.invites) { i in
                            HStack { Text("Invite \(i.code)").font(.body.monospaced()); Spacer(); Button("Revoke", role: .destructive) { Task { await model.revoke(i) } } }
                        }
                    }
                }
                if model.friends == nil && model.friendsLocked {
                    Section(L("Friends")) { Text(L("To manage friends, reconnect this iPhone with a new code from Life Desk (Settings, iPhone).")).font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    Button(L("Disconnect this iPhone"), role: .destructive) { confirmDisconnect = true }
                    Text(L("You will need a new pairing code to connect again.")).font(.caption).foregroundStyle(.secondary)
                }
                if let n = model.note { Text(n).foregroundStyle(Theme.warn) }
            }
            .navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: lang) { _, _ in Task { await LanguageSync.push(reloadPage: true) } }
            .confirmationDialog(L("Disconnect this iPhone?"), isPresented: $confirmDisconnect) {
                Button(L("Disconnect"), role: .destructive) { dismiss(); onDisconnect() }
            }
            .task { await model.load(); await model.loadSettings(); await model.checkNotifications() }
            .onDisappear { model.cleanUp() }
            .alert(model.friendCode.map { L("Code for \($0.name)") } ?? "", isPresented: Binding(get: { model.friendCode != nil }, set: { if !$0 { model.friendCode = nil } })) {
                Button("OK") { model.friendCode = nil }
            } message: { Text((model.friendCode?.code ?? "") + "\n" + L("Valid for 10 minutes, works once. Give it to your friend: they choose “I already have an account”.")) }
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}
