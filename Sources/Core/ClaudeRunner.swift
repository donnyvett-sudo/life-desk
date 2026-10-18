import Foundation
import CFNetwork

/// Finds the `claude` binary: the usual install folders first, then PATH; only files that are safe to run.
enum ClaudeBinary {
    static func find() -> String? {
        let fixed = ["\(Config.home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/claude" }
        return (fixed + path).first { FileManager.default.isExecutableFile(atPath: $0) && BinaryCheck.trusted(path: $0) }
    }
}

/// Proxy settings of macOS (System Settings > Network > Proxies) as environment variables.
/// A GUI app does not inherit the shell's HTTPS_PROXY, and the claude CLI ignores the system proxy on its own:
/// without this it connects directly and is refused ("403 Request not allowed") where a proxy is required.
enum SystemProxy {
    /// Pure: takes the dictionary CFNetwork returns, so it can be tested.
    static func environment(from s: [String: Any]?) -> [String: String] {
        guard let s else { return [:] }
        func on(_ k: String) -> Bool { (s[k] as? NSNumber)?.intValue == 1 }
        func url(_ hostKey: String, _ portKey: String) -> String? {
            guard let h = s[hostKey] as? String, !h.isEmpty, let p = (s[portKey] as? NSNumber)?.intValue else { return nil }
            return "http://\(h):\(p)"
        }
        var out: [String: String] = [:]
        if on("HTTPSEnable"), let u = url("HTTPSProxy", "HTTPSPort") { out["HTTPS_PROXY"] = u }
        if on("HTTPEnable"), let u = url("HTTPProxy", "HTTPPort") {
            out["HTTP_PROXY"] = u
            if out["HTTPS_PROXY"] == nil { out["HTTPS_PROXY"] = u }
        }
        if !out.isEmpty {
            let skip = (s["ExceptionsList"] as? [String] ?? []).filter { !$0.contains("<") && !$0.hasPrefix("*.") || $0.hasPrefix("*.") }
                .map { $0.hasPrefix("*.") ? String($0.dropFirst(1)) : $0 }
            out["NO_PROXY"] = (["localhost", "127.0.0.1", "::1"] + skip).joined(separator: ",")
        }
        return out
    }

    static func current() -> [String: String] {
        environment(from: CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any])
    }
}

/// One decoded piece of claude's `--output-format stream-json` output.
enum StreamEvent: Equatable {
    case sessionInit(String)
    case text(String)
    case result(String)
}

/// Parses claude's stream line by line (no process involved, so it is unit-tested).
/// Text of separate content blocks and messages is kept apart with a blank line.
struct StreamParser {
    private(set) var streamedText = false
    private var needSeparator = false
    private var lastChar: Character?

    mutating func feed(line: Data) -> [StreamEvent] {
        guard let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return [] }
        switch j["type"] as? String {
        case "system":
            if j["subtype"] as? String == "init", let id = j["session_id"] as? String { return [.sessionInit(id)] }
        case "stream_event":
            guard let e = j["event"] as? [String: Any] else { return [] }
            switch e["type"] as? String {
            case "message_start":
                if streamedText { needSeparator = true }
            case "content_block_start":
                if streamedText, (e["content_block"] as? [String: Any])?["type"] as? String == "text" { needSeparator = true }
            default:
                if let d = e["delta"] as? [String: Any], d["type"] as? String == "text_delta",
                   let t = d["text"] as? String, !t.isEmpty {
                    var out = t
                    if needSeparator {
                        needSeparator = false
                        out = (lastChar == "\n" ? "\n" : "\n\n") + t
                    }
                    streamedText = true
                    lastChar = out.last
                    return [.text(out)]
                }
            }
        case "result":
            if let r = j["result"] as? String { return [.result(r)] }
        default: break
        }
        return []
    }
}

/// `claude -p` in the Study Workspace folder (so its CLAUDE.md applies). Text streams to `onText`, both callbacks on the main thread.
/// A new object starts a fresh session (`--session-id`); once the session exists, later runs add `--resume`.
/// The child gets its own process group, so stop() kills claude and everything it spawned.
final class ClaudeRunner {
    /// How the chat wants answers shaped. Sent on every run, so it also applies to resumed sessions.
    static let styleGuide = """
    You are answering inside the Life Desk chat window, which renders Markdown.
    Reply in the language of the user's latest message.
    Lead with the answer; no preamble, no restating the question, no closing offers.
    Structure: short sections with "## " headings (never a bold line as a heading), a Markdown table for schedules and deadlines \
    (columns like When | What | Course), otherwise one-line bullets. Keep it scannable, not an essay.
    Use human course names and dates like "Thu 15 Oct, 16:00". Never show raw folder codes such as mech-eng-intro \
    and never give class periods without the clock time.
    """

