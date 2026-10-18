import AppIntents

/// «Tell Life …» in Siri, Shortcuts and Spotlight: sends the line to the coach exactly like the Feed input
/// («кофе 18», «съел 2 яйца», «what is due today?») and speaks the answer.
struct TellLifeIntent: AppIntent {
    static let title: LocalizedStringResource = "Tell Life"
    static let description = IntentDescription("Log an expense, a meal, a task, or ask the coach.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Message", requestValueDialog: "What should I tell Life?") var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 2000 else { return .result(dialog: Self.say(L("Nothing to send."))) }
        let body = try? JSONSerialization.data(withJSONObject: ["text": t])
        do {
            let r = try await LifeAPI.raw("POST", "/entry", body: body)
            guard r.status == 200 else { return .result(dialog: Self.say(r.status == 401 ? L("Open Life once to reconnect.") : L("Life could not take that (\(r.status))."))) }
            let plain = (QuickEntryModel.render(r.data) ?? L("Saved.")).replacingOccurrences(of: "[*_`]", with: "", options: .regularExpression)
            return .result(dialog: Self.say(String(plain.prefix(400))))
        } catch { return .result(dialog: Self.say(L("No connection. Nothing was saved."))) }
    }

    private static func say(_ s: String) -> IntentDialog { IntentDialog(stringLiteral: s) }
}

struct LifeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TellLifeIntent(), phrases: ["Tell \(.applicationName)", "Log in \(.applicationName)", "Ask \(.applicationName)"],
                    shortTitle: "Tell Life", systemImageName: "text.bubble")
    }
}
