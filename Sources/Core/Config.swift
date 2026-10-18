import Foundation

/// Paths and constants shared by the app. Order: environment variable, then the user's Settings (UserDefaults), then the default.
/// These defaults are the only place that names a particular machine or backend.
enum Config {
    static let home = NSHomeDirectory()   // the real home on a Mac; the app container on iOS
    static let defaultWorkspace = "\(home)/Documents/Study Workspace"
    /// Your own backend's API URL, injected at build time (Config.local.xcconfig -> Info.plist key LifeAPIBase).
    /// Empty when the build was made without one: then the URL must be entered in Settings / the connect screen.
    static let defaultAPIBase = (Bundle.main.object(forInfoDictionaryKey: "LifeAPIBase") as? String) ?? ""

    static var defaults: UserDefaults = .standard
    private static func setting(_ key: String) -> String? {
        let v = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }

    /// The Study Workspace workspace (CLAUDE.md, resources/, workflows/).
    static var workspace: String {
        ProcessInfo.processInfo.environment["LIFE_DESK_WORKSPACE"] ?? setting("workspace") ?? defaultWorkspace
    }
    static var resources: String { "\(workspace)/resources" }
    /// The bot's API URL (https only; anything else falls back to the default).
    static var apiBase: String {
        let v = ProcessInfo.processInfo.environment["LIFE_DESK_API"] ?? setting("apiBase") ?? defaultAPIBase
        return validAPIBase(v) ? v : defaultAPIBase
    }
    static func validAPIBase(_ s: String) -> Bool {
        guard let u = URL(string: s), u.scheme == "https", let h = u.host, !h.isEmpty, u.user == nil else { return false }
        return true
    }
    /// A folder that looks like a Study Workspace workspace.
    static func looksLikeWorkspace(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let fm = FileManager.default
        return fm.fileExists(atPath: "\(path)/resources", isDirectory: &isDir) && isDir.boolValue
            || fm.fileExists(atPath: "\(path)/CLAUDE.md")
    }
    /// Where `tools/life_sync.py` and the bot keep the personal token.
    static var tokenFile: String { "\(home)/.config/life-agent/token" }
    static let keychainService = "LifeDesk"
    static let keychainAccount = "ingest_token"
}
