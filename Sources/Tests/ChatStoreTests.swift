import Foundation

func chatStoreTests() {
    let dir = NSTemporaryDirectory() + "ld-chats-\(getpid())"
    let fm = FileManager.default
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(atPath: dir) }
    func url(_ n: String) -> URL { URL(fileURLWithPath: "\(dir)/\(n)") }
    func backups(_ n: String) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasPrefix("\(n).bad-") }
    }
    let none = url("none-legacy.json")

    // 1) damaged file, and a backup from an earlier crash already exists: the earlier copy is kept
    let u1 = url("c1.json")
    try? "OLD BACKUP".write(to: URL(fileURLWithPath: u1.path + ".bad"), atomically: true, encoding: .utf8)
    try? "{ not json".write(to: u1, atomically: true, encoding: .utf8)
    let r1 = ChatLibraryStore.read(from: u1, legacy: none)
    expect(r1.library.chats.isEmpty && !r1.readOnly && r1.warnings.count == 1, "damaged file: empty library with a warning")
    expect(backups("c1.json").count == 1, "damaged file: new timestamped backup")
    expect((try? String(contentsOfFile: u1.path + ".bad")) == "OLD BACKUP", "damaged file: earlier .bad untouched")
    expect(!fm.fileExists(atPath: u1.path), "damaged file: moved aside")

    // 2) one unreadable chat among three: the others load, the original is kept
    let good1 = ChatState(messages: [ChatMessage(fromUser: true, text: "one")], sessionID: "s1", started: true)
    let good2 = ChatState(messages: [ChatMessage(fromUser: true, text: "two")], sessionID: "s2", started: true)
    let enc = JSONEncoder()
    let j1 = String(data: try! enc.encode(good1), encoding: .utf8)!
    let j2 = String(data: try! enc.encode(good2), encoding: .utf8)!
    let u2 = url("c2.json")
    try? "{\"schemaVersion\":1,\"chats\":[\(j1),{\"messages\":\"oops\",\"id\":5},\(j2)]}".write(to: u2, atomically: true, encoding: .utf8)
    let r2 = ChatLibraryStore.read(from: u2, legacy: none)
    expect(r2.library.chats.count == 2 && r2.library.chats[0].messages[0].text == "one", "lossy: two good chats load")
    expect(r2.warnings.count == 1 && backups("c2.json").count == 1 && !r2.readOnly, "lossy: warning and backup of the original")
    expect(fm.fileExists(atPath: u2.path), "lossy: original stays in place until the next save")

    // 3) old file without schemaVersion
    let u3 = url("c3.json")
    try? "{\"chats\":[\(j1)]}".write(to: u3, atomically: true, encoding: .utf8)
    expect(ChatLibraryStore.read(from: u3, legacy: none).library.chats.count == 1, "old file without schemaVersion reads")

    // 3b) written by a newer version: read-only so nothing is lost
    let u3b = url("c3b.json")
    try? "{\"schemaVersion\":99,\"chats\":[\(j1)],\"newField\":true}".write(to: u3b, atomically: true, encoding: .utf8)
    let r3b = ChatLibraryStore.read(from: u3b, legacy: none)
    expect(r3b.readOnly && r3b.library.chats.count == 1 && r3b.warnings.count == 1, "newer schema: read-only with a warning")

    // 4) save writes the schema version and reports failures instead of swallowing them
    let u4 = url("c4.json")
    do { try ChatLibraryStore.save(ChatLibrary(chats: [good1], currentID: good1.id), to: u4) } catch { expect(false, "save failed: \(error)") }
    expect(((try? String(contentsOf: u4)) ?? "").contains("\"schemaVersion\":1"), "save: schemaVersion written")
    var failed = false
    do { try ChatLibraryStore.save(ChatLibrary(), to: URL(fileURLWithPath: "/dev/null/impossible/chats.json")) } catch { failed = true }
    expect(failed, "save: error is thrown, not swallowed")

    // 5) unreadable (directory instead of file): never claimed to be empty-and-writable
    let u5 = url("c5.json")
    try? fm.createDirectory(at: u5, withIntermediateDirectories: true)
    let r5 = ChatLibraryStore.read(from: u5, legacy: none)
    expect(r5.library.chats.isEmpty && (r5.readOnly || !backups("c5.json").isEmpty), "unreadable path: read-only or set aside")

    print("Chat store tests OK")
}
