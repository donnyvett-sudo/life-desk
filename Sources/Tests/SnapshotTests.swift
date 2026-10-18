import Foundation

func snapshotTests() {
    let fm = FileManager.default
    let base = NSTemporaryDirectory() + "ld-snap-\(getpid())"
    let ws = base + "/ws", store = URL(fileURLWithPath: base + "/store")
    defer { try? fm.removeItem(atPath: base) }
    func w(_ rel: String, _ s: String) {
        let p = "\(ws)/\(rel)"
        try? fm.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? s.write(toFile: p, atomically: true, encoding: .utf8)
    }
    func r(_ rel: String) -> String? { try? String(contentsOfFile: "\(ws)/\(rel)", encoding: .utf8) }

    expect(WorkspaceSnapshot.isEditable("resources/c1/assignments.md"), "snapshot: assignments editable")
    expect(WorkspaceSnapshot.isEditable("resources/exam-dates.md") && WorkspaceSnapshot.isEditable("output/c1/notes.md"), "snapshot: exam dates and output editable")
    expect(WorkspaceSnapshot.isEditable("resources/c1/2026/files.md"), "snapshot: files.md editable")
    for bad in ["CLAUDE.md", "tools/pdf.py", "resources/c1/archive-2025/a.md", "resources/sources.md", "resources/../CLAUDE.md", "resources/c1/x.md", "workflows/a.md"] {
        expect(!WorkspaceSnapshot.isEditable(bad), "snapshot: not editable: \(bad)")
    }

    // a symlinked folder that sorts BEFORE the files next to it must not make them vanish from the snapshot
    let linkTarget = base + "/senior"
    try? fm.createDirectory(atPath: linkTarget, withIntermediateDirectories: true)
    try? "x".write(toFile: linkTarget + "/old.md", atomically: true, encoding: .utf8)
    try? fm.createDirectory(atPath: ws + "/resources/c1", withIntermediateDirectories: true)
    try? fm.createSymbolicLink(atPath: ws + "/resources/c1/a-archive-2025", withDestinationPath: linkTarget)
    w("CLAUDE.md", "rules")
    w("tools/x.py", "print(1)")
    w("resources/c1/assignments.md", "| 1 | HW1 | todo |\n")
    w("resources/c1/course-info.md", "info\n")
    w("resources/exam-dates.md", "exams\n")
    // a dirty file of the owner's, also inside the editable list: must come back exactly as it was
    w("output/draft.md", "my own unsaved thoughts\n")

    expect(fm.fileExists(atPath: ws + "/resources/c1/a-archive-2025/old.md"), "test setup: the link works")
    guard let id = WorkspaceSnapshot.take(workspace: ws, in: store) else { expect(false, "snapshot: take failed"); return }
    expect(WorkspaceSnapshot.changes(since: id, in: store)?.files.isEmpty == true, "snapshot: no change right after taking")

    // the agent: edits one, adds one, deletes one, touches a forbidden one
    w("resources/c1/assignments.md", "| 1 | HW1 | done |\n")
    w("output/new.md", "new file\n")
    try? fm.removeItem(atPath: "\(ws)/resources/exam-dates.md")
    w("CLAUDE.md", "rules\nHACKED")

    guard let set = WorkspaceSnapshot.changes(since: id, in: store) else { expect(false, "snapshot: changes failed"); return }
    let by = Dictionary(uniqueKeysWithValues: set.files.map { ($0.path, $0) })
    expect(set.files.count == 3, "snapshot: three changed files (got \(set.files.map(\.path)))")
    expect(by["resources/c1/assignments.md"]?.status == .modified && by["resources/c1/assignments.md"]?.diff.contains("+| 1 | HW1 | done |") == true,
           "snapshot: modified file with a diff")
    expect(by["output/new.md"]?.status == .added && by["resources/exam-dates.md"]?.status == .deleted, "snapshot: added and deleted")
    expect(set.outside == ["CLAUDE.md"], "snapshot: change outside the list is reported (got \(set.outside))")

    // the owner edits one of the files again after the agent: that one must be left alone
    w("output/new.md", "new file\nowner added a line\n")
    let res = WorkspaceSnapshot.revert(set, in: store)
    expect(r("resources/c1/assignments.md") == "| 1 | HW1 | todo |\n", "revert: modified file restored byte for byte")
    expect(r("resources/exam-dates.md") == "exams\n", "revert: deleted file restored")
    expect(r("output/new.md") == "new file\nowner added a line\n" && res.skipped == ["output/new.md"], "revert: owner's later edit is not destroyed")
    expect(r("output/draft.md") == "my own unsaved thoughts\n", "revert: untouched file stays")

    // a second revert of the same set is recognised as done, not "changed again"
    let again = WorkspaceSnapshot.revert(set, in: store)
    expect(again.already.sorted() == ["resources/c1/assignments.md", "resources/exam-dates.md"] && again.skipped == ["output/new.md"],
           "revert twice: finished files are recognised (got \(again))")
    expect(!again.complete, "revert twice: the owner's file keeps it incomplete")

    // hidden files under output/ count; a hidden folder elsewhere is not an agent path
    guard let id2 = WorkspaceSnapshot.take(workspace: ws, in: store) else { expect(false, "snapshot 2"); return }
    w("output/.hidden/note.md", "secret note\n")
    let set2 = WorkspaceSnapshot.changes(since: id2, in: store)
    expect(set2?.files.map(\.path) == ["output/.hidden/note.md"], "hidden file under output is seen (got \(String(describing: set2?.files.map(\.path))))")
    // nothing changed means the copies are not kept
    guard let id3 = WorkspaceSnapshot.take(workspace: ws, in: store) else { expect(false, "snapshot 3"); return }
    WorkspaceSnapshot.discard(id3, in: store)
    expect(WorkspaceSnapshot.changes(since: id3, in: store) == nil, "discard removes the snapshot")

    // the store folder is private and excluded from backups
    let attrs = try? fm.attributesOfItem(atPath: store.path)
    expect((attrs?[.posixPermissions] as? NSNumber)?.intValue == 0o700, "snapshot folder is 0700")

    // a long diff is cut to the budget
    guard let id4 = WorkspaceSnapshot.take(workspace: ws, in: store) else { expect(false, "snapshot 4"); return }
    for n in 0..<8 { w("output/big\(n).md", String(repeating: "line of text that is long enough\n", count: 600)) }
    let set4 = WorkspaceSnapshot.changes(since: id4, in: store)
    let total = set4?.files.reduce(0) { $0 + $1.diff.utf8.count } ?? 0
    expect(set4?.truncated == true && total <= WorkspaceSnapshot.maxStoredDiffBytes + 400, "diff budget is kept (total \(total))")

    // a ChangeSet written by a newer version with an unknown state still reads
    let json = #"{"snapshotID":"x","files":[],"state":"archived","future":1}"#
    let lenient = try? JSONDecoder().decode(ChangeSet.self, from: Data(json.utf8))
    expect(lenient?.snapshotID == "x" && lenient?.state == .pending, "ChangeSet: unknown state does not break reading")

    WorkspaceSnapshot.prune(olderThanDays: 0, in: store)
    expect(WorkspaceSnapshot.changes(since: id, in: store) == nil, "snapshot: pruned")
    _ = id2
    print("Snapshot tests OK")
}
