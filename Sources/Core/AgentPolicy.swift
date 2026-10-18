import Foundation

/// What the chat agent may do. It reads text written by other people (course chats, notices), so everything
/// here is a narrow allow list plus a few explicit denials as a second line.
/// Path syntax of Claude Code rules: `./x` relative to the working folder, `//abs` absolute, `~/x` home.
enum AgentPolicy {
    /// The one helper the agent may run; it checks every path itself (tools/agent_tools.py in Study Workspace).
    static let helper = "python3 tools/agent_tools.py"

    /// Files the agent may change on its own ("auto" mode). Every change is shown to the owner and can be undone.
    static let editable = [
        "./resources/*/assignments.md",
        "./resources/exam-dates.md",
        "./resources/*/course-info.md",
        "./resources/*/2026/files.md",
        "./output/**",
    ]

    /// Real folders behind `resources/*/archive-*` (the senior archive is a symlink out of the workspace).
    /// Reading there is wanted (old homework, mock exams); the permission check follows the link, so it needs its own rule.
    static func archiveRoots(workspace: String) -> [String] {
        let fm = FileManager.default
        let res = "\(workspace)/resources"
        var roots = Set<String>()
        for course in (try? fm.contentsOfDirectory(atPath: res)) ?? [] {
            for name in (try? fm.contentsOfDirectory(atPath: "\(res)/\(course)")) ?? [] where name.hasPrefix("archive-") {
                let real = URL(fileURLWithPath: "\(res)/\(course)/\(name)").resolvingSymlinksInPath().path
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: real, isDirectory: &isDir), isDir.boolValue, !(real == workspace || real.hasPrefix(workspace + "/")) { roots.insert(real) }
            }
        }
        return roots.sorted()
    }

    /// Real files the owner linked into `resources/` from elsewhere (a textbook): exactly those files, not their folders.
    static func linkedFiles(workspace: String) -> [String] {
        let fm = FileManager.default
        let res = "\(workspace)/resources"
        var out = Set<String>()
        guard let en = fm.enumerator(atPath: res) else { return [] }
        for case let rel as String in en {
            if rel.split(separator: "/").count > 4 { en.skipDescendants(); continue }
            let path = "\(res)/\(rel)"
            // (No skipDescendants on non-directories: on a file it skips the remaining siblings of its folder.)
            guard let attrs = try? fm.attributesOfItem(atPath: path), attrs[.type] as? FileAttributeType == .typeSymbolicLink else { continue }
            let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: real, isDirectory: &isDir), !isDir.boolValue,
               !(real == workspace || real.hasPrefix(workspace + "/")) { out.insert(real) }
        }
        return out.sorted()
    }

    static func allow(workspace: String? = nil, readOnly: Bool = false) -> [String] {
        let archives = workspace.map { archiveRoots(workspace: $0).map { "Read(/\($0)/**)" }
                                       + linkedFiles(workspace: $0).map { "Read(/\($0))" } } ?? []
        // No bare Grep/Glob here: a bare allow lets them search anywhere. Read rules govern what they may touch.
        return ["Read(./**)", "Bash(\(helper) *)"] + archives + (readOnly ? [] : editable.map { "Edit(\($0))" })
    }

    static func deny(home: String, readOnly: Bool = false) -> [String] {
        let abs = "/" + home  // "/Users/me" -> "//Users/me" (absolute form of a rule path)
        let edit = ["./CLAUDE.md", "./tools/**", "./workflows/**", "./.claude/**", "./.gitignore",
                    "./resources/*/archive-*/**", "./resources/sources.md"].map { "Edit(\($0))" }
        let read = [".config", ".ssh", "Library", ".zshrc", ".zprofile", ".aws", ".gnupg", "Downloads", "Desktop"]
            .map { "Read(\(abs)/\($0)/**)" } + ["Read(\(abs)/.zshrc)", "Read(\(abs)/.zprofile)", "Read(**/.env*)"]
        let bash = ["Bash(*life_sync*)", "Bash(git *)", "Bash(curl *)", "Bash(wget *)", "Bash(ssh *)", "Bash(rm *)", "Bash(sudo *)"]
        // Questions from the iPhone are answers only: no edits, and nothing from the repository history or settings.
        let relay = readOnly ? ["Edit(./**)", "Write(./**)", "Read(./.git/**)", "Read(./.claude/**)"] : []
        return edit + read + bash + relay
    }

    /// Arguments for `claude -p`: tools whitelist, no prompts (anything not allowed is refused), no MCP servers,
    /// no user or local settings (hooks, extra permissions), only the project's own.
    static func arguments(home: String, workspace: String? = nil, readOnly: Bool = false) -> [String] {
        ["--tools", readOnly ? "Read,Grep,Glob,Bash" : "Read,Grep,Glob,Edit,Write,Bash",
         "--permission-mode", "dontAsk",
         "--strict-mcp-config",
         "--setting-sources", "project",
         "--allowedTools"] + allow(workspace: workspace, readOnly: readOnly) + ["--disallowedTools"] + deny(home: home, readOnly: readOnly)
    }
}

/// The environment the agent's process gets: what claude and the network need, not the user's other secrets.
enum AgentEnv {
    static let exact: Set<String> = [
        "PATH", "HOME", "USER", "LOGNAME", "SHELL", "LANG", "TMPDIR", "TERM", "__CF_USER_TEXT_ENCODING",
        "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY", "https_proxy", "http_proxy", "all_proxy", "no_proxy",
        "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS",
        // claude's own sign-in and config location; nothing else with these prefixes
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CONFIG_DIR",
    ]
    static let prefixes = ["LC_"]

    static func filter(_ env: [String: String]) -> [String: String] {
        env.filter { k, _ in exact.contains(k) || prefixes.contains { k.hasPrefix($0) } }
    }
}

/// A `claude` binary found in a folder others can write to would run with the owner's rights.
enum BinaryCheck {
    static func trusted(path: String, uid: uid_t = getuid()) -> Bool {
        let fm = FileManager.default
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard fm.isExecutableFile(atPath: real) else { return false }
        func ok(_ p: String) -> Bool {
            guard let a = try? fm.attributesOfItem(atPath: p),
                  let owner = a[.ownerAccountID] as? NSNumber,
                  let perm = a[.posixPermissions] as? NSNumber else { return false }
            let mine = owner.uint32Value == uid || owner.uint32Value == 0
            return mine && (perm.intValue & 0o022) == 0  // not writable by group or others
        }
        return ok(real) && ok((real as NSString).deletingLastPathComponent)
    }
}
