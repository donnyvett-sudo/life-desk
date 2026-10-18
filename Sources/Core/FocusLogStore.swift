import Foundation

/// focus-log.json in Application Support (0600): the daily minutes behind the heatmap.
enum FocusLogStore {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LifeDesk").appendingPathComponent("focus-log.json")
    }
    static func load(from url: URL = url) -> FocusLog {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(FocusLog.self, from: $0) } ?? FocusLog()
    }
    static func save(_ log: FocusLog, to url: URL = url) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        try? SecureFS.write(data, to: url)
    }
}
