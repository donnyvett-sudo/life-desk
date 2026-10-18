import SwiftUI
import AppKit

func chatCopy(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

/// Small "copy" button that flips to a check mark for a moment.
struct ChatCopyButton: View {
    let text: String
    @State private var done = false
    var body: some View {
        Button {
            chatCopy(text)
            done = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { done = false }
        } label: {
            Label(done ? "Copied" : "Copy", systemImage: done ? "checkmark" : "doc.on.doc")
                .font(.chip).labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain).foregroundStyle(done ? Theme.good : Theme.muted).help("Copy")
    }
}

/// Assistant reply: fenced code blocks get a box with a copy button, the rest is Markdown typeset with the app fonts.
struct ChatMarkdown: View {
    let text: String

    static func inline(_ s: String) -> AttributedString {
        var a = MarkdownView.inline(s)
        for r in Array(a.runs) where r.inlinePresentationIntent?.contains(.code) == true {
            a[r.range].font = .chatCode
            a[r.range].backgroundColor = Theme.surface2
        }
        return a
    }

    /// "**Deadlines this week:**" → "Deadlines this week"; nil when the paragraph is anything else.
    static func boldHeading(_ t: String) -> String? {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("**"), s.hasSuffix("**"), s.count > 4, !s.contains("\n") else { return nil }
        let inner = String(s.dropFirst(2).dropLast(2))
        guard !inner.contains("**") else { return nil }
        return inner.trimmingCharacters(in: CharacterSet(charactersIn: ": ")) 
    }

    var body: some View {
        let blocks = Array(ChatBlock.split(text).enumerated())
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks, id: \.offset) { _, b in
                switch b {
                case .markdown(let s): markdown(s)
                case .code(let lang, let body): codeBox(lang, body)
                }
            }
        }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdown(_ s: String) -> some View {
        let nodes = Array(MarkdownView.parse(s).enumerated())
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(nodes, id: \.offset) { _, n in node(n) }
        }
    }

    @ViewBuilder private func node(_ n: MarkdownView.Node) -> some View {
        switch n {
        case .heading(let level, let t):
            Text(Self.inline(t)).font(level == 1 ? .chatH1 : level == 2 ? .chatH2 : .chatH3)
                .foregroundStyle(Theme.text).padding(.top, level <= 2 ? 8 : 4)
        case .item(let depth, let marker, let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).monospacedDigit().foregroundStyle(Theme.muted).frame(minWidth: 14, alignment: .trailing)
                Text(Self.inline(t)).lineSpacing(3)
            }.font(.chatBody).foregroundStyle(Theme.text).padding(.leading, CGFloat(depth) * 18)
        case .quote(let t):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.6)).frame(width: 3)
                Text(Self.inline(t)).lineSpacing(3).foregroundStyle(Theme.muted)
            }.font(.chatBody).fixedSize(horizontal: false, vertical: true)
        case .code(let c): codeBox("", c)
        case .paragraph(let t):
            if let head = Self.boldHeading(t) {
                // A paragraph that is one bold phrase is a section title in the model's habit: set it off as such.
                Text(Self.inline(head)).font(.chatH3).foregroundStyle(Theme.text).padding(.top, 8)
            } else {
                Text(Self.inline(t)).font(.chatBody).lineSpacing(4).foregroundStyle(Theme.text)
            }
        case .table(let t): table(t)
        }
    }

    private func table(_ t: MarkdownTables.Table) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(t.rawHeader.enumerated()), id: \.offset) { _, h in
                        Text(Self.inline(h)).font(.meta.weight(.semibold)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: 360, alignment: .leading)
                    }
                }.background(Theme.surface2)
                ForEach(Array(t.rawRows.enumerated()), id: \.offset) { _, row in
                    Hairline()
                    GridRow {
                        ForEach(Array(row.prefix(t.rawHeader.count).enumerated()), id: \.offset) { _, c in
                            Text(Self.inline(c)).font(.body13).lineSpacing(2).foregroundStyle(Theme.text)
                                .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: 360, alignment: .leading)
                        }
                    }
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        }
    }

    private func codeBox(_ lang: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "code" : lang).font(.chip).foregroundStyle(Theme.muted)
                Spacer()
                ChatCopyButton(text: body)
            }.padding(.horizontal, 12).padding(.vertical, 6)
            ScrollView(.horizontal) {
                Text(body).font(.chatCode).foregroundStyle(Theme.text).padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }
}