    var onText: (String) -> Void = { _ in }
    /// Called (main thread) as soon as claude confirms the session exists, before the run ends.
    var onStarted: () -> Void = {}
    /// Exit code: 0 ok, -1 could not start, -2 stopped by the time limit, -9 abandoned after a kill, -N killed by signal N.
    var onFinish: (Int32) -> Void = { _ in }
    /// True once claude has confirmed the session exists (init event or a clean exit).
    private(set) var started: Bool
    /// Tail of stderr of the last failed run; not persisted.
    private(set) var lastErrorDetail = ""
    /// This app's own conversation: `--continue` would pick up whatever session was last used in the folder.
    let sessionID: String
    private let readOnly: Bool
    private let binaryOverride: String?
    private let workspace: String
    private let timeLimit: TimeInterval
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var current: RunState?
    /// A run is in progress (from run() to onFinish); stop() asked during a gap between processes is remembered.
    private var active = false
    private var stopRequested = false
    private static let ignoreSigpipe: Void = { signal(SIGPIPE, SIG_IGN) }()
    /// Where proxy settings come from when the environment has none (replaceable in tests).
    static var proxyProvider: () -> [String: String] = { SystemProxy.current() }

    /// Everything one launch shares between its threads, so a later launch can never disturb an earlier one.
    private final class RunState {
        private let lock = NSLock()
        private var _exited = false, _status: Int32 = 0, _timedOut = false, _abandoned = false
        let exitedSignal = DispatchSemaphore(value: 0)
        var exited: Bool { lock.lock(); defer { lock.unlock() }; return _exited }
        var status: Int32 { lock.lock(); defer { lock.unlock() }; return _status }
        var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return _timedOut }
        var abandoned: Bool { lock.lock(); defer { lock.unlock() }; return _abandoned }
        func markExited(_ s: Int32) { lock.lock(); _exited = true; _status = s; lock.unlock(); exitedSignal.signal() }
        func markTimedOut() { lock.lock(); _timedOut = true; lock.unlock() }
        func markAbandoned() { lock.lock(); _abandoned = true; lock.unlock() }
    }

    init(sessionID: String = UUID().uuidString.lowercased(), started: Bool = false,
         binary: String? = nil, workspace: String? = nil, timeLimit: TimeInterval = 600, readOnly: Bool = false) {
        self.readOnly = readOnly
        self.sessionID = sessionID; self.started = started
        self.binaryOverride = binary
        self.workspace = workspace ?? Config.workspace
        self.timeLimit = timeLimit
        _ = Self.ignoreSigpipe  // a write to a child that exited early must fail with EPIPE, not kill the app
    }

    /// PATH for the child: a GUI app gets a short one, so the usual tool folders are appended.
    static func childPATH(_ current: String?, home: String) -> String {
        var parts = (current ?? "").split(separator: ":").map(String.init)
        for extra in ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] where !parts.contains(extra) {
            parts.append(extra)
        }
        return parts.joined(separator: ":")
    }

    func run(prompt: String) {
        lock.lock(); active = true; stopRequested = false; lock.unlock()
        launch(prompt: prompt, mayRetry: true)
    }

    private func launch(prompt: String, mayRetry: Bool) {
        lock.lock(); let cancelled = stopRequested; lock.unlock()
        if cancelled { return finish(-15, "stopped") }
        guard let bin = binaryOverride ?? ClaudeBinary.find() else { return finish(-1, "`claude` not found") }
        let resuming = started
        var args = [bin, "-p", "--append-system-prompt", Self.styleGuide,
                    "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
                + AgentPolicy.arguments(home: Config.home, workspace: workspace, readOnly: readOnly)
        args += resuming ? ["--resume", sessionID] : ["--session-id", sessionID]

        var inP = [Int32](repeating: 0, count: 2), outP = inP, errP = inP
        guard pipe(&inP) == 0 else { return finish(-1, "pipe failed") }
        guard pipe(&outP) == 0 else { inP.forEach { close($0) }; return finish(-1, "pipe failed") }
        guard pipe(&errP) == 0 else { (inP + outP).forEach { close($0) }; return finish(-1, "pipe failed") }
        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        posix_spawn_file_actions_adddup2(&fa, inP[0], 0)
        posix_spawn_file_actions_adddup2(&fa, outP[1], 1)
        posix_spawn_file_actions_adddup2(&fa, errP[1], 2)
        posix_spawn_file_actions_addchdir_np(&fa, workspace)
        var at: posix_spawnattr_t?
        posix_spawnattr_init(&at)
        // Own process group, and SIGPIPE back to the default: an ignored signal would be inherited through exec.
        var defaults = sigset_t()
        sigemptyset(&defaults); sigaddset(&defaults, SIGPIPE)
        posix_spawnattr_setsigdefault(&at, &defaults)
        posix_spawnattr_setflags(&at, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&at, 0)
        var env = AgentEnv.filter(ProcessInfo.processInfo.environment)
        env["PATH"] = Self.childPATH(env["PATH"], home: Config.home)
        // Only fills what the environment doesn't already say.
        let hasProxy = ["HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy"].contains { env[$0] != nil }
        if !hasProxy { for (k, v) in Self.proxyProvider() where env[k] == nil { env[k] = v } }
        let argv = args.map { strdup($0) } + [nil]
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        var child: pid_t = 0
        let state = RunState()
        // Registered before the spawn so stop() can never miss a process that is already running.
        lock.lock(); current = state; lock.unlock()
        let rc = posix_spawn(&child, bin, &fa, &at, argv, envp)
        argv.forEach { free($0) }; envp.forEach { free($0) }
        posix_spawn_file_actions_destroy(&fa); posix_spawnattr_destroy(&at)
        close(inP[0]); close(outP[1]); close(errP[1])
        guard rc == 0 else {
            close(inP[1]); close(outP[0]); close(errP[0])
            lock.lock(); if current === state { current = nil }; lock.unlock()
            return finish(-1, "cannot start claude: \(String(cString: strerror(rc)))")
        }
        lock.lock(); pid = child; let late = stopRequested; lock.unlock()
        if late { stop() }  // stop() was asked between the spawn and this point
        let (wfd, ofd, efd) = (inP[1], outP[0], errP[0])
        let launchedPid = child

        // Prompt via stdin (--allowedTools is variadic and would swallow a trailing argument), written in its own
        // thread and in a loop: a big prompt must not block the readers, and a partial write must not drop its tail.
        let data = Data(prompt.utf8)
        DispatchQueue.global().async {
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var off = 0
                while off < raw.count {
                    let n = Darwin.write(wfd, base + off, raw.count - off)
                    if n > 0 { off += n } else if n < 0 && (errno == EINTR || errno == EAGAIN) { continue } else { break }
                }
            }
            close(wfd)
        }

        // The wait for the process runs apart from the readers, so a grandchild that keeps a pipe open
        // cannot hold the run hostage after claude itself has exited. The pid is released the moment it is reaped.
        DispatchQueue.global().async { [self] in
            var raw: Int32 = 0
            while waitpid(launchedPid, &raw, 0) < 0 && errno == EINTR {}
            lock.lock(); if pid == launchedPid { pid = 0 }; lock.unlock()
            state.markExited(raw)
        }

        let limit = timeLimit
        DispatchQueue.global().asyncAfter(deadline: .now() + limit) { [weak self] in
            guard let self, !state.exited else { return }
            state.markTimedOut()
            self.stop()
        }

        DispatchQueue.global().async { [self] in
            var err = Data()
            let errDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                Self.readLoop(fd: efd, state: state) { err.append($0) }
                errDone.signal()
            }
            var parser = StreamParser()
            var resultText: String?, sawInit = false, pending = Data()
            func handle(_ line: Data) {
                for ev in parser.feed(line: line) {
                    switch ev {
                    case .sessionInit:
                        if !sawInit {
                            sawInit = true
                            DispatchQueue.main.async { self.started = true; self.onStarted() }
                        }
                    case .text(let t): DispatchQueue.main.async { self.onText(t) }
                    case .result(let r): resultText = r
                    }
                }
            }
            Self.readLoop(fd: ofd, state: state) { chunk in
                pending.append(chunk)
                while let nl = pending.firstIndex(of: 10) {
                    handle(pending[pending.startIndex..<nl])
                    pending.removeSubrange(pending.startIndex...nl)
                }
            }
            if !pending.isEmpty { handle(pending) }
            close(ofd)
            errDone.wait(); close(efd)
            // Normally the process is gone by now. If it was abandoned and still hasn't been reaped, don't wait for it.
            while !state.exited {
                if state.abandoned { break }
                _ = state.exitedSignal.wait(timeout: .now() + 0.5)
            }
            var code: Int32
            if state.exited {
                let raw = state.status, sig = raw & 0x7F
                code = sig == 0 ? (raw >> 8) & 0xFF : -sig
            } else { code = -9 }
            let didTimeOut = state.timedOut
            if didTimeOut { code = -2 }
            lock.lock(); if current === state { current = nil }; lock.unlock()

            let streamed = parser.streamedText
            let errText = String(decoding: err.suffix(500), as: UTF8.self)
            DispatchQueue.main.async {
                // A session the CLI no longer knows (a chat restored from an old file): start it afresh, once.
                // The opposite, a session that exists although we never saw it confirmed: continue it, once.
                let unknown = (errText + (resultText ?? "")).contains("No conversation found")
                let taken = (errText + (resultText ?? "")).contains("already in use")
                if code != 0, !streamed, mayRetry, !sawInit {
                    if resuming, unknown {
                        self.started = false
                        return self.launch(prompt: prompt, mayRetry: false)
                    }
                    if !resuming, taken {
                        self.started = true
                        return self.launch(prompt: prompt, mayRetry: false)
                    }
                }
                if !streamed, let r = resultText, !r.isEmpty { self.onText(r) }
                if didTimeOut { self.onText("\n[claude took longer than \(Int(limit / 60)) minutes and was stopped]") }
                else if code != 0, !streamed {
                    // The tail of stderr can hold paths and fragments of the owner's files: it goes to the banner
                    // (in memory), never into the saved conversation.
                    self.lastErrorDetail = errText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if resultText?.isEmpty ?? true { self.onText("[claude failed (code \(code))]") }
                }
                if sawInit || code == 0 { self.started = true }
                self.lock.lock(); self.active = false; self.lock.unlock()
                self.onFinish(code)
            }
        }
    }

    /// Reads a pipe until it closes. Gives up when the watchdog abandoned the run, or when claude has exited
    /// and the pipe stays silent (a grandchild still holds it open).
    private static func readLoop(fd: Int32, state: RunState, onChunk: (Data) -> Void) {
        var buf = [UInt8](repeating: 0, count: 1 << 16)
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        var quietAfterExit = 0
        while true {
            if state.abandoned { break }
            let r = poll(&pfd, 1, 500)
            if r < 0 { if errno == EINTR { continue }; break }
            if r == 0 {
                if state.exited { quietAfterExit += 1; if quietAfterExit >= 4 { break } }
                continue
            }
            let n = read(fd, &buf, buf.count)
            if n > 0 { quietAfterExit = 0; onChunk(Data(buf[0..<n])) }
            else if n == 0 { break }
            else if errno != EINTR && errno != EAGAIN { break }
        }
    }

    /// Kills claude and its children (SIGTERM, SIGKILL after 3 s, then the readers are told to give up).
    func stop() {
        lock.lock()
        let p = pid, st = current
        if active && (p <= 0 || st == nil) { stopRequested = true }  // between processes: remembered for launch()
        lock.unlock()
        guard p > 0, let st else { return }
        killpg(p, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [self] in
            lock.lock(); let still = pid == p; lock.unlock()
            if still { killpg(p, SIGKILL) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [self] in
                lock.lock(); let alive = pid == p; lock.unlock()
                if alive { st.markAbandoned() }
            }
        }
    }

    /// For app quit: nobody is left to escalate later, so the whole process group dies now.
    func killNow() {
        lock.lock(); let p = pid; lock.unlock()
        if p > 0 { killpg(p, SIGKILL) }
    }

    private func finish(_ code: Int32, _ msg: String) {
        lock.lock(); active = false; stopRequested = false; lock.unlock()
        DispatchQueue.main.async { self.onText("[\(msg)]"); self.onFinish(code) }
    }
}
