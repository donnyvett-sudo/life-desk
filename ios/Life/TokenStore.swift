import Foundation
import Security

/// The personal API token lives only in the Keychain (the same Core `Keychain` the Mac app uses): never in page JavaScript.
enum TokenStore {
    /// The first iPhone builds kept the token under their own service name; it moves over once.
    private static func legacy() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "LifeIOS",
                                kSecAttrAccount as String: "api_token", kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    // A Keychain read is a synchronous IPC call; the Feed poll and the web bridge ask for the token constantly.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String?

    static func load() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        cached = read()
        return cached
    }

    private static func read() -> String? {
        if let t = Keychain.token() { return t }
        if let old = legacy(), Keychain.save(old) {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "LifeIOS"] as CFDictionary)
            return old
        }
        return nil
    }

    @discardableResult static func save(_ token: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let ok = Keychain.save(token)
        cached = ok ? token : nil
        return ok
    }
    static func clear() {
        lock.lock(); defer { lock.unlock() }
        cached = nil
        Keychain.clear()
    }
}
