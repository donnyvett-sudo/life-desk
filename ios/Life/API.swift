import Foundation

enum LifeAPI {
    static let defaultBase = Config.defaultAPIBase
    /// https only; anything else falls back to the default (same rule as Life Desk's Config.validAPIBase).
    static var base: String {
        let v = UserDefaults.standard.string(forKey: "apiBase")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // The token goes to this host, so an override is only honoured for the project's own domain.
        guard let u = URL(string: v), u.scheme == "https", let h = u.host, h == URL(string: defaultBase)?.host, u.user == nil else { return defaultBase }
        return v
    }

    enum Err: Error { case noToken, network, rateLimited }
    /// Posted when the server says the token is gone (revoked): the app returns to the connect screen.
    static let tokenRejected = BotAPI.tokenRejected

    /// One request with the personal token. Reads are retried once on a server error; writes never are.
    static func raw(_ method: String, _ path: String, body: Data? = nil, token: String? = nil, idempotencyKey: String? = nil, timeout: TimeInterval = 20) async throws -> (status: Int, data: Data) {
        guard let token = token ?? TokenStore.load(), let url = URL(string: base + path) else { throw Err.noToken }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = method
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.setValue(token, forHTTPHeaderField: "X-Token")
        // A retry of the same action carries the same key: the server answers with the first result instead of doing it twice.
        if let idempotencyKey { r.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let body { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = body }
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

    /// The sibling functions (quick-entry, sleep-webhook) live next to /api on the same host.
    static func functionURL(_ name: String) -> URL? {
        guard var c = URLComponents(string: base) else { return nil }
        var parts = c.path.split(separator: "/").map(String.init)
        guard parts.last == "api" else { return nil }
        parts[parts.count - 1] = name
        c.path = "/" + parts.joined(separator: "/")
        return c.url
    }

    static func functionPost(_ name: String, json: [String: Any]) async throws -> (status: Int, data: Data) {
        guard let token = TokenStore.load(), let url = functionURL(name) else { throw Err.noToken }
        var r = URLRequest(url: url, timeoutInterval: 30)
        r.httpMethod = "POST"
        r.setValue(token, forHTTPHeaderField: "X-Token")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: json)
        do {
            let (data, resp) = try await URLSession.shared.data(for: r)
            return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch { throw Err.network }
    }

    /// Unauthenticated: a one-time pairing code is exchanged for this device's own token.
    static func pair(code: String, deviceName: String) async throws -> String? {
        guard let url = URL(string: base + "/auth/pair") else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "deviceName": deviceName, "platform": "ios"])
        let (data, resp) = try await URLSession.shared.data(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw Err.rateLimited }
        guard status == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return j["token"] as? String
    }
}
