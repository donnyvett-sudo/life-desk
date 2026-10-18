import SwiftUI
import AppKit

private struct FileEntry: Identifiable {
    let url: URL, rel: String, size: String, date: String, summary: String?
    var id: String { rel }
}

/// Files of resources/<course>/2026 grouped by first subfolder, with the files.md summary under each name.
struct CourseFilesTab: View {
    let course: String
    @ObservedObject private var store = StudyStore.shared
    @State private var entries: [FileEntry] = []
    @State private var query = ""
    @State private var picked: String?
    @FocusState private var focus: String?

    private var shown: [FileEntry] {
        query.isEmpty ? entries : entries.filter { [$0.rel, $0.summary ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query) }
    }
    private var groups: [(String, [FileEntry])] {
        let d = Dictionary(grouping: shown) { CourseInfo.group(rel: $0.rel) }
        return d.keys.sorted().map { ($0, d[$0]!.sorted { $0.rel < $1.rel }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if entries.isEmpty {
                EmptyState(icon: "folder", title: "No files for this course yet",
                           detail: "Files shared in the chats are copied to resources/\(course)/2026/ when you run sync.")
            } else {
                SearchField(text: $query, prompt: "Search \(entries.count) files").frame(maxWidth: 320)
                if shown.isEmpty { EmptyState(icon: "magnifyingglass", title: "No file matches “\(query)”") }
                ForEach(groups, id: \.0) { name, list in
                    Section2(title: name, count: list.count) {
                        Group2 { Rows(items: list) { row($0) } }
                    }
                }
                Text("Double-click opens · Space previews · right-click for Finder").font(.meta).foregroundStyle(Theme.muted)
            }
        }
        .task(id: store.tick) { load() }
    }

    private func row(_ e: FileEntry) -> some View {
        let sel = picked == e.id
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.icon(e.url.pathExtension)).font(.rowTitle)
                .foregroundStyle(Theme.course(course)).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.url.lastPathComponent).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                if let s = e.summary { Text(s).font(.meta).foregroundStyle(Theme.muted).lineLimit(2) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(e.size).font(.meta).monospacedDigit().foregroundStyle(Theme.muted)
                Text(e.date).font(.meta).monospacedDigit().foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(sel ? Theme.surface2 : .clear)
        .contentShape(Rectangle())
        .focusable().focused($focus, equals: e.id)
        .onKeyPress(.space) { picked = e.id; StudyQuickLook.show(e.url); return .handled }
        .onTapGesture(count: 2) { FileOpener.open(e.url) }
        .onTapGesture { picked = e.id; focus = e.id }
        .contextMenu {
            Button("Open") { FileOpener.open(e.url) }
            Button("Quick Look") { StudyQuickLook.show(e.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([e.url]) }
        }
    }

    private func load() {
        let dir = "\(Config.resources)/\(course)/2026"
        let sums = CourseInfo.summaries(filesMd: readResource("\(course)/2026/files.md"))
        entries = courseFileList(dir).map { u in
            let rel = String(u.path.dropFirst(dir.count + 1))
            let a = try? FileManager.default.attributesOfItem(atPath: u.path)
            let size = ByteCountFormatter.string(fromByteCount: (a?[.size] as? NSNumber)?.int64Value ?? 0, countStyle: .file)
            let date = (a?[.modificationDate] as? Date)?.formatted(date: .abbreviated, time: .omitted) ?? ""
            return FileEntry(url: u, rel: rel, size: size, date: date, summary: sums[rel])
        }
    }

    static func icon(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": "doc.richtext"
        case "doc", "docx": "doc.text"
        case "ppt", "pptx": "play.rectangle"
        case "xls", "xlsx", "csv": "tablecells"
        case "jpg", "jpeg", "png", "heic", "gif": "photo"
        case "zip", "rar", "7z": "doc.zipper"
        case "cpp", "c", "h", "hpp", "py", "swift": "chevron.left.forwardslash.chevron.right"
        case "mp4", "mov", "mp3", "m4a": "play.circle"
        case "md", "txt": "text.alignleft"
        default: "doc"
        }
    }
}
