import SwiftUI
import AppKit

/// Exam preparation sheet: days left, the course's AI rule, a day-by-day topic plan, "Explain" per topic.
struct ExamPrepView: View {
    let exam: MarkdownTables.Item
    @ObservedObject private var router = Router.shared
    @State private var topics: [String] = []
    @State private var checked: Set<String> = []

    private var course: String { exam.course }
    private var daysLeft: Int { exam.date.flatMap { Deadlines.days(from: DateFmt.today(), to: $0) } ?? 0 }
    private var info: String? { try? String(contentsOfFile: "\(Config.resources)/\(course)/course-info.md", encoding: .utf8) }
    private var key: String { "prep.done.\(course)" }
    private var plan: [ExamPrep.Day] { ExamPrep.plan(topics: topics, daysLeft: max(1, daysLeft)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prepare: \(exam.title)").font(.pageTitle).foregroundStyle(Theme.text)
                    Text("\(Theme.short(course)) · \(exam.date ?? "no date")" + (daysLeft >= 0 ? " · \(daysLeft) d left" : ""))
                        .font(.body13).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Close") { router.prepExam = nil }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
            }
            if let tone = AIPolicy.level(course: course, info: info) {
                Banner(icon: tone == .bad ? "exclamationmark.shield" : "info.circle",
                       text: tone == .bad ? "AI is banned in assessments here: explanations and concept questions only, no solving."
                                          : "Your own work: the Agent explains and checks understanding, it does not write what you submit.",
                       tone: tone == .bad ? .bad : .warn)
            }
            if topics.isEmpty {
                EmptyState(icon: "list.bullet", title: "No topic list yet",
                           detail: "Add a Topics table to resources/\(course)/archive-2025.md or ask the Agent to build one from the slides.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(plan, id: \.number) { d in
                            Section2(title: d.review ? "Day \(d.number) · review and timed practice" : "Day \(d.number)") {
                                Group2 {
                                    ForEach(Array(d.topics.enumerated()), id: \.offset) { i, t in
                                        if i > 0 { Hairline() }
                                        HStack(spacing: 10) {
                                            Toggle(t, isOn: Binding(get: { checked.contains(t) }, set: { toggle(t, $0) }))
                                                .toggleStyle(.checkbox).font(.body13)
                                            Spacer()
                                            Button("Explain") { explain(t) }.buttonStyle(QuietButton())
                                        }.padding(.horizontal, 14).padding(.vertical, 8)
                                    }
                                    if d.review { Text("Old quizzes and mock papers: resources/\(course)/archive-2025/")
                                        .font(.meta).foregroundStyle(Theme.muted).padding(14) }
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Text("\(checked.intersection(topics).count) of \(topics.count) topics done").font(.meta).foregroundStyle(Theme.muted)
                Spacer()
                Button("Open archive folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "\(Config.resources)/\(course)/archive-2025"))
                }.buttonStyle(QuietButton())
            }
        }
        .padding(24).frame(width: 620, height: 560)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .onAppear {
            topics = ExamPrep.topics(archiveMd: (try? String(contentsOfFile: "\(Config.resources)/\(course)/archive-2025.md", encoding: .utf8)) ?? "")
            checked = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        }
    }

    private func toggle(_ t: String, _ on: Bool) {
        if on { checked.insert(t) } else { checked.remove(t) }
        UserDefaults.standard.set(Array(checked), forKey: key)
    }

    private func explain(_ topic: String) {
        router.prepExam = nil
        router.page = .chat
        ChatModel.shared.newChat()
        ChatModel.shared.send(ExamPrep.explainPrompt(topic: topic, course: course, exam: exam.title), course: course)
    }
}
