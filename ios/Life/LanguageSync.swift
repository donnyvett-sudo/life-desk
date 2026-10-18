import Foundation

/// The server writes the coach's messages (and the Mini App reads its language) from settings.lang:
/// keep it equal to the language chosen in the app.
enum LanguageSync {
    /// "ru" or "en": the app's choice, or the phone's first language when the choice is "system".
    static var effective: String {
        let c = AppLanguage.choice
        if c == "ru" || c == "en" { return c }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("ru") ? "ru" : "en"
    }

    static func push(reloadPage: Bool = false) async {
        let code = effective
        let body = try? JSONSerialization.data(withJSONObject: ["lang": code])
        _ = try? await LifeAPI.raw("PUT", "/settings", body: body)
        UserDefaults.standard.set(code, forKey: "lang.sent")
        if reloadPage { await MainActor.run { LifeWebHolder.shared.setLanguage(code) } }
    }

    /// Once per launch when the choice changed outside the picker (the phone's own language switched).
    static func syncIfNeeded() async {
        if UserDefaults.standard.string(forKey: "lang.sent") != effective { await push() }
    }
}
