import Foundation

// Compiled with Sources/Core/*.swift by `./build.sh --test`.
// A small synthetic workspace: tests never depend on anyone's real files.
let res = NSTemporaryDirectory() + "ld-fixture-\(getpid())"
try? FileManager.default.createDirectory(atPath: "\(res)/cpp", withIntermediateDirectories: true)
try? """
# C++ — Assignments

| # | Title | Task | Due | Submission | Status | File |
|---|---|---|---|---|---|---|
| Lab 1 | Environment | Hello | after the 2026-09-09 session | PDF | done | — |
| Lab 2 | Bank | Functions | 2026-10-20 | PDF | todo | — |
| HW1 | Homework | via QR | as announced | QR | todo | — |

""".write(toFile: "\(res)/cpp/assignments.md", atomically: true, encoding: .utf8)
try? """
# Exams

| Course | Type | Topic/Chapters | Date | Notes |
|---|---|---|---|---|
| cpp | Final | Whole course | 2026-12-20 | Handwritten code |
| cpp | Quiz 1 | Ch 1 | Tentative, week 9: 2026-10-26 – 2026-11-01 | open-book |

""".write(toFile: "\(res)/exam-dates.md", atomically: true, encoding: .utf8)
defer { try? FileManager.default.removeItem(atPath: res) }
let fails = MarkdownTables.selfTest(resources: res)
var fails2 = AssignmentsFile.selfTest() + Deadlines.selfTest() + QuickEntry.selfTest() + Reminders.selfTest() + ExamCountdown.selfTest() + ICS.selfTest() + SearchIndex.selfTest() + Inbox.selfTest() + ExamPrep.selfTest() + FilePreview.selfTest() + FocusStats.selfTest() + Devices.selfTest() + StudyDocsStore.selfTest() + SleepLogic.selfTest() + FoodLogic.selfTest() + FinanceLogic.selfTest() + HabitLogic.selfTest() + AppRoute.selfTest()
// file edit on a temp copy of a real assignments.md
if let first = MarkdownTables.courseFolders(resources: res).first(where: { MarkdownTables.tables(MarkdownTables.read("\(res)/\($0)/assignments.md")).first != nil }) {
    let tmp = NSTemporaryDirectory() + "ld-test-\(getpid())"
    try? FileManager.default.createDirectory(atPath: "\(tmp)/\(first)", withIntermediateDirectories: true)
    try? FileManager.default.copyItem(atPath: "\(res)/\(first)/assignments.md", toPath: "\(tmp)/\(first)/assignments.md")
    if let it = MarkdownTables.assignments(resources: tmp).first(where: { !$0.done }) {
        let ok = AssignmentsFile.markDone(course: first, num: it.num, resources: tmp)
        let now = MarkdownTables.assignments(resources: tmp).first { $0.num == it.num }
        if ok { if now?.done != true { fails2.append("temp copy not marked done") } } // nil match (duplicate num) is fine
    }
    try? FileManager.default.removeItem(atPath: tmp)
} else { fails2.append("fixture workspace has no assignments table") }
fails2.forEach { print("FAIL: \($0)") }
if !fails2.isEmpty { exit(1) }
print("assignments: \(MarkdownTables.assignments(resources: res).count), exams: \(MarkdownTables.exams(resources: res).count)")
if fails.isEmpty {
    print("MarkdownTables.selfTest OK")
} else {
    fails.forEach { print("FAIL: \($0)") }
    exit(1)
}

// Chat / SYNC pure parts
expect(ChatBlock.split("hi\n```swift\nlet a = 1\n```\nbye") ==
       [.markdown("hi"), .code(lang: "swift", body: "let a = 1"), .markdown("bye")], "block split")
