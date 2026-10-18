import SwiftUI
import Speech
import AVFoundation

/// "потратил 35 на обед": typed or dictated (on-device Russian speech recognition), sent to the quick-entry function.
@MainActor
final class QuickEntryModel: ObservableObject {
    @Published var text = ""
    @Published var reply: String?
    private var entryKey = ""
    private var entryKeyText: String?
    @Published var listening = false
    @Published var busy = false
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggleListening() {
        if listening { stopListening() } else { Task { await startListening() } }
    }

    private func startListening() async {
        let ok = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        guard ok, let recognizer, recognizer.isAvailable else { reply = L("Speech recognition is not available."); return }
        guard await AVAudioApplication.requestRecordPermission() else { reply = L("Microphone access is off."); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
            engine.prepare()
            try engine.start()
            listening = true
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.text = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.stopListening() }
                }
            }
        } catch {
            reply = L("Could not start recording.")
            stopListening()
        }
    }

    /// A meal photo: the server answers with the meal card text (calories, macros).
    func sendPhoto(_ jpeg: Data) async {
        busy = true; reply = nil; defer { busy = false }
        let body = try? JSONSerialization.data(withJSONObject: ["image": jpeg.base64EncodedString()])
        do {
            let r = try await LifeAPI.raw("POST", "/meals/photo", body: body)
            if r.status == 200 { reply = Self.render(r.data) ?? L("Saved.") }
            else if r.status == 404 { reply = L("The server does not support meal photos yet.") }
            else if r.status == 413 { reply = L("The photo is too large.") }
            else { reply = L("Server answered \(r.status).") }
        } catch { reply = L("No connection.") }
    }

    func stopListening() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        listening = false
    }

    /// What the server's /entry answered: messages in order, an edit replaces the message with the same id.
    nonisolated static func render(_ data: Data) -> String? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = j["messages"] as? [[String: Any]] else { return nil }
        var order: [Int] = []
        var bodies: [Int: String] = [:]
        for m in list {
            guard let id = m["id"] as? Int, let b = m["body"] as? String else { continue }
            if bodies[id] == nil { order.append(id) }
            bodies[id] = b
        }
        let out = order.compactMap { bodies[$0] }.joined(separator: "\n\n")
        return out.isEmpty ? nil : out
    }

    func send() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        stopListening()
        busy = true; reply = nil; defer { busy = false }
        do {
            // The app route first (every kind of phrase, answers like the bot); the old function while the server lacks it.
            let body = try? JSONSerialization.data(withJSONObject: ["text": t])
            // Same phrase, same key until it succeeds: a retry after a lost answer never saves it twice.
            if entryKeyText != t { entryKey = "qe-" + UUID().uuidString; entryKeyText = t }
            let a = try await LifeAPI.raw("POST", "/entry", body: body, idempotencyKey: entryKey, timeout: 60)
            if a.status == 200, let text = Self.render(a.data) {
                reply = text; self.text = ""; entryKeyText = nil
                return
            }
            // The old function only when the route does not exist yet; any other failure may already have saved the entry.
            if a.status != 404 {
                reply = a.status == 200 ? L("Saved.") : a.status == 409 ? L("Still saving, wait a moment.") : a.status == 403 ? L("This token cannot do quick entry. Pair again with a code.") : L("Could not save. Try again.")
                if a.status == 200 { self.text = ""; entryKeyText = nil }
                return
            }
            let r = try await LifeAPI.functionPost("quick-entry", json: ["text": t])
            let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any]
            reply = (j?["reply"] as? String) ?? (r.status == 200 ? L("Saved.") : r.status == 403 ? L("This token cannot do quick entry (it needs the ingest scope). Pair again with a code.") : L("Server answered \(r.status)."))
            if r.status == 200 { text = "" }
        } catch LifeAPI.Err.noToken {
            reply = L("Not connected.")
        } catch {
            reply = L("No connection.")
        }
    }
}

struct QuickEntrySheet: View {
    var onDisconnect: () -> Void = {}
    @StateObject private var model = QuickEntryModel()
    @State private var confirmDisconnect = false
    @State private var camera = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick entry").font(.pageTitle).foregroundStyle(Theme.text)
            Text("Say or type: «потратил 35 на обед», «кофе 18», «перевёл 500 с карты на карту».")
                .font(.body13).foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                TextField("What happened?", text: $model.text, axis: .vertical)
                    .lineLimit(1...3).focused($focused)
                    .padding(12).background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                Button { model.toggleListening() } label: {
                    Image(systemName: model.listening ? "stop.circle.fill" : "mic.circle.fill").font(.system(size: 38))
                        .foregroundStyle(model.listening ? Theme.bad : Theme.accent)
                }.accessibilityLabel(model.listening ? L("Stop dictation") : L("Dictate"))
            }
            HStack(spacing: 12) {
                Button { Task { await model.send() } } label: { Text(model.busy ? L("Saving…") : L("Save")).frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButton())
                    .disabled(model.busy || model.text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(model.busy || model.text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                Button { camera = true } label: { Label("Meal photo", systemImage: "camera") }
                    .buttonStyle(QuietButton()).disabled(model.busy)
            }
            if let r = model.reply { Text(r).font(.body13).foregroundStyle(Theme.text).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 10)) }
            Spacer()
        }
        .padding(20).background(Theme.bg)
        .sheet(isPresented: $camera) { CameraPicker { data in Task { await model.sendPhoto(data) } } }
        .onAppear { focused = true }
        .onDisappear { model.stopListening() }
        .presentationDetents([.medium, .large])
    }
}
