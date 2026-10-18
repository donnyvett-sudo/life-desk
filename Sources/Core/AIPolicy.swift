import Foundation

/// Per-course rules for using the Agent (W8.1). The course-info.md text decides; the built-in list is the fallback.
enum AIPolicy {
    /// .bad = generative AI banned in assessments, .warn = work must be the student's own, nil = no rule found.
    /// The stricter of what the file says and the built-in list: rewording a file can never loosen a ban.
    static func level(course: String, info: String?) -> CourseInfo.PolicyTone? {
        var fromText: CourseInfo.PolicyTone?
        if let t = info?.lowercased(), !t.isEmpty {
            let mentionsAI = t.contains("generative") || t.contains(" ai ") || t.contains("ai policy") || t.contains("artificial intelligence")
            let bans = ["not permitted", "not allowed", "banned", "prohibited", "forbidden", "forbid", "must not use", "no ai"]
            if mentionsAI, bans.contains(where: t.contains) { fromText = .bad }
            else if t.contains("on your own") || t.contains("own work") { fromText = .warn }
        }
        let builtIn = CourseInfo.policy(course)?.tone
        if fromText == .bad || builtIn == .bad { return .bad }
        return fromText ?? builtIn
    }

    /// Words that name a course besides its folder and short label (other languages, spelled out). Ships empty:
    /// e.g. ["stats101": ["probability", "statistics"]].
    nonisolated(unsafe) static var aliases: [String: [String]] = [:]

    /// Instruction put before the question; empty when the course has no rule.
    static func prefix(course: String, tone: CourseInfo.PolicyTone?) -> String {
        switch tone {
        case .bad:
            return "Course \(course) bans generative AI in all assessments. Do not solve, check, hint at or paraphrase homework, quiz or exam questions. "
                + "Explain only concepts, with clearly different examples of your own, and point to the course slides. "
        case .warn:
            return "Course \(course) requires that assignments are the student's own work. Explain concepts and debug understanding with separate examples; do not write code or text to be submitted. "
        case nil:
            return ""
        }
    }

    /// The course a message is about when none is picked: a folder name or its short label appears in the text.
    static func course(in text: String, among folders: [String], label: (String) -> String) -> String? {
        let t = text.lowercased()
        // A banned course wins when a message names several courses.
        let hits = folders.filter { f in
            t.contains(f.lowercased()) || t.contains(label(f).lowercased()) || (aliases[f] ?? []).contains { t.contains($0) }
        }
        return hits.first { CourseInfo.policy($0)?.tone == .bad } ?? hits.first
    }
}
