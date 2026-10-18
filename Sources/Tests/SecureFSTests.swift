import Foundation

func secureFSTests() {
    let fm = FileManager.default
    let base = NSTemporaryDirectory() + "ld-secure-\(getpid())"
    defer { try? fm.removeItem(atPath: base) }
    let u = URL(fileURLWithPath: base + "/deep/er/chats.json")
    try! SecureFS.write(Data("{}".utf8), to: u, excludeFromBackup: true)
    func mode(_ p: String) -> Int { ((try? fm.attributesOfItem(atPath: p))?[.posixPermissions] as? NSNumber)?.intValue ?? -1 }
    expect(mode(u.path) == 0o600, "secure: file is 0600 (got \(String(mode(u.path), radix: 8)))")
    expect(mode(base + "/deep/er") == 0o700, "secure: folder is 0700")
    expect((try? u.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup == true, "secure: excluded from backup")
    // a file from an earlier version with default permissions is tightened
    let old = URL(fileURLWithPath: base + "/old/chat.json")
    try? fm.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? "x".write(to: old, atomically: true, encoding: .utf8)
    chmod(old.path, 0o644); chmod(old.deletingLastPathComponent().path, 0o755)
    SecureFS.tighten(old)
    expect(mode(old.path) == 0o600 && mode(old.deletingLastPathComponent().path) == 0o700, "secure: old files are tightened")
    print("SecureFS tests OK")
}
