import Foundation

func paletteTests() {
    let surfaces: [(String, Palette.Pair)] = [("bg", Palette.bg), ("sidebar", Palette.sidebar), ("surface", Palette.surface), ("surface2", Palette.surface2)]
    let inks: [(String, Palette.Pair)] = [("text", Palette.text), ("muted", Palette.muted), ("accent", Palette.accent),
                                          ("good", Palette.good), ("warn", Palette.warn), ("bad", Palette.bad)]
    for (sn, s) in surfaces {
        for (inn, i) in inks {
            expect(Palette.contrast(i.light, s.light) >= 4.5, "palette: \(inn) on \(sn) light >= 4.5 (\(Palette.contrast(i.light, s.light)))")
            expect(Palette.contrast(i.dark, s.dark) >= 4.5, "palette: \(inn) on \(sn) dark >= 4.5 (\(Palette.contrast(i.dark, s.dark)))")
        }
    }
    // every accent theme: text on the surfaces and the label on the accent fill stay readable
    for t in AccentTheme.all {
        for (sn, s) in surfaces {
            expect(Palette.contrast(t.accent.light, s.light) >= 4.5, "theme \(t.id): accent on \(sn) light")
            expect(Palette.contrast(t.accent.dark, s.dark) >= 4.5, "theme \(t.id): accent on \(sn) dark")
        }
        expect(Palette.contrast(t.onAccent.light, t.accent.light) >= 4.5, "theme \(t.id): onAccent light")
        expect(Palette.contrast(t.onAccent.dark, t.accent.dark) >= 4.5, "theme \(t.id): onAccent dark")
    }
    print("Palette tests OK")
}
