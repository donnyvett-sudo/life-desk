import SwiftUI
import UIKit

/// Feed: one conversation with the coach. Everything it sent (morning, evening, reminders, penalties) and everything
/// you wrote or said lands here in order, and the buttons on its messages work.
@MainActor
final class FeedModel: ObservableObject {
    struct Item: Identifiable, Decodable, Equatable {
        struct Action: Decodable, Hashable { var id: String; var label: String; var style: String?; var url: String? }
        var id: String
        var kind: String
        var title: String?
        var body: String
        var actions: [Action]
        var created_at: String
        var read_at: String?
        var handled_at: String?
        var reply_to: String?
        var isMine: Bool { kind == "user" }
        private static let isoFraction: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
        private static let isoPlain = ISO8601DateFormatter()
        var date: Date? {
            return Self.isoFraction.date(from: created_at) ?? Self.isoPlain.date(from: created_at)
        }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var sending = false
    @Published var note: String?
    @Published private(set) var unsupported = false
    @Published private(set) var loaded = false   // the first load finished: until then no "say hello" empty state
    private var running = Set<String>()   // buttons being processed: no double taps
    private var sendKey = ""
    private var sendKeyText: String?

    func load() async {
        defer { loaded = true }
        let r: (status: Int, data: Data)
        do { r = try await BotAPI.raw("GET", "/inbox?limit=80") }
        catch is CancellationError { return }
        catch { note = L("No connection."); return }
        if r.status == 404 { unsupported = true; return }
        guard r.status == 200, let list = try? JSONDecoder().decode([String: [Item]].self, from: r.data)["messages"] else { return }
        note = nil
        let fresh = Array(list.reversed())
        if fresh != items { items = fresh }   // the server sends newest first; a chat reads oldest first. An unchanged poll must not redraw
        if list.contains(where: { $0.read_at == nil }) { _ = try? await BotAPI.raw("POST", "/inbox/read-all", body: Data("{}".utf8)) }
    }

    /// `replyTo`: the inbox id of the message this line answers; the server gives it to the coach as context.
    @discardableResult
    func send(_ text: String, replyTo: String? = nil) async -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return false }
        sending = true; defer { sending = false }
        // Show my line at once; the server's copy replaces it on the reload.
        let localID = "local-\(UUID().uuidString)"
        items.append(Item(id: localID, kind: "user", body: t, actions: [], created_at: ISO8601DateFormatter().string(from: Date()), read_at: nil, handled_at: nil, reply_to: replyTo))
        var payload = ["text": t]
        if let replyTo { payload["replyTo"] = replyTo }
        let body = try? JSONSerialization.data(withJSONObject: payload)
        let keyText = t + "\u{1F}" + (replyTo ?? "")   // the same line answering another message is a new message
        do {
            if sendKeyText != keyText { sendKey = "fd-" + UUID().uuidString; sendKeyText = keyText }
            let r = try await LifeAPI.raw("POST", "/entry", body: body, idempotencyKey: sendKey, timeout: 60)
            if r.status == 200 { sendKeyText = nil; await load(); return true }
            items.removeAll { $0.id == localID }; note = r.status == 404 ? L("The server does not support this yet.") : r.status == 409 ? L("Still saving the last message, wait a moment.") : L("Could not send (\(r.status)).")
            return false
        } catch { items.removeAll { $0.id == localID }; note = L("No connection. Your message was not sent; tap send to retry."); return false }
    }

    /// Queues a question for the Mac agent; the answer arrives in the Feed when Life Desk has run it.
    func askMac(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return }
        sending = true; defer { sending = false }
        let body = try? JSONSerialization.data(withJSONObject: ["prompt": t])
        do {
            let r = try await LifeAPI.raw("POST", "/agent/jobs", body: body)
            switch r.status {
            case 200: await load(); note = L("Sent to your Mac. It answers while Life Desk is open there.")
            case 403: note = L("Reconnect this iPhone with a new code from Life Desk to use the Mac agent.")
            case 404: note = L("The server does not support this yet.")
            case 429: note = L("Too many open questions. Wait for the Mac.")
            default: note = L("Could not send (\(r.status)).")
            }
        } catch { note = L("No connection. Your question was not sent.") }
    }

    func run(_ a: Item.Action, in it: Item) async {
        // An answer to a coach question goes back as my next line; the reply hides the choices (see `answered`).
        if a.id.hasPrefix("ch:") { await send(a.label, replyTo: it.id); return }
        if a.id == "open", let u = a.url.flatMap(URL.init(string:)), u.scheme == "https" { await UIApplication.shared.open(u); return }
        let body = try? JSONSerialization.data(withJSONObject: ["id": a.id])
        guard !running.contains(it.id) else { return }
        running.insert(it.id); defer { running.remove(it.id) }
        if let r = try? await LifeAPI.raw("POST", "/actions", body: body), r.status == 200,
           let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any] {
            if let t = j["toast"] as? String, !t.isEmpty { Toasts.shared.show(t) }
            if j["ok"] as? Bool == true, let i = items.firstIndex(where: { $0.id == it.id }) { items[i].handled_at = ISO8601DateFormatter().string(from: Date()) }
        } else { note = L("That did not work.") }
    }

    /// A question is settled once I replied to it (the local bubble counts, so the chips fold at once).
    func answered(_ it: Item) -> Bool { items.contains { $0.isMine && $0.reply_to == it.id } }
    func item(_ id: String?) -> Item? { id.flatMap { id in items.first { $0.id == id } } }
}

