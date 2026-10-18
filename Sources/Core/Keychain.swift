import Foundation
import Security

/// The personal bot token lives in the Keychain. First start imports it from ~/.config/life-agent/token.
enum Keychain {
    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Config.keychainService,
         kSecAttrAccount as String: Config.keychainAccount]
    }

    static func token() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
        // Update in place (a failed add after a delete would lose the token).
        if SecItemUpdate(query() as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess { return true }
        #if os(iOS)
        var q = query()
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly   // readable by background refresh
        q[kSecAttrSynchronizable as String] = false
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        #else
        var q = query()
        q[kSecValueData as String] = data
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        #endif
    }

    static func clear() { SecItemDelete(query() as CFDictionary) }

    /// True when the running app carries a real (not ad-hoc) signature: its Keychain items then stay readable
    /// across rebuilds, so the Keychain can be the main store.
    static let stablySigned: Bool = {
        #if os(macOS)
            var code: SecCode?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
            var staticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                  let dict = info as? [String: Any], let flags = dict[kSecCodeInfoFlags as String] as? UInt32 else { return false }
            return flags & 0x2 == 0  // 0x2 = adhoc
        #else
        return true   // an iOS app always carries a real signature
        #endif
    }()

    private static func valid(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), t.count >= 32 else { return nil }
        return t
    }

    /// Where the token comes from. Pure so the order can be tested.
    /// Stable signature: Keychain first; a token found only in the file is moved into the Keychain.
    /// Ad-hoc signature: the file first (reading a file never prompts), the Keychain as a fallback.
    static func resolve(stable: Bool, file: () -> String?, keychain: () -> String?, store: (String) -> Void) -> String? {
        if stable {
            if let t = valid(keychain()) { return t }
            if let t = valid(file()) { store(t); return t }
            return nil
        }
        return valid(file()) ?? valid(keychain())
    }

    static func loadOrImport() -> String? {
        resolve(stable: stablySigned,
                file: { try? String(contentsOfFile: Config.tokenFile, encoding: .utf8) },
                keychain: { token() },
                store: { save($0) })
    }
}
