import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var fromUser: Bool
    var text: String
    /// Files the agent changed while producing this answer (kept for undo; absent in older histories).
    var changes: ChangeSet?
}

/// One conversation. `id`, `title` and `updated` are optional in old files (a single-chat `chat.json` had none).
struct ChatState: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var updated = Date()
    var messages: [ChatMessage] = []
    var sessionID = UUID().uuidString.lowercased()
    var started = false

    init(messages: [ChatMessage] = [], sessionID: String = UUID().uuidString.lowercased(), started: Bool = false) {
        self.messages = messages; self.sessionID = sessionID; self.started = started
    }

    private enum CodingKeys: String, CodingKey { case id, title, updated, messages, sessionID, started }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? Date()
        messages = try c.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID) ?? UUID().uuidString.lowercased()
        started = try c.decodeIfPresent(Bool.self, forKey: .started) ?? false
    }
}

enum ChatStore {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LifeDesk/chat.json")
    }

    static func load(from u: URL = url) -> ChatState? {
        guard let d = try? Data(contentsOf: u) else { return nil }
        if let s = try? JSONDecoder().decode(ChatState.self, from: d) { return s }
        // Unreadable (corrupt or an older schema): keep it aside instead of overwriting it on the next save.
        try? FileManager.default.moveItem(at: u, to: u.appendingPathExtension("bad"))
        return nil
    }

    static func save(_ s: ChatState, to u: URL = url) {
        if let d = try? JSONEncoder().encode(s) { try? SecureFS.write(d, to: u, excludeFromBackup: true) }
    }

    static func delete(at u: URL = url) { try? FileManager.default.removeItem(at: u) }
}

/// All chats plus the one that is open. Lives in `chats.json`; a legacy single `chat.json` is imported once.
struct ChatLibrary: Codable, Equatable {
    static let currentSchema = 1
    var schemaVersion = ChatLibrary.currentSchema
    var chats: [ChatState] = []
    var currentID: UUID?

    init(chats: [ChatState] = [], currentID: UUID? = nil) {
        self.chats = chats; self.currentID = currentID
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, chats, currentID }

    /// One unreadable chat must not take the others with it.
    private struct Lossy: Decodable {
        let value: ChatState?
        init(from d: Decoder) throws { value = try? ChatState(from: d) }
    }

    /// Chats that could not be read in the last decode (not persisted).
    private(set) var skipped = 0

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        let raw = try c.decodeIfPresent([Lossy].self, forKey: .chats) ?? []
        chats = raw.compactMap { $0.value }
        skipped = raw.count - chats.count
        currentID = try? c.decodeIfPresent(UUID.self, forKey: .currentID)
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(ChatLibrary.currentSchema, forKey: .schemaVersion)
        try c.encode(chats, forKey: .chats)
        try c.encodeIfPresent(currentID, forKey: .currentID)
    }

    static func == (l: ChatLibrary, r: ChatLibrary) -> Bool { l.chats == r.chats && l.currentID == r.currentID }
}

/// What came out of reading the library file.
struct ChatLoadResult {
    var library: ChatLibrary
    /// Things the user should hear about (a backup was made, chats were skipped, ...).
    var warnings: [String] = []
    /// The file exists but could not be read nor moved aside: saving would destroy it, so don't.
    var readOnly = false
}

enum ChatLibraryStore {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LifeDesk/chats.json")
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    /// A copy next to the original: `chats.json.bad-20261015-141500`. Never overwrites an earlier one.
    private static func backupURL(_ u: URL) -> URL {
        var n = 0
        while true {
            let suffix = n == 0 ? "bad-\(stamp())" : "bad-\(stamp())-\(n)"
            let c = u.appendingPathExtension(suffix)
            if !FileManager.default.fileExists(atPath: c.path) { return c }
            n += 1
        }
    }

    static func read(from u: URL = url, legacy: URL = ChatStore.url) -> ChatLoadResult {
        let fm = FileManager.default
        if fm.fileExists(atPath: u.path) {
            guard let d = try? Data(contentsOf: u) else {
                return ChatLoadResult(library: ChatLibrary(),
                                      warnings: ["The chat file can't be read; history is shown empty and won't be overwritten."],
                                      readOnly: true)
            }
            if let lib = try? JSONDecoder().decode(ChatLibrary.self, from: d) {
                SecureFS.tighten(u)  // files from earlier versions were created with default permissions
                // Written by a newer version of the app: saving would drop what this version doesn't know.
                if lib.schemaVersion > ChatLibrary.currentSchema {
                    return ChatLoadResult(library: lib,
                                          warnings: ["Chats were saved by a newer version of Life Desk; they are shown read-only here."],
                                          readOnly: true)
                }
                var r = ChatLoadResult(library: lib)
                if lib.skipped > 0 {
                    // Keep the original before the next save drops the unreadable chats for good.
                    let b = backupURL(u)
                    if (try? fm.copyItem(at: u, to: b)) != nil {
                        r.warnings.append("\(lib.skipped) chat(s) could not be read and were skipped. The original is kept as \(b.lastPathComponent).")
                    } else {
                        r.warnings.append("\(lib.skipped) chat(s) could not be read; history is read-only until it is fixed.")
                        r.readOnly = true
                    }
                }
                return r
            }
            // Not valid at all: set it aside under a fresh name; if that fails, never write over it.
            let b = backupURL(u)
            if (try? fm.moveItem(at: u, to: b)) != nil {
                return ChatLoadResult(library: ChatLibrary(),
                                      warnings: ["The chat file was damaged. It is kept as \(b.lastPathComponent); history starts empty."])
            }
            return ChatLoadResult(library: ChatLibrary(),
                                  warnings: ["The chat file is damaged and couldn't be set aside; history is read-only."],
                                  readOnly: true)
        }
        if var old = ChatStore.load(from: legacy), !old.messages.isEmpty {
            old.title = ChatTitle.make(from: old.messages.first(where: { $0.fromUser })?.text ?? "")
            return ChatLoadResult(library: ChatLibrary(chats: [old], currentID: old.id))
        }
        return ChatLoadResult(library: ChatLibrary())
    }

    static func load(from u: URL = url, legacy: URL = ChatStore.url) -> ChatLibrary { read(from: u, legacy: legacy).library }

    static func save(_ l: ChatLibrary, to u: URL = url) throws {
        try SecureFS.write(try JSONEncoder().encode(l), to: u, excludeFromBackup: true)
    }
}

enum ChatTitle {
    /// First line of the question, spaces collapsed, cut at `limit` characters.
    static func make(from text: String, limit: Int = 42) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let s = line.split(separator: " ").joined(separator: " ")
        if s.isEmpty { return "New chat" }
        guard s.count > limit else { return s }
        return String(s.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Assistant text split into fenced code blocks and everything else (the rest goes to the markdown renderer).
enum ChatBlock: Equatable {
    case markdown(String)
    case code(lang: String, body: String)

    /// An unclosed fence (text is still streaming) counts as code up to the end.
    static func split(_ text: String) -> [ChatBlock] {
        var out: [ChatBlock] = []
        var md: [String] = [], code: [String] = [], lang = "", inCode = false
        func flushMD() {
            let s = md.joined(separator: "\n")
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.markdown(s)) }
            md = []
        }
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                if inCode { out.append(.code(lang: lang, body: code.joined(separator: "\n"))); code = []; inCode = false }
                else { flushMD(); lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces); inCode = true }
            } else if inCode { code.append(line) } else { md.append(line) }
        }
        if inCode { out.append(.code(lang: lang, body: code.joined(separator: "\n"))) } else { flushMD() }
        return out
    }
}
