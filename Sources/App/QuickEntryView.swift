import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Global hotkey (⌃⌥⌘D; every Space combination is taken by Spotlight, Finder search or the input-source switch): brings Life Desk forward with the quick-entry box open. Carbon hot keys need no permission.
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onFire: () -> Void = {}

    private(set) var registered = false

    func register() {
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotKey.shared.onFire() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x4C444B31), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &ref)
        registered = status == noErr
    }
}

/// Adds the row and tells the bot (tools/life_sync.py in the workspace).
enum QuickEntryRunner {
    /// nil = ok, otherwise the message. Runs life_sync in the background; the row is already saved by then.
    @MainActor static func add(_ p: QuickEntry.Parsed) async -> String {
        guard AssignmentsFile.add(course: p.course, num: p.num, title: p.title, due: p.date) else {
            return "Could not add: no assignments table in \(p.course), or \(p.num) already exists"
        }
        let ws = Config.workspace
        let ok: Bool = await Task.detached {
            // Only a real workspace's own script; -I keeps files next to it (a planted json.py) off the import path.
            let script = ((ws as NSString).appendingPathComponent("tools/life_sync.py") as NSString).resolvingSymlinksInPath
            guard Config.looksLikeWorkspace(ws), script.hasPrefix((ws as NSString).resolvingSymlinksInPath + "/"),
                  FileManager.default.fileExists(atPath: script) else { return false }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = ["-I", script]
            proc.currentDirectoryURL = URL(fileURLWithPath: ws)
            proc.standardOutput = FileHandle.nullDevice; proc.standardError = FileHandle.nullDevice
            do { try proc.run() } catch { return false }
            // 60 s at most: a hung sync must not leave the box busy for ever.
            let killer = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: killer)
            proc.waitUntilExit()
            killer.cancel()
            return proc.terminationStatus == 0
        }.value
        StudyStore.shared.tick += 1
        let what = "\(p.num) · \(Theme.short(p.course))" + (p.date.map { " · \($0)" } ?? " · no date")
        return ok ? "Added \(what)" : "Added \(what) to the file; bot sync failed (run life_sync)"
    }
}

struct QuickEntryView: View {
    @ObservedObject private var router = Router.shared
    @State private var text = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    private var courses: [String] { MarkdownTables.courseFolders(resources: Config.resources) }
    private var parsed: Result<QuickEntry.Parsed, QuickEntry.Failure> {
        QuickEntry.parse(text, courses: courses, label: Theme.short, today: DateFmt.today())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("cpp lab 3 fri", text: $text)
                .textFieldStyle(.plain).font(.system(size: 16)).padding(14)
                .focused($focused)
                .onSubmit { submit() }
                .onKeyPress(.escape) { router.quickEntryVisible = false; return .handled }
            Hairline()
            Group {
                switch parsed {
                case .success(let p):
                    Text("\(Theme.short(p.course)) · \(p.num) · \(p.title) · \(p.date ?? "no date")  —  Enter to add")
                        .foregroundStyle(Theme.text)
                case .failure(.noCourse):
                    Text("Start with a course: \(courses.map(Theme.short).joined(separator: ", "))").foregroundStyle(Theme.muted)
                case .failure(.empty):
                    Text("Course, what, when: cpp lab 3 fri · stats101 hw4 2026-11-02 · lang1 quiz tomorrow").foregroundStyle(Theme.muted)
                }
            }.font(.meta).padding(14)
        }
        .frame(width: 560)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear { text = ""; DispatchQueue.main.async { focused = true } }
    }

    private func submit() {
        guard !busy, case .success(let p) = parsed else { return }
        busy = true
        router.quickEntryVisible = false
        Task { @MainActor in
            ToastCenter.shared.show(await QuickEntryRunner.add(p))
            busy = false
        }
    }
}
