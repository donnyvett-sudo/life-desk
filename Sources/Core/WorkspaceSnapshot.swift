import Foundation
import CryptoKit

/// One file the agent changed during a run.
struct FileChange: Equatable, Codable, Identifiable {
    enum Status: String, Codable { case modified, added, deleted }
    var path: String          // relative to the workspace
    var status: Status
    var diff: String          // unified diff, shortened
    var afterHash: String?    // sha256 of the file as the agent left it (nil when deleted)
    var revertible: Bool      // false for files too big to keep a copy of
    /// sha256 of the file before the run (nil when it did not exist); lets a repeated revert recognise finished work.
    var beforeHash: String? = nil
    var id: String { path }
}

/// What a run changed, and what the owner decided about it.
struct ChangeSet: Equatable, Codable {
    enum State: String, Codable { case pending, kept, reverted }
    var snapshotID: String
    var files: [FileChange]
    /// Changes outside the allowed list (should never happen; shown as a warning).
    var outside: [String] = []
    var state: State = .pending
    /// The diffs were cut to keep the saved conversation small.
    var truncated = false

    init(snapshotID: String, files: [FileChange], outside: [String] = [], state: State = .pending, truncated: Bool = false) {
        self.snapshotID = snapshotID; self.files = files; self.outside = outside; self.state = state; self.truncated = truncated
    }

    private enum CodingKeys: String, CodingKey { case snapshotID, files, outside, state, truncated }

    /// Tolerant: an unknown state or a missing field must not make the whole message unreadable.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        snapshotID = try c.decode(String.self, forKey: .snapshotID)
        files = (try? c.decode([FileChange].self, forKey: .files)) ?? []
        outside = (try? c.decode([String].self, forKey: .outside)) ?? []
        state = (try? c.decode(State.self, forKey: .state)) ?? .pending
        truncated = (try? c.decode(Bool.self, forKey: .truncated)) ?? false
    }
}

