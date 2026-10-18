import AVFoundation
import SwiftUI

/// Today's Chinese cards: hear or read the word, pick the meaning, see the answer, repeat. Same daily session as the bot.
@MainActor
final class CardsModel: ObservableObject {
    struct Option: Decodable, Hashable { var text: String; var hint: String? }
    struct Reveal: Decodable { var front: String; var reading: String?; var meaning: String; var example: String? }
    struct Shadow: Decodable, Identifiable { var id: String; var text: String?; var pinyin: String? }
    struct State: Decodable {
        var state: String
        var pos: Int?; var total: Int?; var id: String?; var kind: String?
        var front: String?; var reading: String?; var q: String?
        var options: [Option]?
        var right: Int?; var shadow: [Shadow]?
    }
    struct Answer: Decodable { var correct: Bool; var reveal: Reveal; var next: State }

    @Published var current: State?
    @Published var last: Answer?      // answer shown until "Next"
    @Published var note: String?
    private var player: AVAudioPlayer?

    func load() async {
        guard let r = try? await LifeAPI.raw("GET", "/cards/session") else { note = L("No connection."); return }
        if r.status == 404 { note = L("The server is being updated."); return }
        guard r.status == 200, let s = try? JSONDecoder().decode(State.self, from: r.data) else { note = L("Could not load cards."); return }
        note = nil; current = s
        if s.kind == "word", let id = s.id { await speak(id, "front") }
    }

    func pick(_ o: Option) async {
        guard let id = current?.id, last == nil else { return }
        let body = try? JSONSerialization.data(withJSONObject: ["id": id, "choice": o.text])
        guard let r = try? await LifeAPI.raw("POST", "/cards/answer", body: body) else { note = L("No connection."); return }
        guard r.status == 200, let a = try? JSONDecoder().decode(Answer.self, from: r.data) else {
            if r.status == 409 { await load() } else { note = L("Could not save the answer.") }
            return
        }
        note = nil; last = a
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func next() async {
        guard let a = last else { return }
        current = a.next; last = nil
        if a.next.kind == "word", let id = a.next.id { await speak(id, "front") }
    }

    /// Audio comes as base64 mp3 in JSON.
    func speak(_ cardID: String, _ part: String) async {
        guard let r = try? await LifeAPI.raw("GET", "/cards/audio?id=\(cardID)&part=\(part)"), r.status == 200,
              let b64 = (try? JSONSerialization.jsonObject(with: r.data) as? [String: String])?["mp3"],
              let data = Data(base64Encoded: b64) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])   // a card must not stop the user's music
        player = try? AVAudioPlayer(data: data); player?.play()
    }
}

struct CardsScreen: View {
    @StateObject private var model = CardsModel()
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L("Cards")).font(.pageTitle).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 8)
                Button { adding = true } label: { Image(systemName: "plus.circle.fill").font(.system(size: 26)).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel(L("Add a word"))
                Button(L("Close")) { dismiss() }.padding(.leading, 6)
            }
            if let s = model.current { content(s) }
            else if let n = model.note { VStack(spacing: 10) { Text(n).foregroundStyle(Theme.muted); Button(L("Try again")) { Task { await model.load() } }.buttonStyle(QuietButton()) } }
            else { ProgressView() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 16).background(Theme.bg)
        .task { await model.load() }
        .sheet(isPresented: $adding) { AddCardSheet { Task { await model.load() } } }
    }

    @ViewBuilder private func content(_ s: CardsModel.State) -> some View {
        switch s.state {
        case "none": EmptyState(icon: "rectangle.stack", title: L("No cards for today"), detail: L("Add words in the Feed: «/card 请假 отпроситься»."))
        case "done": done(s)
        default: active(s)
        }
        if let n = model.note { Text(n).font(.meta).foregroundStyle(Theme.warn) }
    }

    private func active(_ s: CardsModel.State) -> some View {
        VStack(spacing: 14) {
            Text("\((s.pos ?? 0) + 1) / \(s.total ?? 0)").font(.meta).foregroundStyle(Theme.muted)
            if s.kind == "situation" { Text(s.q ?? "").font(.body13).multilineTextAlignment(.center).foregroundStyle(Theme.text) }
            else {
                Text(s.front ?? "").font(.system(size: 54, weight: .semibold)).foregroundStyle(Theme.text)
                Text(s.reading ?? "").font(.body13).foregroundStyle(Theme.muted)
                Button { Task { if let id = s.id { await model.speak(id, "front") } } } label: { Label("Listen", systemImage: "speaker.wave.2") }
                    .buttonStyle(QuietButton())
            }
            if let a = model.last {
                VStack(spacing: 6) {
                    Text(a.correct ? L("✅ Correct") : L("❌ Not quite")).font(.sectionLabel).foregroundStyle(a.correct ? Theme.accent : Theme.warn)
                    Text("\(a.reveal.front)  \(a.reveal.reading ?? "")").font(.body13).foregroundStyle(Theme.text)
                    Text(a.reveal.meaning).foregroundStyle(Theme.muted)
                    if let e = a.reveal.example { Text(e).font(.meta).foregroundStyle(Theme.muted) }
                }.multilineTextAlignment(.center)
                Button("Next") { Task { await model.next() } }.buttonStyle(PrimaryButton())
            } else {
                ForEach(s.options ?? [], id: \.self) { o in
                    Button { Task { await model.pick(o) } } label: {
                        VStack { Text(o.text); if let h = o.hint { Text(h).font(.meta).foregroundStyle(Theme.muted) } }.frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(QuietButton())
                }
            }
        }
    }

    private func done(_ s: CardsModel.State) -> some View {
        VStack(spacing: 12) {
            Text("🃏 \(s.right ?? 0) of \(s.total ?? 0)").font(.pageTitle).foregroundStyle(Theme.text)
            Text("Done for today. See you tomorrow.").foregroundStyle(Theme.muted)
            ForEach(s.shadow ?? []) { sh in
                VStack(spacing: 2) {
                    Button { Task { await model.speak(sh.id, "example") } } label: { Label(sh.text ?? "", systemImage: "speaker.wave.2") }
                    Text(sh.pinyin ?? "").font(.meta).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

/// /card in the bot: a new word goes into the next session.
struct AddCardSheet: View {
    var added: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var front = ""
    @State private var reading = ""
    @State private var meaning = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("汉字 / phrase", text: $front)
                TextField("Pinyin (optional)", text: $reading).textInputAutocapitalization(.never)
                TextField("Meaning", text: $meaning)
                if let error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Add a word").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(front.trimmingCharacters(in: .whitespaces).isEmpty || meaning.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }

    private func save() async {
        var body: [String: Any] = ["front": front.trimmingCharacters(in: .whitespaces), "meaning": meaning.trimmingCharacters(in: .whitespaces)]
        if !reading.trimmingCharacters(in: .whitespaces).isEmpty { body["reading"] = reading.trimmingCharacters(in: .whitespaces) }
        let data = try? JSONSerialization.data(withJSONObject: body)
        if let r = try? await LifeAPI.raw("POST", "/cards", body: data), r.status == 200 { added(); dismiss() } else { error = L("Could not save the word.") }
    }
}
