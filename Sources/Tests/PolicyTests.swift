import Foundation

func policyTests() {
    let home = "/Users/tester"
    let allow = AgentPolicy.allow()
    let deny = AgentPolicy.deny(home: home)
    expect(allow.contains("Bash(python3 tools/agent_tools.py *)"), "policy: the helper is allowed")
    expect(!allow.contains("Grep") && !allow.contains("Glob"), "policy: no bare Grep/Glob allow (it would search anywhere)")
    expect(!allow.contains { $0.contains("pdf.py") || $0.contains("office.py") || $0.contains("life_sync") }, "policy: raw tools are not allowed")
    expect(!allow.contains { $0.hasPrefix("Edit(./resources/**)") || $0 == "Edit(./**)" }, "policy: edits are not broad")
    expect(allow.contains("Edit(./resources/*/assignments.md)") && allow.contains("Edit(./output/**)"), "policy: the editable list")
    for must in ["Edit(./CLAUDE.md)", "Edit(./tools/**)", "Edit(./workflows/**)", "Edit(./.claude/**)",
                 "Edit(./resources/*/archive-*/**)", "Edit(./resources/sources.md)", "Bash(*life_sync*)", "Bash(git *)",
                 "Read(//Users/tester/.config/**)", "Read(//Users/tester/.ssh/**)", "Read(//Users/tester/Library/**)",
                 "Read(//Users/tester/.zshrc)", "Read(**/.env*)"] {
        expect(deny.contains(must), "policy: denies \(must)")
    }
    // the archive behind a symlink gets its own read rule; other symlinks do not
    let tmp = NSTemporaryDirectory() + "ld-policy-\(getpid())"
    let fm0 = FileManager.default
    try? fm0.createDirectory(atPath: tmp + "/ws/resources/c1", withIntermediateDirectories: true)
    try? fm0.createDirectory(atPath: tmp + "/archive", withIntermediateDirectories: true)
    try? fm0.createDirectory(atPath: tmp + "/other", withIntermediateDirectories: true)
    try? fm0.createSymbolicLink(atPath: tmp + "/ws/resources/c1/archive-2025", withDestinationPath: tmp + "/archive")
    try? fm0.createSymbolicLink(atPath: tmp + "/ws/resources/c1/linkout", withDestinationPath: tmp + "/other")
    defer { try? fm0.removeItem(atPath: tmp) }
    try? fm0.createDirectory(atPath: tmp + "/ws-twin/x", withIntermediateDirectories: true)
    try? fm0.createSymbolicLink(atPath: tmp + "/ws/resources/c1/archive-2024", withDestinationPath: tmp + "/ws-twin/x")
    try? "book".write(toFile: tmp + "/other/book.pdf", atomically: true, encoding: .utf8)
    try? "secret".write(toFile: tmp + "/other/secret.pdf", atomically: true, encoding: .utf8)
    try? fm0.createSymbolicLink(atPath: tmp + "/ws/resources/c1/textbook.pdf", withDestinationPath: tmp + "/other/book.pdf")
    let withArchive = AgentPolicy.allow(workspace: tmp + "/ws")
    let archiveReal = URL(fileURLWithPath: tmp + "/archive").resolvingSymlinksInPath().path
    expect(withArchive.contains("Read(/\(archiveReal)/**)"), "policy: archive folder is readable")
    let otherReal = URL(fileURLWithPath: tmp + "/other").resolvingSymlinksInPath().path
    expect(withArchive.contains("Read(/\(otherReal)/book.pdf)"), "policy: a linked textbook is readable (rules: \(withArchive.filter { $0.hasPrefix("Read(//") }))")
    expect(!withArchive.contains { $0.contains("secret.pdf") || $0.contains("Read(/\(otherReal)/**)") }, "policy: its neighbours and folder stay closed")
    expect(withArchive.contains { $0.contains("ws-twin") }, "policy: a sibling folder that only shares the workspace name prefix still counts as outside (readable as archive)")

    let args = AgentPolicy.arguments(home: home)
    expect(args.contains("--strict-mcp-config") && args.contains("dontAsk"), "policy: no MCP, no prompts")
    expect(args.contains("--setting-sources") && args[args.firstIndex(of: "--setting-sources")! + 1] == "project", "policy: project settings only")
    expect(args.firstIndex(of: "--allowedTools")! < args.firstIndex(of: "--disallowedTools")!, "policy: both lists present")

    let env = AgentEnv.filter(["PATH": "/usr/bin", "HOME": "/Users/x", "GITHUB_TOKEN": "ghp_secret", "OPENAI_API_KEY": "sk-secret",
                               "AWS_SECRET_ACCESS_KEY": "aws", "HTTPS_PROXY": "http://127.0.0.1:7897", "LC_ALL": "en_US.UTF-8",
                               "CLAUDE_CODE_OAUTH_TOKEN": "t", "ANTHROPIC_API_KEY": "k"])
    expect(env["PATH"] != nil && env["HOME"] != nil && env["HTTPS_PROXY"] != nil && env["LC_ALL"] != nil, "env: needed variables stay")
    expect(env["GITHUB_TOKEN"] == nil && env["OPENAI_API_KEY"] == nil && env["AWS_SECRET_ACCESS_KEY"] == nil, "env: other secrets removed")
    expect(env["CLAUDE_CODE_OAUTH_TOKEN"] != nil && env["ANTHROPIC_API_KEY"] != nil, "env: claude's own variables stay")
    let env2 = AgentEnv.filter(["ANTHROPIC_BASE_URL": "http://evil", "CLAUDE_SOMETHING": "x", "XDG_CONFIG_HOME": "/x", "CLAUDE_CONFIG_DIR": "/c"])
    expect(env2["ANTHROPIC_BASE_URL"] == nil && env2["CLAUDE_SOMETHING"] == nil && env2["XDG_CONFIG_HOME"] == nil, "env: only claude's own named variables")
    expect(env2["CLAUDE_CONFIG_DIR"] == "/c", "env: CLAUDE_CONFIG_DIR stays")

    // binary trust: a file in a world-writable folder is refused, one in a private folder is accepted
    let dir = NSTemporaryDirectory() + "ld-bin-\(getpid())"
    let fm = FileManager.default
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(atPath: dir) }
    let bin = "\(dir)/claude"
    try? "#!/bin/sh\n".write(toFile: bin, atomically: true, encoding: .utf8)
    chmod(bin, 0o755); chmod(dir, 0o755)
    expect(BinaryCheck.trusted(path: bin), "binary: private folder is trusted")
    chmod(dir, 0o777)
    expect(!BinaryCheck.trusted(path: bin), "binary: world-writable folder is refused")
    chmod(dir, 0o755); chmod(bin, 0o775)
    expect(!BinaryCheck.trusted(path: bin), "binary: group-writable file is refused")
    expect(!BinaryCheck.trusted(path: "\(dir)/missing"), "binary: missing file is refused")
    print("Policy tests OK")
}
