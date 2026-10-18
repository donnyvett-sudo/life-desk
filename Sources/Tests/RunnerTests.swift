import Foundation

/// A fake `claude`: a shell script whose behaviour is chosen by the test. Runs through the real ClaudeRunner.
private func makeFake(_ body: String, in dir: String, name: String) -> String {
    let path = "\(dir)/\(name)"
    try? ("#!/bin/sh\n" + body).write(toFile: path, atomically: true, encoding: .utf8)
    chmod(path, 0o755)
    return path
}

private func runFake(_ bin: String, dir: String, prompt: String = "hi", started: Bool = false,
                     stopAfter: TimeInterval? = nil, timeout: TimeInterval = 20, timeLimit: TimeInterval = 600)
    -> (text: String, code: Int32?, started: Bool, seconds: TimeInterval) {
    let r = ClaudeRunner(sessionID: "test-session", started: started, binary: bin, workspace: dir, timeLimit: timeLimit)
    var text = "", code: Int32?
    r.onText = { text += $0 }
    r.onFinish = { code = $0 }
    let t0 = Date()
    r.run(prompt: prompt)
    var stopped = false
    while code == nil && Date().timeIntervalSince(t0) < timeout {
        if let s = stopAfter, !stopped, Date().timeIntervalSince(t0) > s { stopped = true; r.stop() }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return (text, code, r.started, Date().timeIntervalSince(t0))
}

private let initLine = #"{"type":"system","subtype":"init","session_id":"abc"}"#
private func delta(_ t: String) -> String {
    #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"\#(t)"}}}"#
}

func runnerTests() {
    // --- pure parts
    var p = StreamParser()
    expect(p.feed(line: Data(initLine.utf8)) == [.sessionInit("abc")], "parser: init event")
    expect(p.feed(line: Data(delta("Sure.").utf8)) == [.text("Sure.")], "parser: text delta")
    _ = p.feed(line: Data(#"{"type":"stream_event","event":{"type":"message_start"}}"#.utf8))
    expect(p.feed(line: Data(delta("Result").utf8)) == [.text("\n\nResult")], "parser: separator between messages")
    expect(p.feed(line: Data("not json".utf8)).isEmpty, "parser: garbage ignored")
    expect(ClaudeRunner.childPATH("/usr/bin", home: "/Users/x").contains("/opt/homebrew/bin"), "PATH gets homebrew")
    expect(ClaudeRunner.childPATH("/opt/homebrew/bin:/usr/bin", home: "/Users/x").components(separatedBy: "/opt/homebrew/bin").count == 2,
           "PATH has no duplicates")

    let dir = NSTemporaryDirectory() + "ld-runner-\(getpid())"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    // --- success: init + two messages + exit 0
    let ok = makeFake("""
    cat > /dev/null
    echo '\(initLine)'
    echo '\(delta("First."))'
    echo '{"type":"stream_event","event":{"type":"message_start"}}'
    echo '\(delta("Second."))'
    echo '{"type":"result","result":"First.Second."}'
    """, in: dir, name: "ok")
    let a = runFake(ok, dir: dir)
    expect(a.code == 0 && a.started, "runner: success marks the session started (code \(String(describing: a.code)))")
    expect(a.text == "First.\n\nSecond.", "runner: text and separator (got \(a.text.debugDescription))")

    // --- failure before init: the chat must not become 'started'
    let bad = makeFake("cat > /dev/null; echo 'not logged in' >&2; exit 1", in: dir, name: "bad")
    let b = runFake(bad, dir: dir)
    expect(b.code == 1 && !b.started, "runner: failed first run leaves started = false")
    expect(b.text.contains("claude failed (code 1)") && !b.text.contains("not logged in"), "runner: stderr stays out of the chat text (got \(b.text.debugDescription))")

    // --- a 1 MB prompt goes through intact
    let big = makeFake("""
    n=$(wc -c | tr -d " ")
    echo '\(initLine)'
    echo "{\\"type\\":\\"result\\",\\"result\\":\\"bytes=$n\\"}"
    """, in: dir, name: "big")
    let c = runFake(big, dir: dir, prompt: String(repeating: "a", count: 1_000_000))
    expect(c.text.contains("bytes=1000000"), "runner: 1 MB prompt delivered (got \(c.text.prefix(60)))")

    // --- SIGPIPE must be the default in the child
    let sig = makeFake("""
    cat > /dev/null
    echo '\(initLine)'
    v=$(perl -e 'print defined $SIG{PIPE} ? $SIG{PIPE} : "DEFAULT"')
    echo "{\\"type\\":\\"result\\",\\"result\\":\\"sigpipe=$v\\"}"
    """, in: dir, name: "sig")
    let d = runFake(sig, dir: dir)
    expect(d.text.contains("sigpipe=DEFAULT"), "runner: child has default SIGPIPE (got \(d.text))")

    // --- a grandchild that keeps the pipe open must not hold the run
    let held = makeFake("""
    cat > /dev/null
    echo '\(initLine)'
    echo '\(delta("done"))'
    sleep 30 &
    exit 0
    """, in: dir, name: "held")
    let e = runFake(held, dir: dir)
    expect(e.code == 0 && e.seconds < 8, "runner: finishes although a grandchild holds the pipe (\(e.seconds) s)")

    // --- stop() ends a long run
    let slow = makeFake("cat > /dev/null; echo '\(initLine)'; sleep 60", in: dir, name: "slow")
    let f = runFake(slow, dir: dir, stopAfter: 0.5)
    expect(f.code != nil && f.code != 0 && f.seconds < 10, "runner: stop() finishes the run (code \(String(describing: f.code)), \(f.seconds) s)")

    // --- a restored chat whose session the CLI no longer knows is restarted once with --session-id
    let resume = makeFake("""
    cat > /dev/null
    case "$*" in
      *--resume*) echo 'No conversation found with session ID' >&2; exit 1 ;;
      *) echo '\(initLine)'; echo '\(delta("fresh"))' ;;
    esac
    """, in: dir, name: "resume")
    let g = runFake(resume, dir: dir, started: true)
    expect(g.code == 0 && g.started && g.text == "fresh", "runner: unknown session is restarted (got \(g.text.debugDescription), code \(String(describing: g.code)))")

    // --- a session that exists although we never saw it confirmed: continued once with --resume
    let taken = makeFake("""
    cat > /dev/null
    case "$*" in
      *--session-id*) echo 'Error: Session ID test-session is already in use' >&2; exit 1 ;;
      *) echo '\(initLine)'; echo '\(delta("continued"))' ;;
    esac
    """, in: dir, name: "taken")
    let h = runFake(taken, dir: dir, started: false)
    expect(h.code == 0 && h.started && h.text == "continued", "runner: session already in use is resumed (got \(h.text.debugDescription))")

    // --- the time limit stops a run that never ends
    let endless = makeFake("cat > /dev/null; echo '\(initLine)'; sleep 60", in: dir, name: "endless")
    let i = runFake(endless, dir: dir, timeout: 15, timeLimit: 1)
    expect(i.code == -2 && i.text.contains("took longer"), "runner: time limit ends the run (code \(String(describing: i.code)))")

    // --- started is announced as soon as init arrives, before the run ends
    let early = makeFake("cat > /dev/null; echo '\(initLine)'; sleep 3; echo '\(delta("late"))'", in: dir, name: "early")
    let r2 = ClaudeRunner(sessionID: "s", started: false, binary: early, workspace: dir)
    var startedAt: TimeInterval?, finishedAt: TimeInterval?
    let t0 = Date()
    r2.onStarted = { startedAt = Date().timeIntervalSince(t0) }
    r2.onFinish = { _ in finishedAt = Date().timeIntervalSince(t0) }
    r2.run(prompt: "x")
    while finishedAt == nil && Date().timeIntervalSince(t0) < 15 { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    expect(startedAt != nil && finishedAt != nil && startedAt! < finishedAt! - 1.5, "runner: onStarted fires at init, not at the end")

    // --- stop() asked before the process exists is not lost
    let quick = ClaudeRunner(sessionID: "s", started: false, binary: ok, workspace: dir)
    var qCode: Int32?
    quick.onFinish = { qCode = $0 }
    quick.run(prompt: "x")
    quick.stop()  // immediately: the spawn may not have registered its pid yet
    let q0 = Date()
    while qCode == nil && Date().timeIntervalSince(q0) < 10 { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    expect(qCode != nil, "runner: a run with an early stop() still finishes (code \(String(describing: qCode)))")

    // --- proxy: from macOS settings when the environment has none
    let sys: [String: Any] = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 7897,
                              "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7897,
                              "ExceptionsList": ["127.0.0.1", "*.local", "10.0.0.0/8"]]
    let env = SystemProxy.environment(from: sys)
    expect(env["HTTPS_PROXY"] == "http://127.0.0.1:7897" && env["HTTP_PROXY"] == "http://127.0.0.1:7897", "proxy: urls built")
    expect(env["NO_PROXY"]?.contains("localhost") == true && env["NO_PROXY"]?.contains(".local") == true, "proxy: exceptions kept")
    expect(SystemProxy.environment(from: ["HTTPEnable": 0, "HTTPSEnable": 0]).isEmpty, "proxy: disabled gives nothing")
    expect(SystemProxy.environment(from: nil).isEmpty, "proxy: no settings gives nothing")
    let saved = (getenv("HTTPS_PROXY").map { String(cString: $0) }, getenv("https_proxy").map { String(cString: $0) },
                 getenv("ALL_PROXY").map { String(cString: $0) }, getenv("all_proxy").map { String(cString: $0) })
    for k in ["HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy"] { unsetenv(k) }
    ClaudeRunner.proxyProvider = { SystemProxy.environment(from: sys) }
    let prox = makeFake("""
    cat > /dev/null
    echo '\(initLine)'
    echo "{\\"type\\":\\"result\\",\\"result\\":\\"proxy=$HTTPS_PROXY\\"}"
    """, in: dir, name: "prox")
    let pr = runFake(prox, dir: dir)
    expect(pr.text.contains("proxy=http://127.0.0.1:7897"), "runner: child gets the system proxy (got \(pr.text))")
    ClaudeRunner.proxyProvider = { SystemProxy.current() }
    if let v = saved.0 { setenv("HTTPS_PROXY", v, 1) }
    if let v = saved.1 { setenv("https_proxy", v, 1) }
    if let v = saved.2 { setenv("ALL_PROXY", v, 1) }
    if let v = saved.3 { setenv("all_proxy", v, 1) }

    print("Runner tests OK")
}
