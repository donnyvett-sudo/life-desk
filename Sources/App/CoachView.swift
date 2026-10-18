import SwiftUI
import AppKit

/// Liquid Glass for floating controls (composer, quote bar); solid surface when Reduce Transparency is on.
struct DeskGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var solid
    func body(content: Content) -> some View {
        if solid {
            content.background(Theme.surface, in: shape).overlay(shape.stroke(Theme.line, lineWidth: 1))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
extension View {
    func deskGlass<S: Shape>(_ shape: S) -> some View { modifier(DeskGlass(shape: shape)) }
}

/// The coach conversation (the iPhone's Feed): GET /inbox, POST /entry, POST /actions.
@MainActor
final class CoachModel: ObservableObject {
    struct Item: Identifiable, Decodable, Equatable {
        struct Action: Decodable, Hashable { var id: String; var label: String; var style: String?; var url: String? }
        var id: String
        var kind: String
        var title: String?
        var body: String
        var actions: [Action]?
        var created_at: String
        var read_at: String?
        var handled_at: String?
        var reply_to: String?
        var isMine: Bool { kind == "user" }
        var buttons: [Action] { handled_at == nil ? actions ?? [] : [] }
        /// Spending and meal records ("x:" undo, "ml:" meal buttons) render as cards, not bubbles.
        var isRecord: Bool { (actions ?? []).contains { $0.id.hasPrefix("x:") || $0.id.hasPrefix("ml:") } }
        private static let isoFraction: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
        private static let isoPlain = ISO8601DateFormatter()
        var date: Date? { Self.isoFraction.date(from: created_at) ?? Self.isoPlain.date(from: created_at) }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var sending = false
    @Published var note: String?
    @Published private(set) var unsupported = false
    private var running = Set<String>()
    /// One key per message: a retry of the same text (and quote) reuses it, so the server never records it twice.
    private var pendingKey: (key: String, text: String, replyTo: String?)?

    func load() async {
        let r: (status: Int, data: Data)
        do { r = try await BotAPI.raw("GET", "/inbox?limit=80") }
        catch is CancellationError { return }
        catch let e as URLError where e.code == .cancelled { return }   // the page was left while loading
        catch { note = "No connection to the bot."; return }
        if r.status == 404 { unsupported = true; return }
        guard r.status == 200, let list = try? JSONDecoder().decode([String: [Item]].self, from: r.data)["messages"] else { return }
        unsupported = false; note = nil
        let fresh = Array(list.reversed())   // the server sends newest first; a chat reads oldest first
        if fresh != items { items = fresh }
        if list.contains(where: { $0.read_at == nil }) { _ = try? await BotAPI.raw("POST", "/inbox/read-all", body: Data("{}".utf8)) }
    }

    /// Returns false when the text was not sent (the caller puts it back in the composer).
    @discardableResult
    func send(_ text: String, replyTo: String? = nil) async -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return false }
        sending = true; defer { sending = false }
        let localID = "local-\(UUID().uuidString)"
        items.append(Item(id: localID, kind: "user", title: nil, body: t, actions: [], created_at: ISO8601DateFormatter().string(from: Date()),
                          read_at: nil, handled_at: nil, reply_to: replyTo))
        if pendingKey?.text != t || pendingKey?.replyTo != replyTo { pendingKey = ("mac-" + UUID().uuidString, t, replyTo) }
        var body: [String: Any] = ["text": t]
        if let replyTo { body["replyTo"] = replyTo }
        do {
            let r = try await Self.entry(body, key: pendingKey!.key)
            if r == 200 { pendingKey = nil; await load(); return true }
            items.removeAll { $0.id == localID }
            note = r == 404 ? "The server does not support this yet." : r == 409 ? "Still saving the last message, wait a moment." : "Could not send (\(r))."
        } catch {
            items.removeAll { $0.id == localID }
            note = "No connection. Your message was not sent; press Send to retry."
        }
        return false
    }

    /// POST /entry with an Idempotency-Key and a longer timeout (the coach may think for a while).
    /// BotAPI.raw (shared with the iPhone) takes no extra headers, so this one request is built here with the same token.
    private static func entry(_ json: [String: Any], key: String) async throws -> Int {
        guard let token = Keychain.loadOrImport(), let url = URL(string: BotAPI.base + "/entry") else { throw BotAPI.Err.noToken }
        var r = URLRequest(url: url, timeoutInterval: 60)
        r.httpMethod = "POST"
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.setValue(token, forHTTPHeaderField: "X-Token")
        r.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (_, resp) = try await URLSession.shared.data(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { NotificationCenter.default.post(name: BotAPI.tokenRejected, object: nil) }
        return status
    }

    func run(_ a: Item.Action, in it: Item) async {
        if a.id == "open" {
            if let u = a.url.flatMap(URL.init(string:)), u.scheme == "https" { NSWorkspace.shared.open(u) }
            return
        }
        guard !running.contains(it.id) else { return }
        running.insert(it.id); defer { running.remove(it.id) }
        // An answer choice: the label goes back as my reply to the question, the chips fold away.
        if a.id.hasPrefix("ch:") {
            markHandled(it.id)
            if !(await send(a.label, replyTo: it.id)) { unmarkHandled(it.id) }
            return
        }
        let body = try? JSONSerialization.data(withJSONObject: ["id": a.id])
        if let r = try? await BotAPI.raw("POST", "/actions", body: body), r.status == 200,
           let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any] {
            if let t = j["toast"] as? String, !t.isEmpty { ToastCenter.shared.show(t) }
            if j["ok"] as? Bool == true { markHandled(it.id) }
        } else { note = "That did not work." }
    }

    private func markHandled(_ id: String) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].handled_at = ISO8601DateFormatter().string(from: Date()) }
    }
    private func unmarkHandled(_ id: String) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].handled_at = nil }
    }
}

