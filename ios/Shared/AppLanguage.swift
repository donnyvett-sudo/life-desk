import SwiftUI

/// In-app language: "system" | "en" | "ru" in UserDefaults ("app.lang"). SwiftUI literals follow `.environment(\.locale)`
/// set at the root; every String the app builds itself goes through `L(...)`, which reads the same choice.
enum AppLanguage {
    static let key = "app.lang"
    /// The App Group store, so the widgets and Live Activity read the same choice as the app.
    static let store = UserDefaults(suiteName: WidgetSnapshot.group) ?? .standard
    static var choice: String { store.string(forKey: key) ?? "system" }
    static var locale: Locale { choice == "system" ? .autoupdatingCurrent : Locale(identifier: choice) }
    /// The .lproj of the chosen language; the main bundle (system language) when "system" or when the folder is missing.
    static var bundle: Bundle {
        guard choice != "system", let p = Bundle.main.path(forResource: choice, ofType: "lproj"), let b = Bundle(path: p) else { return .main }
        return b
    }
    /// Translates a dynamic English string (an error from shared code, a bucket name) when the catalog has it; otherwise as is.
    static func tr(_ s: String) -> String { bundle.localizedString(forKey: s, value: s, table: nil) }
}

/// A localized String in the chosen language, for text SwiftUI does not localize itself (String parameters, notes, errors).
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: AppLanguage.bundle, locale: AppLanguage.locale)
}
