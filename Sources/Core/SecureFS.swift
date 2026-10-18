import Foundation

/// Where the app keeps personal data (chats, a copy of deadlines): readable by the owner only, not in backups.
enum SecureFS {
    /// Creates the folder (and parents) as 0700 and keeps it that way.
    static func privateDirectory(_ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Only touch it when others could get in (a system folder that is already private may refuse chmod).
        let mode = ((try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
        if mode & 0o077 != 0 { try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
    }

    /// Atomic write into a private folder, file mode 0600. `excludeFromBackup` keeps it out of Time Machine.
    static func write(_ data: Data, to url: URL, excludeFromBackup: Bool = false) throws {
        try privateDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if excludeFromBackup {
            var v = URLResourceValues()
            v.isExcludedFromBackup = true
            var u = url
            try? u.setResourceValues(v)
        }
    }

    /// Brings an existing file (written by an earlier version with default permissions) to 0600.
    static func tighten(_ url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try? privateDirectory(url.deletingLastPathComponent())
    }
}
