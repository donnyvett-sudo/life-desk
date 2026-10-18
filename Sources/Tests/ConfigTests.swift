import Foundation

func configTests() {
    expect(Config.validAPIBase("https://x.supabase.co/functions/v1/api"), "config: https accepted")
    for bad in ["http://x.co/api", "ftp://x", "https://", "https://u:p@x.co/api", "nonsense", ""] {
        expect(!Config.validAPIBase(bad), "config: refuses \(bad)")
    }
    let d = UserDefaults(suiteName: "lifedesk.test.\(UUID().uuidString)")!
    let old = Config.defaults; Config.defaults = d; defer { Config.defaults = old }
    d.set("http://evil.example/api", forKey: "apiBase")
    if ProcessInfo.processInfo.environment["LIFE_DESK_API"] == nil { expect(Config.apiBase == Config.defaultAPIBase, "config: bad override falls back") }
    d.set("https://mine.example/api", forKey: "apiBase")
    if ProcessInfo.processInfo.environment["LIFE_DESK_API"] == nil { expect(Config.apiBase == "https://mine.example/api", "config: override used") }
    expect(!Config.looksLikeWorkspace("/nonexistent-\(UUID().uuidString)"), "config: missing folder is not a workspace")
    print("Config tests OK")
}