expect(ChatBlock.split("x\n```\nopen") == [.markdown("x"), .code(lang: "", body: "open")], "unclosed fence")
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ld-chat-\(UUID()).json")
let st = ChatState(messages: [ChatMessage(fromUser: true, text: "a"), ChatMessage(fromUser: false, text: "b")], sessionID: "s1", started: true)
ChatStore.save(st, to: tmp)
expect(ChatStore.load(from: tmp) == st, "chat round trip")
ChatStore.delete(at: tmp)
let now = SyncInfo.parseDate("2026-10-09T16:22+08:00")!
expect(SyncInfo.ago(now, now: now).text == "read today", "ago today")
expect(SyncInfo.ago(now.addingTimeInterval(-2.5 * 86400), now: now) == ("read 2 d ago", .ok), "ago 2")
expect(SyncInfo.ago(now.addingTimeInterval(-4 * 86400), now: now).level == .warn, "ago warn")
expect(SyncInfo.ago(nil).level == .never, "ago never")
let rows = [["app": "QQ", "last read": "2026-10-09T16:22+08:00", "notes": ""],
            ["app": "WeChat", "last read": "", "notes": ""]]
expect(SyncInfo.lastRead(rows: rows, app: "qq") == now, "lastRead qq")
expect(SyncInfo.lastRead(rows: rows, app: "wechat") == nil, "lastRead wechat never")
expect(SyncInfo.parseStat(" a/b.md | 12 +++--\n 2 files changed\n c.py |  3 +-\n").map { $0.path } == ["a/b.md", "c.py"], "stat")
// Chat library
expect(ChatTitle.make(from: "  what   is due\nthis week?  ") == "what is due", "title: first line, spaces collapsed")
expect(ChatTitle.make(from: "") == "New chat", "title: empty")
expect(ChatTitle.make(from: String(repeating: "a", count: 80)).count == 43, "title: cut with ellipsis")
let legacyJSON = #"{"messages":[{"id":"6F1B1A8E-1D5E-4C1B-9E5B-1C1D4F1A0001","fromUser":true,"text":"hello there"}],"sessionID":"abc","started":true}"#
let legacy = try! JSONDecoder().decode(ChatState.self, from: Data(legacyJSON.utf8))
expect(legacy.sessionID == "abc" && legacy.started && legacy.title.isEmpty && legacy.messages.count == 1, "legacy chat.json decodes")
let libTmp = URL(fileURLWithPath: NSTemporaryDirectory() + "ld-lib-\(getpid()).json")
let legTmp = URL(fileURLWithPath: NSTemporaryDirectory() + "ld-leg-\(getpid()).json")
ChatStore.save(legacy, to: legTmp)
let migrated = ChatLibraryStore.load(from: libTmp, legacy: legTmp)
expect(migrated.chats.count == 1 && migrated.chats[0].title == "hello there" && migrated.currentID == migrated.chats[0].id, "legacy chat imported")
var lib2 = migrated
let second = ChatState(messages: [ChatMessage(fromUser: true, text: "q")], sessionID: "s2", started: false)
lib2.chats.append(second); lib2.currentID = second.id
try! ChatLibraryStore.save(lib2, to: libTmp)
expect(ChatLibraryStore.load(from: libTmp, legacy: legTmp) == lib2, "library round trip")
try? FileManager.default.removeItem(at: libTmp); try? FileManager.default.removeItem(at: legTmp)
print("Chat/Sync tests OK")

