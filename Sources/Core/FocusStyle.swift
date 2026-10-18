import Foundation

/// How the focus clock looks and behaves. Saved as one JSON blob in UserDefaults.
struct FocusStyle: Codable, Equatable {
    enum Face: String, Codable, CaseIterable { case serif = "Serif", sans = "Sans", mono = "Mono", rounded = "Rounded" }
    enum Weight: String, Codable, CaseIterable { case ultraLight = "Ultralight", light = "Light", regular = "Regular", bold = "Bold" }
    enum Tint: String, Codable, CaseIterable { case text = "Text", accent = "Coral", course = "Course colour", custom = "Custom" }
    enum Backdrop: String, Codable, CaseIterable { case standard = "Standard", black = "Black", tinted = "Tinted" }
    enum Progress: String, Codable, CaseIterable { case bar = "Bar", fill = "Fill", none = "None" }
    enum Format: String, Codable, CaseIterable { case clock = "24:07", minutes = "24 min" }

    var face: Face = .serif
    var weight: Weight = .light
    var size: Double = 1.0            // 0.5 … 1.0 of the largest size that fits
    var tint: Tint = .text
    var customHex: String = "d9785a"
    var backdrop: Backdrop = .standard
    var progress: Progress = .bar
    var format: Format = .clock
    var showLabel = true
    var showEnd = true
    var sound = "Glass"               // a macOS system sound name, or "None"
    var autoFullScreen = true

    init() {}
    /// Missing keys (a style saved by an older build) fall back to the defaults instead of resetting everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = FocusStyle()
        face = try c.decodeIfPresent(Face.self, forKey: .face) ?? d.face
        weight = try c.decodeIfPresent(Weight.self, forKey: .weight) ?? d.weight
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        tint = try c.decodeIfPresent(Tint.self, forKey: .tint) ?? d.tint
        customHex = try c.decodeIfPresent(String.self, forKey: .customHex) ?? d.customHex
        backdrop = try c.decodeIfPresent(Backdrop.self, forKey: .backdrop) ?? d.backdrop
        progress = try c.decodeIfPresent(Progress.self, forKey: .progress) ?? d.progress
        format = try c.decodeIfPresent(Format.self, forKey: .format) ?? d.format
        showLabel = try c.decodeIfPresent(Bool.self, forKey: .showLabel) ?? d.showLabel
        showEnd = try c.decodeIfPresent(Bool.self, forKey: .showEnd) ?? d.showEnd
        sound = try c.decodeIfPresent(String.self, forKey: .sound) ?? d.sound
        autoFullScreen = try c.decodeIfPresent(Bool.self, forKey: .autoFullScreen) ?? d.autoFullScreen
    }
    private enum Keys: String, CodingKey { case face, weight, size, tint, customHex, backdrop, progress, format, showLabel, showEnd, sound, autoFullScreen }

    static let sounds = ["Glass", "Ping", "Hero", "Submarine", "Funk", "Tink", "None"]
    private static let key = "focus.style"

    static func load() -> FocusStyle {
        guard let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(FocusStyle.self, from: d) else { return FocusStyle() }
        return s
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    /// The big number: "24:07" or just the minutes left ("24", rounded up).
    func text(remaining: TimeInterval) -> String {
        switch format {
        case .clock: return FocusLogic.clock(remaining)
        case .minutes: return String(max(0, Int((remaining / 60).rounded(.up))))
        }
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        var s = FocusStyle()
        if s.text(remaining: 1447) != "24:07" { f.append("style clock") }
        s.format = .minutes
        if s.text(remaining: 1447) != "25" || s.text(remaining: 0) != "0" { f.append("style minutes") }
        let back = try? JSONDecoder().decode(FocusStyle.self, from: JSONEncoder().encode(s))
        if back != s { f.append("style json") }
        if (try? JSONDecoder().decode(FocusStyle.self, from: Data("{}".utf8))) == nil { f.append("style defaults on partial json") }
        return f
    }
}