struct CoachView: View {
    @StateObject private var model = CoachModel()
    @State private var input = ""
    @State private var inputHeight: CGFloat = ChatInput.minHeight
    @State private var replyTo: CoachModel.Item?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Coach").font(.pageTitle).foregroundStyle(Theme.text)
                Spacer()
            }.coachColumn().padding(.top, 20).padding(.bottom, 8)
            conversation
        }
        .background(Theme.bg)
        .onChange(of: model.note) { _, n in
            guard let n else { return }
            Task { try? await Task.sleep(nanoseconds: 6_000_000_000); if model.note == n { model.note = nil } }
        }
        .task {
            await model.load()
            // Coach messages and the Mac agent's answers arrive on their own: look again while the page is open.
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 15_000_000_000); await model.load() }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.unsupported { EmptyState(icon: "tray", title: "The server is being updated") }
                    else if model.items.isEmpty {
                        EmptyState(icon: "bubble.left.and.bubble.right", title: "Say hello to your coach",
                                   detail: "Ask «what is due today?», log «кофе 18» or «съел 2 яйца».")
                    }
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { i, it in
                        if i == 0 || !sameDay(model.items[i - 1], it) { dayLabel(it) }
                        CoachRow(item: it, answered: model.items.contains { $0.kind == "user" && $0.reply_to == it.id }, quoted: it.reply_to.flatMap { r in model.items.first { $0.id == r } },
                                 reply: { replyTo = it },
                                 run: { a in
                                     if a.id.hasPrefix("ch:"), isOther(a.label) { replyTo = it } else { Task { await model.run(a, in: it) } }
                                 },
                                 jump: { id in withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(id, anchor: .center) } })
                            .id(it.id)
                    }
                    if model.sending { typing }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.vertical, 12).coachColumn()
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.items.count) { _, _ in
                if reduceMotion { proxy.scrollTo("end", anchor: .bottom) } else { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            .safeAreaBar(edge: .bottom) { composer.coachColumn().padding(.bottom, 14).padding(.top, 6) }
        }
    }

    /// "Другое…" / "Other…": write the answer yourself, quoting the question.
    private func isOther(_ label: String) -> Bool {
        let l = label.lowercased()
        return l.hasPrefix("другое") || l.hasPrefix("other")
    }

    private var composer: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                if let n = model.note {
                    Text(n).font(.meta).foregroundStyle(Theme.warn).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                }
                if let q = replyTo {
                    HStack(spacing: 10) {
                        Rectangle().fill(Theme.accent).frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.isMine ? "Reply to yourself" : "Reply to the coach").font(.chip).foregroundStyle(Theme.accent)
                            Text(q.body).font(.meta).foregroundStyle(Theme.muted).lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Button { replyTo = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Cancel reply").keyboardShortcut(.cancelAction)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .deskGlass(RoundedRectangle(cornerRadius: 14))
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ChatInput(text: $input, height: $inputHeight, onSend: send)
                        .frame(height: inputHeight)
                        .overlay(alignment: .topLeading) {
                            if input.isEmpty {
                                Text("Tell the coach…").font(.chatBody).foregroundStyle(Theme.muted)
                                    .padding(.leading, 8).padding(.top, 5).allowsHitTesting(false)
                            }
                        }
                    Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).frame(width: 18, height: 18) }
                        .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                        .disabled(model.sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Send (Return)").accessibilityLabel("Send")
                }
                .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 6)
                .deskGlass(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var typing: some View {
        HStack(spacing: 5) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Theme.muted).frame(width: 6, height: 6) } }
            .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
            .accessibilityLabel("The coach is typing")
    }

    private func sameDay(_ a: CoachModel.Item, _ b: CoachModel.Item) -> Bool {
        guard let x = a.date, let y = b.date else { return true }
        return Calendar.current.isDate(x, inSameDayAs: y)
    }

    private func dayLabel(_ it: CoachModel.Item) -> some View {
        Text(it.date.map { Calendar.current.isDateInToday($0) ? "Today" : Calendar.current.isDateInYesterday($0) ? "Yesterday" : $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
            .font(.sectionLabel).textCase(.uppercase).tracking(0.6).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity).padding(.top, 10)
    }

    private func send() {
        let t = input, q = replyTo
        guard !model.sending, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        input = ""; replyTo = nil
        Task {
            if !(await model.send(t, replyTo: q?.id)) {
                // Not sent: give the text and the quote back so Send retries with the same key.
                if input.isEmpty { input = t }
                if replyTo == nil { replyTo = q }
            }
        }
    }
}

