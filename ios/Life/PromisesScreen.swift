import SwiftUI

/// Promises to friends: what I promised, what friends promised me, and a short form to give my word.
@MainActor
final class PromisesModel: ObservableObject {
    struct Item: Decodable, Identifiable {
        var id: String; var title: String; var due: String; var status: String; var kind: String
        var penalty: String?; var from: String; var to: String
    }
    struct Friend: Decodable, Identifiable, Hashable { var id: String; var name: String }
    struct List: Decodable { var mine: [Item]; var toMe: [Item]; var friends: [Friend]; var today: String }

    @Published var list: List?
    @Published var note: String?

    func load() async {
        guard let r = try? await LifeAPI.raw("GET", "/promises") else { note = L("No connection."); return }
        guard r.status == 200, let l = try? JSONDecoder().decode(List.self, from: r.data) else {
            note = r.status == 404 ? L("The server is being updated.") : L("Could not load promises."); return
        }
        note = nil; list = l
    }

    func create(to: String, title: String, due: String, kind: String) async -> Bool {
        let body = try? JSONSerialization.data(withJSONObject: ["to": to, "title": title, "due": due, "kind": kind])
        guard let r = try? await LifeAPI.raw("POST", "/promises", body: body) else { note = L("No connection."); return false }
        guard r.status == 200, let l = try? JSONDecoder().decode(List.self, from: r.data) else { note = L("Could not save (\(r.status))."); return false }
        note = nil; list = l; return true
    }

    func act(_ id: String) async {
        let body = try? JSONSerialization.data(withJSONObject: ["id": id])
        if let r = try? await LifeAPI.raw("POST", "/actions", body: body), r.status == 200,
           let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any], let t = j["toast"] as? String { Toasts.shared.show(t) }
        await load()
    }
}

struct PromisesScreen: View {
    @StateObject private var model = PromisesModel()
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Promises").font(.pageTitle).foregroundStyle(Theme.text)
                Spacer()
                Button("Close") { dismiss() }
            }
            if let n = model.note { Text(n).font(.meta).foregroundStyle(Theme.warn) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let l = model.list {
                        Button { adding = true } label: { Label("Give my word", systemImage: "hand.raised").frame(maxWidth: .infinity).padding(.vertical, 4) }
                            .buttonStyle(PrimaryButton()).disabled(l.friends.isEmpty)
                        if l.friends.isEmpty { Text("Add a friend first: promises are made to someone in your circle.").font(.meta).foregroundStyle(Theme.muted) }
                        section(L("I promised"), l.mine.filter { $0.status == "open" }, mine: true)
                        section(L("Promised to me"), l.toMe.filter { $0.status == "open" }, mine: false)
                        history(l.mine + l.toMe)
                        if l.mine.isEmpty && l.toMe.isEmpty { Group2 { EmptyState(icon: "hand.raised", title: L("No promises yet"), detail: L("Give your word to a friend: the app keeps score and asks them to confirm.")) } }
                    } else if model.note != nil { Button(L("Try again")) { Task { await model.load() } }.buttonStyle(QuietButton()) } else { ProgressView() }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 16).background(Theme.bg)
        .task { await model.load() }
        .sheet(isPresented: $adding) { NewPromiseSheet(model: model) }
    }

    @ViewBuilder private func section(_ title: String, _ items: [PromisesModel.Item], mine: Bool) -> some View {
        if !items.isEmpty {
            Text(title).font(.sectionLabel).textCase(.uppercase).tracking(0.6).foregroundStyle(Theme.muted)
            ForEach(items) { p in
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.title).font(.body13).foregroundStyle(Theme.text)
                    Text("\(mine ? L("to \(p.to)") : L("from \(p.from)")) · \(L("due \(p.due)"))").font(.meta).foregroundStyle(Theme.muted)
                    HStack {
                        if mine { Button("Cancel") { Task { await model.act("prx:\(p.id)") } }.buttonStyle(QuietButton()) }
                        else if p.due <= (model.list?.today ?? "") {
                            Button("Kept") { Task { await model.act("pry:\(p.id)") } }.buttonStyle(QuietButton())
                            Button("Not kept") { Task { await model.act("prn:\(p.id)") } }.buttonStyle(QuietButton())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder private func history(_ all: [PromisesModel.Item]) -> some View {
        let done = all.filter { $0.status != "open" }.prefix(10)
        if !done.isEmpty {
            Text("History").font(.sectionLabel).textCase(.uppercase).tracking(0.6).foregroundStyle(Theme.muted)
            ForEach(Array(done)) { p in
                Text("\(icon(p.status)) \(p.title) · \(p.from) → \(p.to)\(p.penalty.map { " · \($0)" } ?? "")").font(.meta).foregroundStyle(Theme.muted)
            }
        }
    }
    private func icon(_ s: String) -> String { s == "kept" ? "✅" : s == "broken" ? "❌" : "◦" }
}

struct NewPromiseSheet: View {
    @ObservedObject var model: PromisesModel
    @Environment(\.dismiss) private var dismiss
    @State private var friend: String = ""
    @State private var title = ""
    @State private var due = Date()
    @State private var bySleep = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("To", selection: $friend) { ForEach(model.list?.friends ?? []) { Text($0.name).tag($0.id) } }
                TextField("I promise to…", text: $title, axis: .vertical)
                DatePicker("By", selection: $due, in: Date()..., displayedComponents: .date)
                Picker("Checked by", selection: $bySleep) { Text("Friend's word").tag(false); Text("Sleep data").tag(true) }
            }
            .navigationTitle("Give my word").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(busy || friend.isEmpty || title.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
            .onAppear { if friend.isEmpty { friend = model.list?.friends.first?.id ?? "" } }
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        if await model.create(to: friend, title: title.trimmingCharacters(in: .whitespaces), due: f.string(from: due), kind: bySleep ? "sleep" : "friend") { dismiss() }
    }
}
