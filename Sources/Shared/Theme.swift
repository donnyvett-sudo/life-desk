import SwiftUI

/// Palette shared with the Mini App (warm dark + coral accent) and one colour per course.
enum Theme {
    // Tokens from docs/DESIGN.md: [light, dark] pairs that follow the system appearance.
    private static func pair(_ p: Palette.Pair) -> Color { pair(p.light, p.dark) }
    private static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        func rgb(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255)
        }
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { ap in
            let c = rgb(ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        return Color(uiColor: UIColor { tc in
            let c = rgb(tc.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }
    static let bg = pair(Palette.bg)
    static let sidebar = pair(Palette.sidebar)
    static let surface = pair(Palette.surface)
    static let surface2 = pair(Palette.surface2)
    static let line = pair(Palette.line)
    static let text = pair(Palette.text)
    static let muted = pair(Palette.muted)
    /// Computed, not stored: a theme change shows up on the next redraw (the roots re-render on `.id(theme)`).
    static var accent: Color { pair(Palette.accent) }
    /// Text on the accent fill: white on the light coral, the dark background colour on the lighter dark-mode coral (AA contrast).
    static var onAccent: Color { pair(AccentTheme.current.onAccent) }
    static let good = pair(Palette.good)
    static let warn = pair(Palette.warn)
    static let bad = pair(Palette.bad)

    /// One colour per area, the same in lists, cards and charts (light / dark pairs, readable on both backgrounds).
    static let sleep = pair(0x5B5FC7, 0x8E92F0)
    static let money = pair(0x2F8F5B, 0x5FC48D)
    static let food = pair(0xC9702A, 0xF0A35E)
    static let focus = pair(0x1F8A86, 0x4FC7C1)

    private static let palette: [Color] = [
        Color(red: 0.85, green: 0.47, blue: 0.35), Color(red: 0.42, green: 0.65, blue: 0.82),
        Color(red: 0.51, green: 0.73, blue: 0.55), Color(red: 0.85, green: 0.64, blue: 0.31),
        Color(red: 0.69, green: 0.55, blue: 0.82), Color(red: 0.40, green: 0.74, blue: 0.72),
        Color(red: 0.82, green: 0.52, blue: 0.64), Color(red: 0.62, green: 0.68, blue: 0.40),
    ]

    /// Stable colour for a course folder name (the same everywhere in the app).
    static func course(_ code: String) -> Color {
        // djb2 hash, so the same folder always gets the same colour (String.hashValue is randomised per launch).
        let h = code.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
        return palette[abs(h % palette.count)]
    }

    /// Map the bot's short course labels back to workspace folder names. Ships empty (label == folder);
    /// e.g. ["Stats": "stats101"].
    nonisolated(unsafe) static var botLabels: [String: String] = [:]
    static func folder(botShort: String) -> String { botLabels[botShort] ?? botShort }

    /// Short course label for badges.
    static func short(_ code: String) -> String { code == "general" ? "General" : code }
}
