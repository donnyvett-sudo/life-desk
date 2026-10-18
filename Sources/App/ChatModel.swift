import SwiftUI

@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var chats: [ChatState]
    @Published private(set) var currentID: UUID
    @Published private(set) var runningIDs: Set<UUID> = []
    /// Something worth telling the user: a backup was made, a save failed, history is read-only.
    @Published var notice: String?
    private var runners: [UUID: ClaudeRunner] = [:]
    /// Chats whose answer is waiting for the safety copy of the files (the process has not started yet).
    private var preparing: Set<UUID> = []
    /// Reverts in progress (a double click must not run twice).
    private var reverting: Set<UUID> = []
    private var readOnly = false
    /// Course whose AI rule applies to a chat once it was named (not stored: a restart asks again by name).
    private var policyCourse: [UUID: String] = [:]
    private var pendingSave: DispatchWorkItem?

    static let shared = ChatModel()

    private init() {
        let loaded = ChatLibraryStore.read()
        var lib = loaded.library
        readOnly = loaded.readOnly
        notice = loaded.warnings.first
        if lib.chats.isEmpty { let c = ChatState(); lib.chats = [c]; lib.currentID = c.id }
        if lib.currentID == nil || !lib.chats.contains(where: { $0.id == lib.currentID }) { lib.currentID = lib.chats[0].id }
        chats = lib.chats
        currentID = lib.currentID!
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runners.values.forEach { $0.killNow() }
                self?.save()  // the answer that was still streaming is kept
            }
        }
        save()  // writes chats.json right away, so a legacy chat.json is imported only once
        DispatchQueue.global(qos: .utility).async { WorkspaceSnapshot.prune() }
    }

    // MARK: reading

    var messages: [ChatMessage] { chats.first(where: { $0.id == currentID })?.messages ?? [] }
    var running: Bool { runningIDs.contains(currentID) }
    /// Most recently used first.
    var sorted: [ChatState] { chats.sorted { $0.updated > $1.updated } }

    private func index(_ id: UUID) -> Int? { chats.firstIndex(where: { $0.id == id }) }

    private func runner(for id: UUID) -> ClaudeRunner {
        if let r = runners[id] { return r }
        let c = chats[index(id)!]
        let r = ClaudeRunner(sessionID: c.sessionID, started: c.started, readOnly: c.title == "iPhone")
        runners[id] = r
        return r
    }

    /// Writes the library now. A read-only library (damaged file that could not be set aside) is never written.
    private func save() {
        pendingSave?.cancel(); pendingSave = nil
        guard !readOnly else { return }
        // Empty chats are not worth keeping, except the one that is open.
        let keep = chats.filter { !$0.messages.isEmpty || $0.id == currentID }
        do { try ChatLibraryStore.save(ChatLibrary(chats: keep, currentID: currentID)) }
        catch { notice = "Couldn't save chats: \(error.localizedDescription)" }
    }

    /// For streamed text: at most one write per second instead of one per token.
    private func scheduleSave() {
        guard pendingSave == nil else { return }
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.pendingSave = nil; self?.save() }
        }
        pendingSave = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
    }

    // MARK: actions

    /// `course` only prefixes the prompt sent to claude; the bubble shows what was typed.
    func send(_ text: String, course: String?, in chat: UUID? = nil) {
        let id = chat ?? currentID
        guard !runningIDs.contains(id), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let i = index(id) else { return }
        // One answer at a time: two agents writing the same files would blur whose change is whose.
        guard runningIDs.isEmpty else {
            notice = "Another answer is still being written. Wait for it, or stop it, then ask again."
            return
        }
        if readOnly { notice = "History is read-only: this conversation will not be saved." }
        chats[i].messages.append(ChatMessage(fromUser: true, text: text))
        chats[i].messages.append(ChatMessage(fromUser: false, text: ""))
        if chats[i].title.isEmpty { chats[i].title = ChatTitle.make(from: text) }
        chats[i].updated = Date()
        runningIDs.insert(id)
        preparing.insert(id)
        let answerID = chats[i].messages[chats[i].messages.count - 1].id
        let r = runner(for: id)
        // The session exists from the first init event on; remember it at once, not only when the answer ends.
        r.onStarted = { [weak self] in
            guard let self, let i = self.index(id) else { return }
            self.chats[i].started = true
            self.save()
        }
        r.onText = { [weak self] t in
            guard let self, let i = self.index(id), !self.chats[i].messages.isEmpty else { return }
            self.chats[i].messages[self.chats[i].messages.count - 1].text += t
            self.scheduleSave()
        }
        // A course that bans AI (or demands own work) gets its rule in front of the question, whichever way it was named.
        let named = course ?? AIPolicy.course(in: text, among: MarkdownTables.courseFolders(resources: Config.resources), label: Theme.short)
        // Later messages of the same chat keep the rule of the course named earlier.
        let effective = named ?? policyCourse[id]
        if let named { policyCourse[id] = named }
        let policy = effective.map { c in
            AIPolicy.prefix(course: c, tone: AIPolicy.level(course: c, info: try? String(contentsOfFile: "\(Config.resources)/\(c)/course-info.md", encoding: .utf8)))
        } ?? ""
        let prompt = policy + (course.map { "Course: \($0). " } ?? "") + text
        // Copies of the editable files are taken first (off the main thread); the run starts once they exist.
        DispatchQueue.global().async { [weak self] in
            let snapshotID = WorkspaceSnapshot.take(workspace: Config.workspace)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Stop was pressed while the copies were being made: nothing starts.
                    guard self.preparing.remove(id) != nil, self.runningIDs.contains(id) else {
                        if let s = snapshotID { WorkspaceSnapshot.discard(s) }
                        return
                    }
                    // No safety copy, no agent: it may change files and every change must be undoable.
                    guard let sid = snapshotID else {
                        self.runningIDs.remove(id)
                        self.notice = "Couldn't make a safety copy of your files, so the agent was not started."
                        return
                    }
                    self.start(r, prompt: prompt, chat: id, snapshotID: sid, answer: answerID)
                }
            }
        }
    }

    private func start(_ r: ClaudeRunner, prompt: String, chat id: UUID, snapshotID: String, answer: UUID) {
        r.onFinish = { [weak self] _ in
            guard let self else { return }
            self.runningIDs.remove(id)
            if !r.lastErrorDetail.isEmpty { self.notice = "claude failed: \(r.lastErrorDetail)" }
            if let i = self.index(id) { self.chats[i].started = r.started }
            self.save()
            self.attachChanges(chat: id, snapshotID: snapshotID, answer: answer)
        }
        r.run(prompt: prompt)
        if let i = index(id) { chats[i].started = r.started }
        save()
    }

    // MARK: what the agent changed

    /// Compares the files with the snapshot taken before the run and hangs the result on the answer.
    private func attachChanges(chat id: UUID, snapshotID sid: String, answer: UUID) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let set = WorkspaceSnapshot.changes(since: sid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // Nothing changed (the usual case): the copies are not kept.
                    guard let self, let set, !set.files.isEmpty || !set.outside.isEmpty else {
                        WorkspaceSnapshot.discard(sid)
                        return
                    }
                    guard let i = self.index(id), let m = self.chats[i].messages.firstIndex(where: { $0.id == answer }) else {
                        WorkspaceSnapshot.discard(sid)  // the chat was deleted meanwhile
                        return
                    }
                    self.chats[i].messages[m].changes = set
                    self.save()
                }
            }
        }
    }

    private func updateChanges(chat id: UUID, message mid: UUID, _ f: (inout ChangeSet) -> Void) {
        guard let i = index(id), let m = chats[i].messages.firstIndex(where: { $0.id == mid }),
              var c = chats[i].messages[m].changes else { return }
        f(&c)
        chats[i].messages[m].changes = c
        save()
    }

    func keepChanges(chat id: UUID, message mid: UUID) {
        updateChanges(chat: id, message: mid) { $0.state = .kept }
    }

    func revertChanges(chat id: UUID, message mid: UUID) {
        guard let i = index(id), let c = chats[i].messages.first(where: { $0.id == mid })?.changes, c.state == .pending,
              reverting.insert(mid).inserted else { return }
        DispatchQueue.global().async { [weak self] in
            let res = WorkspaceSnapshot.revert(c)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reverting.remove(mid)
                    self.updateChanges(chat: id, message: mid) { $0.state = res.complete ? .reverted : .pending }
                    let done = res.restored.count + res.already.count
                    self.notice = res.complete
                        ? "Restored \(done) file(s)."
                        : "Restored \(done); left alone because they changed again or have no copy: \(res.skipped.joined(separator: ", "))."
                }
            }
        }
    }

    func stop() {
        let id = currentID
        // Still making the safety copies: there is no process yet, so just cancel the start.
        if preparing.remove(id) != nil {
            runningIDs.remove(id)
            if let i = index(id), let last = chats[i].messages.indices.last, chats[i].messages[last].text.isEmpty {
                chats[i].messages[last].text = "[stopped]"
            }
            save()
            return
        }
        runners[id]?.stop()
    }

    /// The chat that holds questions from the iPhone (created on first use, never selected: the open chat stays open).
    func relayChat() -> UUID {
        if let c = chats.first(where: { $0.title == "iPhone" }) { return c.id }
        var c = ChatState(); c.title = "iPhone"
        chats.append(c)
        save()
        return c.id
    }

    /// Text of the last answer in a chat and whether it ended normally.
    func lastAnswer(_ id: UUID) -> String? {
        guard let i = index(id), let m = chats[i].messages.last, !m.fromUser else { return nil }
        return m.text
    }

    /// Opens an empty chat; if the open one is already empty it is simply reused.
    func newChat() {
        if let c = chats.first(where: { $0.id == currentID }), c.messages.isEmpty { return }
        let c = ChatState()
        chats.append(c)
        currentID = c.id
        save()
    }

    func select(_ id: UUID) {
        guard chats.contains(where: { $0.id == id }) else { return }
        currentID = id
        save()
    }

    func rename(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = index(id) else { return }
        chats[i].title = t
        save()
    }

    func delete(_ id: UUID) {
        if let r = runners[id] { r.onText = { _ in }; r.onFinish = { _ in }; r.stop() }
        runners[id] = nil
        runningIDs.remove(id)
        chats.removeAll { $0.id == id }
        if chats.isEmpty { chats = [ChatState()] }
        if currentID == id || !chats.contains(where: { $0.id == currentID }) {
            currentID = sorted.first?.id ?? chats[0].id
        }
        save()
    }
}