// Courses / Notices pure logic
expect(CourseInfo.teacher(info: "- **Instructor:** Prof. Jane Doe (Dr.), jane@example.edu, office A101.\n") == "Prof. Jane Doe (Dr.)", "teacher cpp")
expect(CourseInfo.teacher(info: "- **Teacher:** JOHN SMITH (as written on the slides).\n") == "JOHN SMITH", "teacher as-written")
expect(CourseInfo.teacher(info: "| Key | Value | Source |\n|---|---|---|\n| teacher | Ms Lee (group owner) | QQ |\n") == "Ms Lee (group owner)", "teacher facts")
expect(CourseInfo.teacher(info: "nothing") == nil, "teacher none")
CourseInfo.builtInPolicies = ["stats101": ("x", .bad), "cpp": ("y", .warn)]
expect(CourseInfo.policy("stats101")?.tone == .bad && CourseInfo.policy("cpp")?.tone == .warn && CourseInfo.policy("lang1") == nil, "policy")
CourseInfo.builtInPolicies = [:]
expect(CourseInfo.summaries(filesMd: "| File | From | Summary |\n|---|---|---|\n| `slides/a.pdf` | x | **Hi** |\n")["slides/a.pdf"] == "Hi", "summaries")
expect(CourseInfo.group(rel: "slides/a.pdf") == "slides" && CourseInfo.group(rel: "a.pdf") == "Other", "group")
expect(CourseInfo.dueLabel(date: "2026-10-08", today: "2026-10-10").text == "2 d overdue", "due overdue")
expect(CourseInfo.dueLabel(date: "2026-10-10", today: "2026-10-10").text == "today", "due today")
expect(CourseInfo.dueLabel(date: nil, today: "2026-10-10").text == "no date", "due none")
expect(NoticeLogic.dayTitle("2026-10-10", today: "2026-10-10") == "Today" && NoticeLogic.dayTitle("2026-10-09", today: "2026-10-10") == "Yesterday", "day titles")
expect(NoticeLogic.dayTitle("2026-10-07", today: "2026-10-10") == "Wednesday, 7 October", "day title date")
print("Courses/Notices tests OK")

let t0 = SyncInfo.parseDate("2026-10-09T16:22+08:00")!
expect(SyncInfo.freshness(t0.addingTimeInterval(-86400), now: t0).fresh == .good, "fresh 1d good")
expect(SyncInfo.freshness(t0.addingTimeInterval(-3 * 86400), now: t0) == ("read 3 d ago", .warn), "fresh 3d warn")
expect(SyncInfo.freshness(t0.addingTimeInterval(-4 * 86400), now: t0).fresh == .bad, "fresh 4d bad")
expect(SyncInfo.freshness(nil).fresh == .bad, "fresh never")
expect(SyncInfo.relative(t0.addingTimeInterval(-7200), now: t0) == "2 h ago", "relative h")
expect(SyncInfo.relative(t0.addingTimeInterval(-300), now: t0) == "5 min ago", "relative min")
expect(SyncInfo.source(of: ["app": "QQ"]) == .qq && SyncInfo.source(of: ["app": "WeChat", "chat name (exact)": "File Transfer (pinned)"]) == .fileTransfer
       && SyncInfo.source(of: ["app": "WeChat", "chat name (exact)": "Course group 2"]) == .wechat, "source grouping")
let ns = SyncInfo.parseNumstat("sync qq\n1760000000\n\n12\t3\ta/b.md\n-\t-\timg.png\n")
expect(ns.count == 2 && ns[0].added == 12 && ns[0].deleted == 3 && ns[1].path == "img.png", "numstat")
print("Sync freshness tests OK")

expect(FocusLogic.selfTest().isEmpty, "focus logic: \(FocusLogic.selfTest())")
print("Focus tests OK")
expect(FocusStyle.selfTest().isEmpty, "focus style: \(FocusStyle.selfTest())")
focusTests()
runnerTests()
chatStoreTests()
policyTests()
snapshotTests()
secureFSTests()
keychainTests()
bridgeTests()
botTests()
configTests()
paletteTests()
dateTests()
aiPolicyTests()
do {
    let now = Date()
    let iso = ISO8601DateFormatter()
    let fresh = iso.string(from: now.addingTimeInterval(-3600))
    let old = iso.string(from: now.addingTimeInterval(-30 * 3600))
    let rows: [[String: String]] = [["last read": fresh], ["last read": old], ["last read": ""], ["last read": old, "notes": "skip: group closed"]]
    expect(SyncInfo.staleRows(rows, now: now) == 2, "sync stale: old and never counted, fresh and skipped not")
}