struct FeedScreen: View {
    var onDisconnect: () -> Void = {}
    @StateObject private var model = FeedModel()
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var toMac = false
    @State private var replyTo: FeedModel.Item?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.unsupported { EmptyState(icon: "tray", title: L("The server is being updated")) }
                    else if !model.loaded { ProgressView().frame(maxWidth: .infinity).padding(.top, 60) }
                    else if model.items.isEmpty { EmptyState(icon: "bubble.left.and.bubble.right", title: L("Say hello to your coach"), detail: L("Ask «what is due today?», log «кофе 18» or «съел 2 яйца».")) }
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { i, it in
                        if i == 0 || !sameDay(model.items[i - 1], it) { dayLabel(it) }
                        bubble(it, proxy: proxy).id(it.id)
                    }
                    if model.sending { typing }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            // Dragging or tapping the conversation puts the keyboard away: it is the way back to the tab bar.
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded { focused = false })
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaBar(edge: .top, spacing: 0) { header }
            .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar(proxy) }
            .onChange(of: model.items.count) { _, _ in scroll(proxy, to: "end", anchor: .bottom) }
            .onChange(of: focused) { _, _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { proxy.scrollTo("end", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
        .background(Theme.bg)
        // With the keyboard up the tab bar is not reachable anyway: hide it, and the bar's chevron is the visible way out.
        .toolbar(focused ? .hidden : .visible, for: .tabBar)
        .onDisappear { focused = false }
        .onChange(of: model.note) { _, n in
            guard let n else { return }
            Task { try? await Task.sleep(nanoseconds: 6_000_000_000); if model.note == n { model.note = nil } }
        }
        .task {
            await model.load()
            // The Mac's answers and the coach's messages arrive on their own: look again while the Feed is open.
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 15_000_000_000); await model.load() }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String, anchor: UnitPoint) {
        if reduceMotion { proxy.scrollTo(id, anchor: anchor) } else { withAnimation { proxy.scrollTo(id, anchor: anchor) } }
    }

    private func bottomBar(_ proxy: ScrollViewProxy) -> some View {
        GlassEffectContainer(spacing: 8) { VStack(spacing: 6) {
            if let n = model.note {
                Text(n).font(.meta).foregroundStyle(Theme.warn).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.surface, in: Capsule()).frame(maxWidth: .infinity, alignment: .leading)
            }
            if toMac {
                HStack(spacing: 6) {
                    Image(systemName: "desktopcomputer")
                    Text(L("Asking the agent on your Mac")).font(.meta)
                    Spacer()
                    Button { toMac = false } label: { Label(L("Back to the coach"), systemImage: "xmark.circle.fill").labelStyle(.titleAndIcon).font(.meta).frame(minHeight: 44) }
                }
                .foregroundStyle(Theme.accent).padding(.horizontal, 14).glassCapsule(tint: Theme.accent)
            }
            if let q = replyTo, !toMac {
                QuoteBar(original: q, onTap: { scroll(proxy, to: q.id, anchor: .center) }, onCancel: { replyTo = nil })
            }
            inputBar
        } }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var header: some View {
        HStack {
            Text("Feed").font(.pageTitle).foregroundStyle(Theme.text)
            Spacer()
            Button { Navigator.shared.go(.promises) } label: { Label("Promises", systemImage: "hand.raised") }.buttonStyle(QuietButton())
            Button { Navigator.shared.go(.account) } label: { Image(systemName: "person.crop.circle").font(.system(size: 22)).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Account")
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    private func sameDay(_ a: FeedModel.Item, _ b: FeedModel.Item) -> Bool {
        guard let x = a.date, let y = b.date else { return true }
        return Calendar.current.isDate(x, inSameDayAs: y)
    }

    private func dayLabel(_ it: FeedModel.Item) -> some View {
        Text(it.date.map { Calendar.current.isDateInToday($0) ? L("Today") : $0.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLanguage.locale)) } ?? "")
            .font(.sectionLabel).textCase(.uppercase).tracking(0.6).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity).padding(.top, 10)
    }

    private func reply(to it: FeedModel.Item, prefill: String? = nil) {
        toMac = false; replyTo = it
        if let prefill, !text.hasPrefix(prefill) { text = prefill + text }
        // After the conversation's own tap gesture, which puts the keyboard away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
    }

    private func bubble(_ it: FeedModel.Item, proxy: ScrollViewProxy) -> some View {
        let mine = it.isMine
        let fg = mine ? Theme.onAccent : Theme.text
        let content = VStack(alignment: .leading, spacing: 6) {
            if let o = model.item(it.reply_to) { QuoteLine(original: o, mine: mine) { scroll(proxy, to: o.id, anchor: .center) } }
            if let t = it.title, !t.isEmpty { Text(t).font(.rowTitle).foregroundStyle(fg) }
            MessageText(item: it, color: fg)
        }
        return VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            Group {
                if let r = it.record {
                    // Records are content, so an opaque card with the area's colour, not glass.
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: r.icon).font(.system(size: 18)).foregroundStyle(r.color).frame(width: 24).accessibilityHidden(true)
                        content
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
                } else {
                    content.padding(.horizontal, 12).padding(.vertical, 9)
                        .background(mine ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay { if !mine { RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1) } }
                }
            }
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14))
            .contextMenu { menu(it) }
            .swipeToReply { reply(to: it) }
            if !mine, it.handled_at == nil, !it.actions.isEmpty {
                if it.isChoice {
                    if !model.answered(it) {
                        ChoiceChips(actions: it.actions.filter { $0.id.hasPrefix("ch:") },
                                    choose: { a in Task { await model.run(a, in: it) } },
                                    other: { reply(to: it) })
                    }
                } else {
                    ActionChips(actions: it.actions) { a in Task { await model.run(a, in: it) } }
                }
            }
            if let d = it.date { Text(d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.locale))).font(.chip).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(mine ? .leading : .trailing, it.record == nil ? 44 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel((mine ? L("You") : L("Coach")) + ": " + [it.title, it.plain].compactMap { $0 }.joined(separator: ". "))
        .accessibilityAction(named: L("Reply")) { reply(to: it) }
    }

    @ViewBuilder private func menu(_ it: FeedModel.Item) -> some View {
        Button { reply(to: it) } label: { Label(L("Reply"), systemImage: "arrowshape.turn.up.left") }
        Button { UIPasteboard.general.string = it.plain } label: { Label(L("Copy"), systemImage: "doc.on.doc") }
        if !it.isMine {
            Button { reply(to: it, prefill: L("Fix: ")) } label: { Label(L("Fix…"), systemImage: "pencil") }
        }
        if !it.isMine, it.handled_at == nil, let u = it.undo {
            Button(role: .destructive) { Task { await model.run(u, in: it) } } label: { Label(L("Undo"), systemImage: "arrow.uturn.backward") }
        }
    }

    private var typing: some View {
        HStack(spacing: 5) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Theme.muted).frame(width: 6, height: 6) } }
            .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14)).accessibilityLabel("The coach is typing")
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Button { toMac.toggle() } label: { Image(systemName: toMac ? "desktopcomputer.circle.fill" : "desktopcomputer").font(.system(size: 20)).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel(toMac ? L("Asking the Mac agent") : L("Ask the Mac agent instead"))
            TextField(toMac ? L("Ask the agent on your Mac…") : L("Tell the coach…"), text: $text, axis: .vertical).lineLimit(1...4).focused($focused)
                .padding(.vertical, 11)
                .submitLabel(.send).onSubmit { send() }
                .onChange(of: toMac) { _, _ in focused = true }
            if focused {
                Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down").font(.system(size: 20)).frame(minWidth: 40, minHeight: 44) }
                    .accessibilityLabel(L("Hide keyboard"))
            }
            Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).frame(minWidth: 44, minHeight: 44) }
                .disabled(model.sending || text.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityLabel("Send")
        }
        .padding(.horizontal, 4)
        // A capsule at one line; rounded rather than pill-shaped once the text grows to four.
        .glassRounded(22)
    }

    private func send() {
        let t = text, pending = replyTo
        text = ""
        if !toMac { replyTo = nil }
        Task {
            if toMac { await model.askMac(t); return }
            // A failed send gives the line and its quote back instead of losing them.
            if await !model.send(t, replyTo: pending?.id), text.isEmpty { text = t; replyTo = pending }
        }
    }
}