/// One message: my bubble (accent), the coach's bubble (surface), or an opaque record card (spending, meal).
private struct CoachRow: View {
    let item: CoachModel.Item
    let answered: Bool   // some line of mine already replies to this message: its choice chips stay folded
    let quoted: CoachModel.Item?
    let reply: () -> Void
    let run: (CoachModel.Item.Action) -> Void
    let jump: (String) -> Void
    @State private var hover = false

    private var text: AttributedString {
        (try? AttributedString(markdown: item.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(item.body.replacingOccurrences(of: "\\[", with: "[").replacingOccurrences(of: "\\]", with: "]"))
    }

    var body: some View {
        let mine = item.isMine
        HStack(alignment: .center, spacing: 6) {
            if mine { Spacer(minLength: 80); replyButton }
            VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                if item.isRecord && !mine { card } else { bubble(mine) }
                if !item.isRecord, !item.buttons.isEmpty, !(answered && item.buttons.allSatisfy { $0.id.hasPrefix("ch:") }) { chips }
                if let d = item.date { Text(d.formatted(date: .omitted, time: .shortened)).font(.chip).foregroundStyle(Theme.muted) }
            }
            if !mine { replyButton; Spacer(minLength: 80) }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu {
            Button("Reply", action: reply)
            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.body, forType: .string) }
            ForEach(item.buttons.filter { $0.id.hasPrefix("x:") }, id: \.self) { a in Button(a.label) { run(a) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel((mine ? "You" : "Coach") + ": " + item.body)
        .accessibilityAction(named: "Reply", reply)
    }

    private var replyButton: some View {
        Button(action: reply) { Image(systemName: "arrowshape.turn.up.left").font(.system(size: 12)) }
            .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Reply")
            .opacity(hover && !item.id.hasPrefix("local-") ? 1 : 0).accessibilityHidden(true)
    }

    @ViewBuilder private var quote: some View {
        if let q = quoted {
            Button { jump(q.id) } label: {
                HStack(spacing: 6) {
                    Rectangle().fill(item.isMine ? Theme.onAccent.opacity(0.7) : Theme.accent).frame(width: 2)
                    Text(q.body).font(.meta).lineLimit(2).multilineTextAlignment(.leading)
                        .foregroundStyle(item.isMine ? Theme.onAccent.opacity(0.85) : Theme.muted)
                }.fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(.plain).help("Show the original")
        }
    }

    private func bubble(_ mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            quote
            if let t = item.title, !t.isEmpty, !mine { Text(t).font(.rowTitle).foregroundStyle(Theme.text) }
            Text(text).font(.chatBody).lineSpacing(2).foregroundStyle(mine ? Theme.onAccent : Theme.text).textSelection(.enabled)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(mine ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { if !mine { RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1) } }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            quote
            if let t = item.title, !t.isEmpty { Text(t).font(.rowTitle).foregroundStyle(Theme.text) }
            Text(text).font(.chatBody).foregroundStyle(Theme.text).textSelection(.enabled)
            if !item.buttons.isEmpty {
                FlowChips { ForEach(item.buttons, id: \.self) { a in
                    Button(a.label) { run(a) }.buttonStyle(QuietButton())
                } }
            }
        }
        .padding(12).frame(minWidth: 240, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }

    /// Answer choices and other buttons: floating glass controls under the bubble.
    private var chips: some View {
        GlassEffectContainer(spacing: 6) {
            FlowChips {
                ForEach(item.buttons, id: \.self) { a in
                    if a.style == "primary" { Button(a.label) { run(a) }.buttonStyle(.glassProminent) }
                    else { Button(a.label) { run(a) }.buttonStyle(.glass).tint(a.style == "danger" ? Theme.bad : nil) }
                }
            }
        }
    }
}

private extension View {
    func coachColumn() -> some View { padding(.horizontal, 28).frame(maxWidth: 720 + 56).frame(maxWidth: .infinity) }
}
