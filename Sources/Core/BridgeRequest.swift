import Foundation

/// A request from the Mini App to the bot API, as it arrives through the web view bridge.
/// The page never holds the token: Swift adds it, and only paths of the bot API on the fixed host are possible.
struct BridgeRequest: Equatable {
    var method: String
    var path: String
    var body: Data?

    static let methods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE"]
    static let maxPath = 1024
    static let maxBody = 1_000_000

    /// Nil when anything is off: unknown method, a path that could leave the API, a body that is too large.
    static func parse(_ raw: Any) -> BridgeRequest? {
        guard let d = raw as? [String: Any],
              let method = (d["method"] as? String)?.uppercased(), methods.contains(method),
              let path = d["path"] as? String, validPath(path) else { return nil }
        var body: Data?
        if let b = d["body"], !(b is NSNull) {
            guard JSONSerialization.isValidJSONObject(b) || b is String || b is NSNumber,
                  let data = try? JSONSerialization.data(withJSONObject: b, options: [.fragmentsAllowed]),
                  data.count <= maxBody else { return nil }
            body = data
        }
        return BridgeRequest(method: method, path: path, body: body)
    }

    static func validPath(_ p: String) -> Bool {
        guard p.hasPrefix("/"), p.count <= maxPath, !p.hasPrefix("//") else { return false }
        if p.contains("..") || p.contains("\\") || p.contains("@") || p.contains("://") || p.contains("#") { return false }
        // Encoded dots, slashes and backslashes would reach other paths once the server decodes them; /auth is native-only.
        let lower = p.lowercased()
        if lower.contains("%2e") || lower.contains("%2f") || lower.contains("%5c") || lower.contains("%00") { return false }
        if lower == "/auth" || lower.hasPrefix("/auth/") || lower.hasPrefix("/auth?") { return false }
        // Letters, digits and the characters of ordinary paths and query strings; nothing else (no control characters).
        let ok = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/?=&%:+,")
        return p.unicodeScalars.allSatisfy { ok.contains($0) }
    }
}
