import AppKit
import SwiftUI

/// SYNC: `claude -p` has no computer use (that is a Claude desktop feature), so "Run sync" copies the prompt and
/// opens Claude; the sync itself runs there, in the Study Workspace folder. Progress is read from resources/sources.md
/// ("Last read" per chat) and the workspace's git log, refreshed every 5 s while the page is visible.
struct SyncView: View {
    @ObservedObject private var store = StudyStore.shared
    @State private var rows: [[String: String]] = []
    @State private var lastSync = SyncSnapshot()
    @State private var history: [SyncSnapshot.Entry] = []
    @State private var now = Date()
    @State private var scope = Scope.all
    @State private var copied = false
    // Not stored: a checklist from yesterday is not true today. Cleared 10 s after a run.
    @State private var checkQQ = false
    @State private var checkPhone = false

    enum Scope: String, CaseIterable {
        case all = "Everything", qq = "QQ", wechat = "WeChat"
        var prompt: String { self == .all ? "sync" : self == .qq ? "sync qq" : "sync wechat" }
    }

    var body: some View {
        PageView(title: "Sync", summary: summary) {
            runBlock
            sources
            changes
            historyBlock
        }
        .task(id: store.tick) { await refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await refresh()
            }
        }
    }

    private var summary: String {
        lastSync.when.map { "Last sync: \(SyncInfo.relative($0, now: now))" } ?? "No sync commit yet"
    }

    // MARK: run

    private var runBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { run() } label: {
                    Text("Run sync · \(scope.rawValue)").frame(maxWidth: .infinity).padding(.vertical, 4)
                }.buttonStyle(PrimaryButton())
                Menu {
                    Picker("Scope", selection: $scope) { ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.inline).labelsHidden()
                } label: { Label("Scope", systemImage: "slider.horizontal.3").font(.meta) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Choose what to sync")
            }
            if copied {
                Label("Prompt copied — paste it into Claude in the Study Workspace folder", systemImage: "checkmark.circle")
                    .font(.body13).foregroundStyle(Theme.good)
            }
            Section2(title: "Before you start") {
                Group2 {
                    RowButton { Toggle("QQ window is open", isOn: $checkQQ).toggleStyle(.checkbox).font(.body13) }
                    Hairline()
                    RowButton { Toggle("iPhone Mirroring is unlocked", isOn: $checkPhone).toggleStyle(.checkbox).font(.body13) }
                }
            }
        }
    }

    // MARK: sources

    private struct Line: Identifiable {
        let id: String
        let source: SyncInfo.Source?   // header row when set
        let row: [String: String]?
    }

    private var lines: [Line] {
        SyncInfo.Source.allCases.flatMap { src -> [Line] in
            let mine = rows.filter { SyncInfo.source(of: $0) == src }
            return [Line(id: "h\(src.rawValue)", source: src, row: nil)]
                + mine.enumerated().map { Line(id: "\(src.rawValue)-\($0.offset)", source: nil, row: $0.element) }
        }
    }

    private var sources: some View {
        Section2(title: "Sources") {
            Group2 {
                Rows(items: lines) { l in
                    if let src = l.source { header(src) } else if let r = l.row { chatRow(r) }
                }
            }
        }
    }

    private func header(_ src: SyncInfo.Source) -> some View {
        RowButton {
            Text(src.title).font(.rowTitle).foregroundStyle(Theme.text)
        }
    }

    private func chatRow(_ r: [String: String]) -> some View {
        let name = r.first { $0.key.hasPrefix("chat name") }?.value ?? "—"
        let course = r["course"] ?? ""
        let skipped = (r["notes"] ?? "").lowercased().hasPrefix("skip")
        let f = SyncInfo.freshness(SyncInfo.parseDate(r["last read"] ?? ""), now: now)
        return RowButton {
            HStack(spacing: 10) {
                Text(name).font(.body13).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
                if course != "any", !course.isEmpty { CourseTag(code: course) }
                Spacer(minLength: 8)
                if skipped { Chip(text: "skipped") }
                else { Chip(text: f.text, tone: f.fresh == .good ? .good : f.fresh == .warn ? .warn : .bad) }
            }.padding(.leading, 12)
        }
    }

    // MARK: last sync

    private var changes: some View {
        Section2(title: "Last sync changes", count: lastSync.files.isEmpty ? nil : lastSync.files.count) {
            if lastSync.files.isEmpty {
                Group2 { EmptyState(icon: "arrow.triangle.2.circlepath", title: "No sync commits yet",
                                    detail: "Files changed by the newest “sync …” commit will be listed here.") }
            } else {
                Group2 {
                    RowButton {
                        HStack {
                            Text(lastSync.subject).font(.rowTitle).foregroundStyle(Theme.text)
                            Spacer()
                            if let w = lastSync.when { Text(SyncInfo.relative(w, now: now)).font(.meta).foregroundStyle(Theme.muted) }
                        }
                    }
                    ForEach(Array(lastSync.files.enumerated()), id: \.offset) { _, f in
                        Hairline()
                        RowButton {
                            HStack(spacing: 8) {
                                Text(f.path).font(.meta).monospaced().foregroundStyle(Theme.muted)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text("+\(f.added)").font(.meta).monospacedDigit().foregroundStyle(Theme.good)
                                Text("−\(f.deleted)").font(.meta).monospacedDigit().foregroundStyle(Theme.bad)
                            }
                        }
                    }
                }
            }
        }
    }

    private var historyBlock: some View {
        Section2(title: "History") {
            Group2 {
                if history.isEmpty {
                    EmptyState(icon: "clock", title: "No git history", detail: "Commits in the Study Workspace folder will appear here.")
                } else {
                    Rows(items: history) { e in
                        RowButton {
                            HStack {
                                Text(e.subject).font(.body13).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(SyncInfo.relative(e.when, now: now)).font(.meta).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: actions

    private func run() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(scope.prompt, forType: .string)
        copied = true
        Task { try? await Task.sleep(nanoseconds: 10_000_000_000); copied = false; checkQQ = false; checkPhone = false }
        if let url = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: "/Applications/Claude.app")) ?? URL(string: "file:///Applications/Claude.app") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func refresh() async {
        let t = MarkdownTables.tables(MarkdownTables.read("\(Config.resources)/sources.md")).first
        rows = t?.rows ?? []
        let (snap, log) = await Task.detached { (SyncSnapshot.load(), SyncSnapshot.log()) }.value
        lastSync = snap
        history = log
        now = Date()
    }
}

struct SyncSnapshot {
    struct Entry: Identifiable { let id = UUID(); let when: Date; let subject: String }

    var subject = ""
    var when: Date?
    var files: [(path: String, added: Int, deleted: Int)] = []

    static func git(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", Config.workspace] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Newest commit whose message starts with "sync", via `git show --numstat`.
    static func load() -> SyncSnapshot {
        let hash = git(["log", "-1", "-E", "--grep=^sync", "--format=%H"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { return SyncSnapshot() }
        let out = git(["show", "--numstat", "--format=%s%n%ct", hash])
        let lines = out.components(separatedBy: "\n")
        let when = lines.count > 1 ? TimeInterval(lines[1]).map { Date(timeIntervalSince1970: $0) } : nil
        return SyncSnapshot(subject: lines.first ?? "", when: when, files: SyncInfo.parseNumstat(out))
    }

    static func log() -> [Entry] {
        git(["log", "-8", "--format=%ct\t%s"]).components(separatedBy: "\n").compactMap { l in
            let p = l.split(separator: "\t", maxSplits: 1).map(String.init)
            guard p.count == 2, let t = TimeInterval(p[0]) else { return nil }
            return Entry(when: Date(timeIntervalSince1970: t), subject: p[1])
        }
    }
}