/// Copies of the files the agent may edit, taken before a run, so every change can be shown and undone byte for byte.
/// Git is deliberately not involved: the owner may have uncommitted edits of their own that a checkout would destroy.
enum WorkspaceSnapshot {
    static let maxCopy = 5 * 1024 * 1024
    static let maxDiffBytes = 8_000
    static let maxStoredDiffBytes = 40_000

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LifeDesk/snapshots")
    }

    private struct Entry: Codable { var existed: Bool; var hash: String?; var copied: Bool }
    private struct Manifest: Codable { var workspace: String; var created: Date; var entries: [String: Entry]; var outside: [String: String] }

    // MARK: which files count

    /// Same patterns as AgentPolicy.editable, as predicates on relative paths.
    static func isEditable(_ rel: String) -> Bool {
        let p = rel.split(separator: "/").map(String.init)
        if p.contains("..") || p.isEmpty { return false }
        if p.count >= 2, p[0] == "output" { return true }
        guard p[0] == "resources" else { return false }
        if p.count == 2 { return p[1] == "exam-dates.md" }
        if p.count == 3 { return p[2] == "assignments.md" || p[2] == "course-info.md" }
        if p.count == 4 { return p[2] == "2026" && p[3] == "files.md" }
        return false
    }

    private static func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    private struct Found { var url: URL; var size: Int; var mtime: Date }

    /// One walk: editable files, and the other .md/.py files (watched, never allowed to change).
    /// Symlinks are not followed (the archive links are never walked); hidden files count.
    private static func scan(_ ws: String) -> (editable: [String: Found], other: [String: Found]) {
        var ed: [String: Found] = [:], other: [String: Found] = [:]
        let base = URL(fileURLWithPath: ws).standardizedFileURL
        let skip: Set<String> = [".git", ".cache", "node_modules", ".venv"]
        guard let en = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                                                      options: []) else { return (ed, other) }
        for case let u as URL in en {
            let rel = String(u.standardizedFileURL.path.dropFirst(base.path.count + 1))
            let name = u.lastPathComponent
            let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            // Symlinks are listed, not followed. (skipDescendants on a non-directory would drop its siblings.)
            if v?.isSymbolicLink == true { continue }
            if v?.isDirectory == true {
                // Outside output/ the skip-list applies; inside output/ everything is watched.
                if !rel.hasPrefix("output/") && skip.contains(name) { en.skipDescendants() }
                continue
            }
            guard v?.isRegularFile == true else { continue }
            let f = Found(url: u, size: v?.fileSize ?? 0, mtime: v?.contentModificationDate ?? .distantPast)
            if isEditable(rel) { ed[rel] = f }
            else if name.hasSuffix(".md") || name.hasSuffix(".py") { other[rel] = f }
        }
        return (ed, other)
    }

    // MARK: take / compare

    /// Takes the snapshot. Returns an id, or nil when nothing could be stored (the caller must not start the agent then).
    static func take(workspace ws: String, in root: URL = root) -> String? {
        let id = UUID().uuidString.lowercased()
        let dir = root.appendingPathComponent(id)
        let files = dir.appendingPathComponent("files")
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            var ex = URLResourceValues(); ex.isExcludedFromBackup = true
            var r = root; try? r.setResourceValues(ex)  // copies of personal files do not belong in Time Machine
            try fm.createDirectory(at: files, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        let (ed, other) = scan(ws)
        var entries: [String: Entry] = [:]
        for (rel, f) in ed {
            guard let data = try? Data(contentsOf: f.url) else { continue }
            var copied = false
            if data.count <= maxCopy {
                let dest = files.appendingPathComponent(rel)
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                copied = (try? data.write(to: dest)) != nil
            }
            entries[rel] = Entry(existed: true, hash: sha(data), copied: copied)
        }
        var outside: [String: String] = [:]
        for (rel, f) in other { outside[rel] = "\(f.size):\(f.mtime.timeIntervalSince1970)" }
        let m = Manifest(workspace: ws, created: Date(), entries: entries, outside: outside)
        guard let d = try? JSONEncoder().encode(m), (try? d.write(to: dir.appendingPathComponent("manifest.json"))) != nil else {
            try? fm.removeItem(at: dir)
            return nil
        }
        return id
    }

    /// Drops a snapshot nobody needs (the run changed nothing).
    static func discard(_ id: String, in root: URL = root) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id))
    }

    private static func manifest(_ id: String, in root: URL) -> Manifest? {
        guard let d = try? Data(contentsOf: root.appendingPathComponent(id).appendingPathComponent("manifest.json")) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: d)
    }

    /// Compares the workspace with the snapshot. Nil when the snapshot is gone.
    static func changes(since id: String, in root: URL = root) -> ChangeSet? {
        guard let m = manifest(id, in: root) else { return nil }
        let (now, otherNow) = scan(m.workspace)
        let copies = root.appendingPathComponent(id).appendingPathComponent("files")
        var out: [FileChange] = []
        for (rel, f) in now {
            let data = (try? Data(contentsOf: f.url)) ?? Data()
            let h = sha(data)
            if let e = m.entries[rel] {
                if e.hash != h {
                    out.append(FileChange(path: rel, status: .modified, diff: diff(old: e.copied ? copies.appendingPathComponent(rel) : nil, new: f.url, oldMissing: !e.copied),
                                          afterHash: h, revertible: e.copied, beforeHash: e.hash))
                }
            } else {
                out.append(FileChange(path: rel, status: .added, diff: diff(old: nil, new: f.url, oldMissing: false), afterHash: h, revertible: true, beforeHash: nil))
            }
        }
        for (rel, e) in m.entries where now[rel] == nil {
            out.append(FileChange(path: rel, status: .deleted, diff: diff(old: e.copied ? copies.appendingPathComponent(rel) : nil, new: nil, oldMissing: !e.copied),
                                  afterHash: nil, revertible: e.copied, beforeHash: e.hash))
        }
        var outside = Set<String>()
        for (rel, f) in otherNow where m.outside[rel] != "\(f.size):\(f.mtime.timeIntervalSince1970)" { outside.insert(rel) }
        for rel in m.outside.keys where otherNow[rel] == nil { outside.insert(rel) }
        out.sort { $0.path < $1.path }
        // The saved conversation keeps at most maxStoredDiffBytes of diff text in total.
        var budget = maxStoredDiffBytes, cut = false
        for i in out.indices {
            if out[i].diff.utf8.count > budget {
                out[i].diff = String(decoding: out[i].diff.utf8.prefix(max(0, budget)), as: UTF8.self) + "\n… (cut)"
                cut = true
            }
            budget = max(0, budget - out[i].diff.utf8.count)
        }
        return ChangeSet(snapshotID: id, files: out, outside: outside.sorted(), truncated: cut)
    }

    private static func diff(old: URL?, new: URL?, oldMissing: Bool) -> String {
        if oldMissing { return "(the earlier version is too large to keep, so there is no diff)" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        p.arguments = ["-u", old?.path ?? "/dev/null", new?.path ?? "/dev/null"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readData(ofLength: maxDiffBytes + 1)
        if data.count > maxDiffBytes { p.terminate() }
        p.waitUntilExit()
        var text = String(decoding: data.prefix(maxDiffBytes), as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 2, lines[0].hasPrefix("---"), lines[1].hasPrefix("+++") { text = lines.dropFirst(2).joined(separator: "\n") }
        // Invisible direction marks and control characters could hide what a line really says.
        text = String(text.unicodeScalars.map { sc -> Character in
            let v = sc.value
            let hidden = (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v) || v == 0x200B || v == 0x200E || v == 0x200F
            let control = v < 0x20 && sc != "\n" && sc != "\t"
            return hidden || control ? "\u{FFFD}" : Character(sc)
        })
        return data.count > maxDiffBytes ? text + "\n… (cut)" : text
    }

    // MARK: undo

    struct RevertResult: Equatable {
        var restored: [String] = []
        /// Files that were already back in their original state (an earlier, partial revert).
        var already: [String] = []
        /// Left alone: the owner changed them after the agent, or there is no copy.
        var skipped: [String] = []
        var complete: Bool { skipped.isEmpty }
    }

    /// Puts the files back. A file is skipped when the owner changed it after the agent did.
    @discardableResult
    static func revert(_ set: ChangeSet, in root: URL = root) -> RevertResult {
        var r = RevertResult()
        guard let m = manifest(set.snapshotID, in: root) else { r.skipped = set.files.map(\.path); return r }
        let fm = FileManager.default
        let copies = root.appendingPathComponent(set.snapshotID).appendingPathComponent("files")
        for c in set.files {
            guard isEditable(c.path), c.revertible else { r.skipped.append(c.path); continue }
            let target = URL(fileURLWithPath: m.workspace).appendingPathComponent(c.path)
            let current = (try? Data(contentsOf: target)).map(sha)
            let original = m.entries[c.path]?.hash
            // Already as it was before the run: a previous revert (or the owner) did the work.
            if current == original { r.already.append(c.path); continue }
            guard current == c.afterHash else { r.skipped.append(c.path); continue }  // changed again by the owner
            switch c.status {
            case .added:
                if (try? fm.removeItem(at: target)) != nil { r.restored.append(c.path) } else { r.skipped.append(c.path) }
            case .modified, .deleted:
                guard let data = try? Data(contentsOf: copies.appendingPathComponent(c.path)) else { r.skipped.append(c.path); continue }
                try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? data.write(to: target, options: .atomic)) != nil { r.restored.append(c.path) } else { r.skipped.append(c.path) }
            }
        }
        return r
    }

    /// Removes snapshots older than `days` (the undo window).
    static func prune(olderThanDays days: Int = 14, in root: URL = root) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for dir in items {
            guard let d = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let m = try? JSONDecoder().decode(Manifest.self, from: d) else { try? fm.removeItem(at: dir); continue }
            if -m.created.timeIntervalSinceNow > Double(days) * 86_400 { try? fm.removeItem(at: dir) }
        }
    }
}
