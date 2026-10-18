import SwiftUI
import AppKit

/// Left column of the Agent page: chat list with search, rename and delete.
struct ChatListPanel: View {
    @ObservedObject var model: ChatModel
    @State private var query = ""
    @State private var renaming: UUID?
    @State private var draft = ""
    @State private var deleting: UUID?

    private var shown: [ChatState] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.sorted.filter { !$0.messages.isEmpty || $0.id == model.currentID } }
        return model.sorted.filter { c in
            c.title.lowercased().contains(q) || c.messages.contains { $0.text.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Chats").font(.sectionLabel).foregroundStyle(Theme.muted).textCase(.uppercase)
                Spacer()
                Button { model.newChat() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).help("New chat")
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.meta).foregroundStyle(Theme.muted)
                TextField("Search chats", text: $query).textFieldStyle(.plain).font(.body13)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(shown) { c in row(c) }
                    if shown.isEmpty { Text("No chats found").font(.meta).foregroundStyle(Theme.muted).padding(8) }
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 12)
        .frame(width: 236)
        .background(Theme.sidebar.opacity(0.55))
        .confirmationDialog("Delete this chat?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let id = deleting { model.delete(id) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("The conversation is removed from this list. This can’t be undone.") }
    }

    @ViewBuilder private func row(_ c: ChatState) -> some View {
        let selected = c.id == model.currentID
        HStack(spacing: 8) {
            if renaming == c.id {
                TextField("Title", text: $draft)
                    .textFieldStyle(.plain).font(.body13)
                    .onSubmit { model.rename(c.id, to: draft); renaming = nil }
                    .onExitCommand { renaming = nil }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title.isEmpty ? "New chat" : c.title).font(.body13).lineLimit(1)
                        .foregroundStyle(Theme.text)
                    Text(c.messages.isEmpty ? "Empty" : Self.relative(c.updated)).font(.chip).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                if model.runningIDs.contains(c.id) { ProgressView().controlSize(.mini).scaleEffect(0.7) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { if renaming != c.id { model.select(c.id) } }
        .contextMenu {
            Button("Rename") { draft = c.title; renaming = c.id }
            Button("Delete", role: .destructive) { deleting = c.id }
        }
    }

    private static func relative(_ d: Date) -> String {
        if abs(d.timeIntervalSinceNow) < 60 { return "Just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
