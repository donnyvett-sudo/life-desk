import SwiftUI

struct ChatView: View {
    @ObservedObject private var model = ChatModel.shared
    @State private var input = ""
    @State private var inputHeight: CGFloat = ChatInput.minHeight
    @State private var course = ""
    @State private var atBottom = true
    private let binary = ClaudeBinary.find()
    private let courses = MarkdownTables.courseFolders(resources: Config.resources)
    private let suggestions = ["What is due this week?", "What changed in the chats?", "Explain this week's topics in my courses simply"]

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                // Narrow window: the chat list gives way to the conversation (⌘N still makes a new chat).
                if g.size.width >= 900 {
                    ChatListPanel(model: model)
                    Rectangle().fill(Theme.line).frame(width: 1)
                }
                chatColumn
            }
        }
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            titleBar.column()
            if let n = model.notice {
                ErrorBanner(text: n) { model.notice = nil }.column().padding(.bottom, 8)
            }
            if binary == nil {
                Group2 {
                    RowButton {
                        HStack(spacing: 8) {
                            Chip(text: "claude missing", tone: .bad)
                            Text("Not found in PATH, ~/.local/bin, /opt/homebrew/bin, /usr/local/bin. Install Claude Code and restart.")
                                .font(.meta).foregroundStyle(Theme.muted)
                        }
                    }
                }.column().padding(.bottom, 8)
            }
            if model.messages.isEmpty { emptyState } else { messageList }
            composer.column()
        }
        .background(Theme.bg)
    }

    // MARK: parts

    private var titleBar: some View {
        HStack {
            Text("Agent").font(.pageTitle).foregroundStyle(Theme.text)
            Spacer()
        }.padding(.top, 20).padding(.bottom, 8)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.newChat() } label: { Label("New chat", systemImage: "square.and.pencil") }
                    .disabled(model.messages.isEmpty && !model.running).help("New chat (⌘N)")
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Section2(title: "Try asking") {
                Group2 {
                    Rows(items: suggestions.map { Suggestion(text: $0) }) { s in
                        RowButton(action: { ask(s.text) }) {
                            HStack {
                                Text(s.text).font(.chatBody).foregroundStyle(Theme.text)
                                Spacer()
                                Image(systemName: "arrow.up.circle").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            Text("It reads your course files and may update assignments, exam dates and notes. It can’t run other scripts.")
                .font(.meta).foregroundStyle(Theme.muted)
            Spacer()
        }.column()
    }

    private struct Suggestion: Identifiable { let text: String; var id: String { text } }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(model.messages) { m in
                        ChatRow(message: m, streaming: model.running && m.id == model.messages.last?.id,
                                keep: { model.keepChanges(chat: model.currentID, message: m.id) },
                                revert: { model.revertChanges(chat: model.currentID, message: m.id) }).id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { atBottom = true }.onDisappear { atBottom = false }
                }.padding(.vertical, 12).column()
            }
            .onChange(of: model.messages.last?.text) { _, _ in if atBottom { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: model.messages.count) { _, _ in atBottom = true; proxy.scrollTo("bottom", anchor: .bottom) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !course.isEmpty, let tone = AIPolicy.level(course: course, info: try? String(contentsOfFile: "\(Config.resources)/\(course)/course-info.md", encoding: .utf8)) {
                Banner(icon: tone == .bad ? "exclamationmark.shield" : "info.circle",
                       text: tone == .bad ? "\(Theme.short(course)) bans AI in assessments: the Agent explains concepts only and will not solve assignments."
                                          : "\(Theme.short(course)): assignments must be your own work. The Agent explains and debugs understanding, it does not write what you submit.",
                       tone: tone == .bad ? .bad : .warn)
            }
            ChatInput(text: $input, height: $inputHeight, onSend: send)
                .frame(height: inputHeight)
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("Ask about your courses…").font(.chatBody).foregroundStyle(Theme.muted)
                            .padding(.leading, 8).padding(.top, 5).allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .deskGlass(RoundedRectangle(cornerRadius: 20))
            HStack(spacing: 10) {
                Menu {
                    Button("No course") { course = "" }
                    ForEach(courses, id: \.self) { c in Button(Theme.short(c)) { course = c } }
                } label: {
                    if course.isEmpty { Text("No course").font(.meta).foregroundStyle(Theme.muted) }
                    else { CourseTag(code: course) }
                }.menuStyle(.borderlessButton).fixedSize().help("Course the question is about")
                Spacer()
                if model.running { Button("Stop") { model.stop() }.buttonStyle(PrimaryButton()) }
                else {
                    Button("Send", action: send).buttonStyle(PrimaryButton())
                        .disabled(binary == nil || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.padding(.top, 8).padding(.bottom, 16)
    }

    private func ask(_ t: String) {
        guard binary != nil else { return }
        model.send(t, course: course.isEmpty ? nil : course)
    }

    private func send() {
        let t = input
        guard binary != nil, !model.running, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        input = ""
        ask(t)
    }
}

private extension View {
    /// Message column: max 720 pt, centred, 28 pt page padding.
    func column() -> some View { padding(.horizontal, 28).frame(maxWidth: 720 + 56).frame(maxWidth: .infinity) }
}

/// One message: user = right-aligned tinted bubble; agent = plain markdown with a small "Claude" label.
struct ChatRow: View {
    let message: ChatMessage
    let streaming: Bool
    var keep: () -> Void = {}
    var revert: () -> Void = {}
    @State private var hover = false

    var body: some View {
        if message.fromUser {
            HStack {
                Spacer(minLength: 80)
                Text(message.text).font(.chatBody).lineSpacing(3).foregroundStyle(Theme.text).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Claude").font(.chip).foregroundStyle(Theme.muted)
                    if streaming { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10) }
                    Spacer()
                    if !message.text.isEmpty && !streaming { ChatCopyButton(text: message.text).opacity(hover ? 1 : 0) }
                }
                if message.text.isEmpty {
                    Text(streaming ? "Thinking…" : "No reply").font(.chatBody).foregroundStyle(Theme.muted)
                } else { ChatMarkdown(text: message.text) }
                if let c = message.changes, !streaming { ChangesCard(changes: c, keep: keep, revert: revert) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
        }
    }
}
