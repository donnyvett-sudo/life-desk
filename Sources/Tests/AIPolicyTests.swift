import Foundation

func aiPolicyTests() {
    CourseInfo.builtInPolicies = ["stats101": ("Generative AI banned in all assessments", .bad), "cpp": ("Assignments must be your own work", .warn)]
    AIPolicy.aliases = ["stats101": ["probability", "statistics", "теорвер"]]
    defer { CourseInfo.builtInPolicies = [:]; AIPolicy.aliases = [:] }
    expect(AIPolicy.level(course: "x", info: "Use of generative AI is NOT permitted in any assessments.") == .bad, "ai: banned from text")
    expect(AIPolicy.level(course: "x", info: "Assignments must be completed on your own.") == .warn, "ai: own work from text")
    expect(AIPolicy.level(course: "stats101", info: nil) == .bad, "ai: fallback list")
    expect(AIPolicy.level(course: "lang1", info: "Textbook: Integrated Chinese") == nil, "ai: no rule")
    expect(AIPolicy.prefix(course: "stats101", tone: .bad).contains("Do not solve") && AIPolicy.prefix(course: "x", tone: nil).isEmpty, "ai: prefix")
    expect(AIPolicy.course(in: "помоги с stats101 hw3", among: ["cpp", "stats101"], label: { $0 }) == "stats101", "ai: course named in text")
    expect(AIPolicy.course(in: "explain Stats 101 Bayes", among: ["stats101"], label: { _ in "Stats 101" }) == "stats101", "ai: label match")
    expect(AIPolicy.course(in: "what is due", among: ["cpp"], label: { $0 }) == nil, "ai: none")
    expect(AIPolicy.level(course: "stats101", info: "AI tools are not allowed in assessments. Work on your own.") == .bad, "ai: reworded ban stays a ban")
    expect(AIPolicy.level(course: "stats101", info: "Textbook: Walpole") == .bad, "ai: built-in ban survives silent file")
    expect(AIPolicy.course(in: "помоги с теорвером", among: ["cpp", "stats101"], label: { $0 }) == "stats101", "ai: russian alias")
    expect(AIPolicy.course(in: "compare cpp and stats101", among: ["cpp", "stats101"], label: { $0 }) == "stats101", "ai: banned course wins")
    print("AIPolicy tests OK")
}
