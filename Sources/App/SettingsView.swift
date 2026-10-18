import SwiftUI
import AppKit

/// Settings window (⌘,): workspace folder, bot URL and token, the claude CLI, version.
struct SettingsView: View {
    @AppStorage("workspace") private var workspace = ""
    @AppStorage("apiBase") private var apiBase = ""
    @State private var tokenInput = ""
    @State private var botStatus = ""
    @State private var claudeStatus = ""
    @State private var reminders = ReminderScheduler.enabled
    @State private var relay = RelayWorker.enabled
    @State private var hasToken = Router.shared.tokenPresent
    @AppStorage(AccentTheme.key) private var theme = AccentTheme.all[0].id

    var body: some View {
        Form {
            Section("Appearance") {
                HStack(spacing: 14) {
                    ForEach(AccentTheme.all) { t in
                        Button { AccentTheme.choose(t.id); theme = t.id } label: {
                            VStack(spacing: 4) {
                                Circle().fill(Color(nsColor: NSColor(name: nil) { ap in
                                    let h = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? t.accent.dark : t.accent.light
                                    return NSColor(red: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
                                }))
                                .frame(width: 28, height: 28)
                                .overlay { if theme == t.id { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) } }
                                Text(t.title).font(.caption).foregroundStyle(theme == t.id ? .primary : .secondary)
                            }
                        }.buttonStyle(.plain)
                        .accessibilityLabel(t.title).accessibilityAddTraits(theme == t.id ? .isSelected : [])
                    }
                }
            }
            Section("Workspace") {
                Text(Config.workspace).textSelection(.enabled).foregroundStyle(.secondary)
                Text(Config.looksLikeWorkspace(Config.workspace) ? "Looks like a Study Workspace folder." : "No resources/ or CLAUDE.md here: Study pages will be empty.")
                    .font(.caption).foregroundStyle(Config.looksLikeWorkspace(Config.workspace) ? Color.secondary : Color.orange)
                HStack {
                    Button("Choose folder…") { chooseFolder() }
                    if !workspace.isEmpty { Button("Use default") { workspace = "" } }
                }
            }
            Section("Bot") {
                TextField("API URL (https)", text: $apiBase, prompt: Text(Config.defaultAPIBase))
                if !apiBase.isEmpty && !Config.validAPIBase(apiBase) { Text("Not a valid https URL: the default is used.").font(.caption).foregroundStyle(.orange) }
                let host = URL(string: Config.apiBase)?.host ?? "?"
                Text("The token is sent to \(host)").font(.caption)
                    .foregroundStyle(host.hasSuffix(".supabase.co") ? Color.secondary : Color.orange)
                SecureField(hasToken ? "Token saved — paste to replace" : "Paste your token", text: $tokenInput)
                HStack {
                    Button("Save token") { saveToken() }.disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).count < 32)
                    Button("Test connection") { Task { await testBot() } }
                    if !botStatus.isEmpty { Text(botStatus).font(.caption).foregroundStyle(.secondary) }
                }
            }
            PairingSection()
            Section("Reminders") {
                Toggle("Notify about deadlines", isOn: Binding(get: { reminders }, set: { on in
                    reminders = on
                    Task {
                        if on { reminders = await ReminderScheduler.enable() } else { await ReminderScheduler.disable() }
                    }
                }))
                Text("The evening before (18:00) and the morning of the day (09:00), for open deadlines and exams.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Agent") {
                Text(ClaudeBinary.find() ?? "claude CLI not found (install Claude Code, then sign in with `claude auth login`)")
                    .textSelection(.enabled).foregroundStyle(.secondary)
                HStack {
                    Button("Check") { Task { claudeStatus = await checkClaude() } }
                    if !claudeStatus.isEmpty { Text(claudeStatus).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("iPhone questions") {
                Toggle("Answer questions from my iPhone", isOn: Binding(get: { relay }, set: { on in
                    relay = on; UserDefaults.standard.set(on, forKey: RelayWorker.enabledKey); RelayWorker.shared.apply()
                }))
                Text("While Life Desk is open, questions you send from the Feed with “Ask Mac” are answered by Claude here, in the “iPhone” chat, and the answer goes back to the Feed. The agent can change files in the Study Workspace folder, with the usual safety copy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("About") {
                Text("Life Desk \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
            }
        }
        .formStyle(.grouped).frame(width: 520, height: 720).padding()
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Use folder"
        if p.runModal() == .OK, let u = p.url { workspace = u.path }
    }

    private func saveToken() {
        let t = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ad-hoc signature: the file is read first, so the new token must replace the old one there too.
        if !Keychain.stablySigned {
            try? SecureFS.write(Data(t.utf8), to: URL(fileURLWithPath: Config.tokenFile))
        }
        hasToken = Keychain.save(t) || !Keychain.stablySigned
        Router.shared.tokenPresent = true
        tokenInput = ""
        botStatus = hasToken ? "Saved." : "Could not save to the Keychain."
    }

    private func testBot() async {
        botStatus = "Checking…"
        do { _ = try await BotAPI.fetchStudy(); botStatus = "Connected." }
        catch let e as BotAPI.Err { botStatus = e.message } catch { botStatus = BotAPI.Err.network.message }
    }

    private func checkClaude() async -> String {
        guard let bin = ClaudeBinary.find() else { return "Not found." }
        return await Task.detached {
            let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = ["--version"]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            do { try p.run() } catch { return "Could not start." }
            p.waitUntilExit()
            let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return p.terminationStatus == 0 ? "OK: \(s)" : "Failed (exit \(p.terminationStatus))."
        }.value
    }
}
