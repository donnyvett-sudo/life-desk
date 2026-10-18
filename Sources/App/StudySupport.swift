import SwiftUI
import AppKit
import QuickLookUI
import CoreServices

/// Watches resources/ (FSEvents, recursive) and bumps `tick` 0.5 s after the last change.
final class StudyStore: ObservableObject {
    static let shared = StudyStore()
    @Published var tick = 0
    private var stream: FSEventStreamRef?

    private init() {
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let me = Unmanaged<StudyStore>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { me.tick += 1 }
        }
        // latency 0.5 s coalesces bursts of events = the debounce
        guard let s = FSEventStreamCreate(nil, cb, &ctx, [Config.resources] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
    }
}

/// Quick Look for a single file via the shared panel.
final class StudyQuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = StudyQuickLook()
    private var url: URL?
    static func show(_ url: URL) {
        shared.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = shared
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL? }
}

/// The one way files are opened: PDFs and images in Preview, Office documents and the rest in Quick Look,
/// archives revealed in Finder. Never in Word or Pages.
enum FileOpener {
    @MainActor static func open(_ url: URL) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        switch FilePreview.mode(ext: url.pathExtension, isDirectory: isDir.boolValue) {
        case .preview:
            let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
            if FileManager.default.fileExists(atPath: preview.path) {
                NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
            } else {
                StudyQuickLook.show(url)
            }
        case .quickLook: StudyQuickLook.show(url)
        case .finder: NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

/// Open / Show in Finder / Quick Look for one file.
struct StudyFileButtons: View {
    let url: URL
    var body: some View {
        HStack(spacing: 4) {
            Button("Open") { FileOpener.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Quick Look") { StudyQuickLook.show(url) }
        }.controlSize(.small)
    }
}


/// Text of a file under the Study Workspace `resources/` folder (shared by the Study pages).
func readResource(_ rel: String) -> String { MarkdownTables.read("\(Config.resources)/\(rel)") }
