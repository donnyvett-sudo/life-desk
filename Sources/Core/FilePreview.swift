import Foundation

/// How Life Desk shows a file: never in the app the file type is registered to (Word, Pages, ...).
enum FilePreview {
    enum Mode: Equatable { case preview, quickLook, finder }

    private static let previewApp: Set<String> = ["pdf", "png", "jpg", "jpeg", "heic", "gif", "tif", "tiff", "bmp", "webp"]
    private static let noPreview: Set<String> = ["zip", "rar", "7z", "gz", "tar", "dmg", "pkg", "exe", "app"]

    /// pdf and images: Preview.app. Archives and programs: reveal in Finder (nothing to look at, nothing to run).
    /// Everything else (Word, PowerPoint, Excel, text, code, video): the Quick Look panel.
    static func mode(ext: String, isDirectory: Bool = false) -> Mode {
        if isDirectory { return .finder }
        let e = ext.lowercased()
        if previewApp.contains(e) { return .preview }
        if noPreview.contains(e) { return .finder }
        return .quickLook
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let cases: [(String, Bool, Mode)] = [("PDF", false, .preview), ("jpg", false, .preview), ("docx", false, .quickLook),
                                              ("pptx", false, .quickLook), ("cpp", false, .quickLook), ("", false, .quickLook),
                                              ("7z", false, .finder), ("app", false, .finder), ("pdf", true, .finder)]
        for (e, d, m) in cases where mode(ext: e, isDirectory: d) != m { f.append("mode \(e) \(d)") }
        return f
    }
}
