import Foundation

/// Paired clients (iPhone app, PWA) and the one-time code that pairs a new one.
enum Devices {
    struct Code: Equatable {
        var code: String
        var expiresAt: Date
        var scopes: [String]
    }
    struct Device: Equatable, Identifiable {
        var id: String
        var name: String
        var platform: String
        var createdAt: Date?
        var lastSeen: Date?
    }

    static func parseCode(_ data: Data) -> Code? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = j["code"] as? String, code.count == 9,
              let exp = (j["expiresAt"] as? String).flatMap(parseDate) else { return nil }
        return Code(code: code, expiresAt: exp, scopes: (j["scopes"] as? [String]) ?? [])
    }

    static func parseDevices(_ data: Data) -> [Device] {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = j["devices"] as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            return Device(id: id, name: name, platform: d["platform"] as? String ?? "other",
                          createdAt: (d["created_at"] as? String).flatMap(parseDate),
                          lastSeen: (d["last_seen"] as? String).flatMap(parseDate))
        }
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Asks the server for a new pairing code. Needs the Mac's full-access token.
    static func createCode() async throws -> Code {
        // admin: this is the owner's own phone (friends, invites, Mac questions); the server refuses it for anyone else.
        let body = try JSONSerialization.data(withJSONObject: ["scopes": ["app", "ingest", "admin"]])
        let (status, data) = try await BotAPI.raw("POST", "/auth/pairing-code", body: body)
        if status == 403 { throw BotAPI.Err.http(403) }
        guard status == 200, let c = parseCode(data) else { throw BotAPI.Err.http(status) }
        return c
    }

    static func list() async throws -> [Device] {
        let (status, data) = try await BotAPI.raw("GET", "/devices")
        guard status == 200 else { throw BotAPI.Err.http(status) }
        return parseDevices(data)
    }

    static func remove(_ id: String) async throws {
        let (status, _) = try await BotAPI.raw("DELETE", "/devices/\(id)")
        guard status == 200 else { throw BotAPI.Err.http(status) }
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let c = Data(#"{"code":"K7M2-PX4R","expiresAt":"2026-10-16T09:50:00.123Z","scopes":["app","ingest"]}"#.utf8)
        if parseCode(c)?.code != "K7M2-PX4R" || parseCode(c)?.scopes != ["app", "ingest"] { f.append("code") }
        if parseCode(Data(#"{"code":"short","expiresAt":"2026-10-16T09:50:00Z"}"#.utf8)) != nil { f.append("short code refused") }
        if parseCode(Data("nonsense".utf8)) != nil { f.append("garbage") }
        let d = Data(#"{"devices":[{"id":"a1","name":"iPhone","platform":"ios","created_at":"2026-10-16T08:00:00+00:00","last_seen":null},{"name":"no id"}]}"#.utf8)
        let list = parseDevices(d)
        if list.count != 1 || list[0].platform != "ios" || list[0].lastSeen != nil || list[0].createdAt == nil { f.append("devices \(list)") }
        return f
    }
}
