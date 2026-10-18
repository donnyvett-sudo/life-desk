import Foundation

enum BotAPI {
    static var base: String { Config.apiBase }
    /// Posted when the server answers 401: the app (iPhone) goes back to its connect screen.
    static let tokenRejected = Notification.Name("LifeTokenRejected")
    enum Err: Error, Equatable {
        case noToken, unauthorized, http(Int), network, decoding
        /// What the user is told (never a raw status code alone).
        var message: String {
            switch self {
            case .noToken: "No bot token"
            case .unauthorized: "Token not accepted"
            case .http(let c): "Bot error \(c)"
            case .network: "No connection to the bot"
            case .decoding: "Bot reply not understood (update the app)"
            }
        }
    }

    /// One request to the bot API with the personal token; returns the status and body whatever the status is.
    /// The only place that adds the token (also used by the web view bridge, so the page never sees it).
    static func raw(_ method: String, _ path: String, body: Data? = nil) async throws -> (status: Int, data: Data) {
        guard let token = Keychain.loadOrImport(), let url = URL(string: base + path) else { throw Err.noToken }
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.httpMethod = method
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.setValue(token, forHTTPHeaderField: "X-Token")
        if let body { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = body }
        // One retry for reads on a server error or timeout (a write is never repeated).
        for attempt in 0..<(method == "GET" ? 2 : 1) {
            do {
                let (data, resp) = try await URLSession.shared.data(for: r)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if status >= 500, attempt == 0, method == "GET" { try? await Task.sleep(nanoseconds: 700_000_000); continue }
                if status == 401 { NotificationCenter.default.post(name: tokenRejected, object: nil) }
                return (status, data)
            } catch let e as URLError {
                if e.code == .cancelled { throw CancellationError() }
                throw Err.network
            }
        }
        throw Err.network
    }

    private static func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        let payload = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let (status, data) = try await raw(method, path, body: payload)
        if status == 401 || status == 403 { throw Err.unauthorized }
        if status >= 300 { throw Err.http(status) }
        return data
    }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LifeDesk")
        try? SecureFS.privateDirectory(dir)
        return dir.appendingPathComponent("study.json")
    }

    /// Fresh overview (cached on success).
    static func fetchStudy() async throws -> BotStudy {
        let data = try await request("GET", "/study")
        guard let s = try? JSONDecoder().decode(BotStudy.self, from: data) else { throw Err.decoding }
        try? SecureFS.write(data, to: cacheURL)
        return s
    }
    /// When the cached overview was fetched (file time), nil without a cache.
    /// Forget the saved overview (another account is about to use this device).
    static func clearCache() { try? FileManager.default.removeItem(at: cacheURL) }

    static func cacheDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: cacheURL.path))?[.modificationDate] as? Date
    }
    static func cachedStudy() -> BotStudy? {
        (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(BotStudy.self, from: $0) }
    }
    /// Starts a focus session in the bot (it counts the minutes and messages Telegram at the end).
    static func startFocus(courseId: String?, minutes: Int) async throws {
        var body: [String: Any] = ["minutes": minutes]
        if let courseId { body["courseId"] = courseId }
        _ = try await request("POST", "/focus", body: body)
    }
    static func stopFocus(id: String) async throws {
        _ = try await request("POST", "/focus/\(id)/stop", body: [:])
    }
    static func setDone(id: String, done: Bool) async throws {
        _ = try await request("PATCH", "/assignments/\(id)", body: ["done": done])
    }
}
