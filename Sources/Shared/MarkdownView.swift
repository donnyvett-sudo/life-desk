import SwiftUI

/// Markdown renderer: heading hierarchy, bullets, numbered lists, quotes, code, tables, inline bold/code/links.
/// Prose is capped at `proseWidth` (≈70 characters at 13 pt); tables and code may be wider. A section whose
/// heading mentions "AI policy" sits in a tinted box.
struct MarkdownView: View {
    let text: String
    var skipFirstHeading = false
    var proseWidth: CGFloat = 460

    enum Node {
        case heading(Int, String)
        case item(depth: Int, marker: String, text: String)
        case quote(String)
        case code(String)
        case paragraph(String)
        case table(MarkdownTables.Table)
    }

    static func inline(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }

    static func parse(_ text: String) -> [Node] {
        var out: [Node] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                out.append(.code(code.joined(separator: "\n")))
            } else if line.hasPrefix("#") {
                let level = line.prefix { $0 == "#" }.count
                out.append(.heading(min(level, 4), line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("|") {
                var chunk = [raw]
                while i + 1 < lines.count, lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix("|") { i += 1; chunk.append(lines[i]) }
                if let t = MarkdownTables.tables(chunk.joined(separator: "\n")).first { out.append(.table(t)) }
                else { out.append(.paragraph(line)) }
            } else if line.hasPrefix(">") {
                out.append(.quote(String(line.drop { $0 == ">" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                out.append(.item(depth: indent / 2, marker: indent >= 2 ? "◦" : "•", text: String(line.dropFirst(2))))
            } else if let r = line.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                let indent = raw.prefix { $0 == " " }.count
                out.append(.item(depth: indent / 2, marker: String(line[r]).trimmingCharacters(in: .whitespaces), text: String(line[r.upperBound...])))
            } else if line == "---" || line == "***" {
                // horizontal rule: skip
            } else if !line.isEmpty {
                out.append(.paragraph(line))
            }
            i += 1
        }
        return out
    }

    private func isPolicy(_ t: String) -> Bool { t.lowercased().contains("ai policy") }

    /// Consecutive nodes grouped so the AI-policy section can share one tinted box.
    private func segments() -> [(policy: Bool, nodes: [Node])] {
        var segs: [(policy: Bool, nodes: [Node])] = []
        var inPolicy = false, policyLevel = 0, first = true
        for n in Self.parse(text) {
            if case .heading(let l, let t) = n {
                if first && skipFirstHeading { first = false; continue }
                if isPolicy(t) { inPolicy = true; policyLevel = l }
                else if inPolicy && l <= policyLevel { inPolicy = false }
            }
            first = false
            if segs.last?.policy == inPolicy { segs[segs.count - 1].nodes.append(n) } else { segs.append((inPolicy, [n])) }
        }
        return segs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments().enumerated()), id: \.offset) { _, seg in
                if seg.policy {
                    blocks(seg.nodes).padding(14)
                        .background(Theme.bad.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.bad.opacity(0.35), lineWidth: 1))
                } else { blocks(seg.nodes) }
            }
        }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func blocks(_ nodes: [Node]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { _, n in node(n) }
        }
    }

    @ViewBuilder private func node(_ n: Node) -> some View {
        switch n {
        case .heading(let level, let t):
            Group {
                if level <= 2 { Text(Self.inline(t)).font(.h2).foregroundStyle(Theme.text) }
                else if level == 3 { Text(Self.inline(t)).font(.rowTitle).foregroundStyle(Theme.text) }
                else { Text(Self.inline(t.uppercased())).font(.sectionLabel).tracking(0.6).foregroundStyle(Theme.muted) }
            }
            .padding(.top, level <= 2 ? 16 : 8)
            .frame(maxWidth: proseWidth, alignment: .leading)
        case .item(let depth, let marker, let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).foregroundStyle(Theme.muted).monospacedDigit().frame(minWidth: 14, alignment: .trailing)
                Text(Self.inline(t)).lineSpacing(3).foregroundStyle(Theme.text)
            }
            .font(.body13).padding(.leading, CGFloat(depth) * 16)
            .frame(maxWidth: proseWidth, alignment: .leading)
        case .quote(let t):
            HStack(spacing: 10) {
                Rectangle().fill(Theme.accent).frame(width: 2)
                Text(Self.inline(t)).lineSpacing(3).foregroundStyle(Theme.muted)
            }.font(.body13).fixedSize(horizontal: false, vertical: true).frame(maxWidth: proseWidth, alignment: .leading)
        case .code(let c):
            ScrollView(.horizontal) {
                Text(c).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.text).padding(10)
            }
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 680, alignment: .leading)
        case .paragraph(let t):
            Text(Self.inline(t)).font(.body13).lineSpacing(4).foregroundStyle(Theme.text)
                .frame(maxWidth: proseWidth, alignment: .leading)
        case .table(let t):
            MarkdownTableView(table: t)
        }
    }
}

/// A markdown table on one card: muted header, hairlines, cells wrap; no raw pipes.
struct MarkdownTableView: View {
    let table: MarkdownTables.Table
    var body: some View {
        Group2 {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.rawHeader.enumerated()), id: \.offset) { _, h in
                        Text(MarkdownView.inline(MarkdownTables.clean(h).uppercased())).font(.sectionLabel).tracking(0.6)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(Array(table.rawRows.enumerated()), id: \.offset) { _, row in
                    Hairline().gridCellColumns(max(table.rawHeader.count, 1))
                    GridRow {
                        ForEach(Array(row.prefix(table.rawHeader.count).enumerated()), id: \.offset) { _, c in
                            Text(MarkdownView.inline(c)).font(.body13).lineSpacing(2).foregroundStyle(Theme.text)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }
}
