import SwiftUI

/// Under an answer: which files the agent changed, with the diff, and Keep / Revert.
struct ChangesCard: View {
    let changes: ChangeSet
    let keep: () -> Void
    let revert: () -> Void
    @State private var open: Set<String> = []

    private var touchedBot: Bool {
        changes.files.contains {
            let p = $0.path.split(separator: "/").map(String.init)
            return p.first == "resources" && (p.last == "assignments.md" || p.last == "exam-dates.md")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape").foregroundStyle(Theme.muted)
                Text("Changed \(changes.files.count) file\(changes.files.count == 1 ? "" : "s")")
                    .font(.rowTitle).foregroundStyle(Theme.text)
                switch changes.state {
                case .kept: Chip(text: "Kept", tone: .good)
                case .reverted: Chip(text: "Reverted", tone: .neutral)
                case .pending: EmptyView()
                }
                Spacer()
                if changes.state == .pending && !changes.files.isEmpty {
                    Button("Keep", action: keep).buttonStyle(QuietButton())
                    Button("Revert", action: revert).buttonStyle(PrimaryButton())
                        .disabled(!changes.files.contains { $0.revertible })
                }
            }
            ForEach(changes.files) { f in
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        if open.contains(f.path) { open.remove(f.path) } else { open.insert(f.path) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: open.contains(f.path) ? "chevron.down" : "chevron.right").font(.meta).foregroundStyle(Theme.muted)
                            Text(f.path).font(.chatCode).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                            Chip(text: f.status.rawValue, tone: f.status == .deleted ? .bad : (f.status == .added ? .good : .accent))
                            if !f.revertible { Chip(text: "no copy", tone: .warn) }
                            Spacer()
                        }
                    }.buttonStyle(.plain)
                    if open.contains(f.path) {
                        ScrollView(.horizontal) {
                            Text(f.diff.isEmpty ? "(no text diff)" : f.diff)
                                .font(.chatCode).foregroundStyle(Theme.text)
                                .textSelection(.enabled).padding(8)
                        }
                        .frame(maxHeight: 220)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            if !changes.outside.isEmpty {
                Text("Also changed outside the allowed list: \(changes.outside.joined(separator: ", ")). Check these files.")
                    .font(.meta).foregroundStyle(Theme.warn)
            }
            if changes.truncated {
                Text("Long diffs are cut here. Open the file to see everything before you keep the change.")
                    .font(.meta).foregroundStyle(Theme.warn)
            }
            if touchedBot && changes.state == .pending {
                Text("Deadlines changed. Review them, then Keep; only then send them to the bot with life_sync.")
                    .font(.meta).foregroundStyle(Theme.muted)
            } else if touchedBot && changes.state == .kept {
                HStack(spacing: 8) {
                    Text("Kept. Run life_sync to send the deadlines to the bot.").font(.meta).foregroundStyle(Theme.muted)
                    Button("Open Sync") { Router.shared.page = .sync }.buttonStyle(QuietButton())
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }
}
