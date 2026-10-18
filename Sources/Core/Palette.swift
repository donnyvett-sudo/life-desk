import Foundation

/// Colour tokens as [light, dark] hex pairs (docs/DESIGN.md). Kept in Core so the contrast rules are tested.
enum Palette {
    typealias Pair = (light: UInt32, dark: UInt32)
    static let bg: Pair = (0xf6f3ec, 0x151411)
    static let sidebar: Pair = (0xefe9dd, 0x1b1915)
    static let surface: Pair = (0xfffdf8, 0x1e1c18)
    static let surface2: Pair = (0xefe8db, 0x27241f)
    static let line: Pair = (0xe4ddd0, 0x2f2c26)
    static let text: Pair = (0x1f1d1a, 0xece6da)
    static let muted: Pair = (0x6f685c, 0x968d7f)
    /// The accent follows the chosen theme; everything else (warm background, text) stays.
    static var accent: Pair { AccentTheme.current.accent }
    static let good: Pair = (0x37703f, 0x82b98d)
    static let warn: Pair = (0x8f5c10, 0xd9a24f)
    static let bad: Pair = (0xa83a28, 0xe0715a)

    private static func luminance(_ h: UInt32) -> Double {
        func lin(_ v: UInt32) -> Double { let c = Double(v) / 255; return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin((h >> 16) & 255) + 0.7152 * lin((h >> 8) & 255) + 0.0722 * lin(h & 255)
    }
    /// WCAG contrast ratio of two colours.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

/// Accent themes the owner can switch between (iPhone Account, Mac Settings). Each one keeps WCAG AA contrast
/// for text on every surface and for the text drawn on the accent fill (checked in PaletteTests).
struct AccentTheme: Identifiable {
    let id: String
    let title: String
    let accent: Palette.Pair
    let onAccent: Palette.Pair

    static let all: [AccentTheme] = [
        AccentTheme(id: "coral", title: "Coral", accent: (0xa34a30, 0xd9785a), onAccent: (0xffffff, 0x151411)),
        AccentTheme(id: "ocean", title: "Ocean", accent: (0x1d5f9a, 0x6fb0ec), onAccent: (0xffffff, 0x151411)),
        AccentTheme(id: "forest", title: "Forest", accent: (0x2d6a3e, 0x7fc48f), onAccent: (0xffffff, 0x151411)),
        AccentTheme(id: "violet", title: "Violet", accent: (0x6a46b0, 0xb49af0), onAccent: (0xffffff, 0x151411)),
        AccentTheme(id: "graphite", title: "Graphite", accent: (0x3d4650, 0xb5bec8), onAccent: (0xffffff, 0x151411)),
    ]
    static let key = "app.theme"
    static var current: AccentTheme { all.first { $0.id == UserDefaults.standard.string(forKey: key) } ?? all[0] }
    static func choose(_ id: String) { UserDefaults.standard.set(id, forKey: key) }
}
