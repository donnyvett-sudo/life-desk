import Foundation

func focusTests() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    expect(FocusLogic.elapsedSeconds(from: t0, to: t0.addingTimeInterval(89), planned: 25) == 89, "elapsed: seconds kept")
    expect(FocusLogic.elapsedSeconds(from: t0, to: t0.addingTimeInterval(40 * 60), planned: 25) == 25 * 60, "elapsed: capped at planned")
    expect(FocusLogic.elapsedSeconds(from: t0, to: t0.addingTimeInterval(-30), planned: 25) == 0, "elapsed: never negative")
    expect(FocusLogic.minutes(fromSeconds: 89) == 1 && FocusLogic.minutes(fromSeconds: 91) == 2, "minutes: nearest")
    // twenty 29-second segments are 9.7 minutes, not 0
    expect(FocusLogic.minutes(fromSeconds: 20 * 29) == 10, "minutes: segments are summed before rounding")

    let suite = "ld-focus-test-\(getpid())"
    let d = UserDefaults(suiteName: suite)!
    defer { d.removePersistentDomain(forName: suite) }
    let p = FocusPaused(label: "Reading", courseId: "k1", courseCode: "stats101", remaining: 612, plannedMin: 25,
                        bankedSeconds: 14 * 60 + 20, pendingStopId: "s-9", savedAt: Date())
    FocusPaused.save(p, to: d)
    expect(FocusPaused.load(from: d) == p, "paused: round trip keeps bank and pending stop")
    expect(FocusPaused.load(from: d, now: Date().addingTimeInterval(13 * 3600)) == nil, "paused: expires after 12 h")
    expect(FocusPaused.load(from: d) == nil, "paused: expired record is removed")
    FocusPaused.saveBanked(860, session: "s-1", to: d)
    expect(FocusPaused.banked(session: "s-1", from: d) == 860, "banked: stored per session in seconds")
    d.set(14, forKey: "focus.banked.s-old")
    expect(FocusPaused.banked(session: "s-old", from: d) == 14 * 60, "banked: minutes of an earlier version are read")
    FocusPaused.clearBanked(session: "s-1", in: d)
    expect(FocusPaused.banked(session: "s-1", from: d) == 0, "banked: cleared")

    // a record written by the previous version: whole minutes, no pending stop
    let legacy = #"{"label":"Old","courseId":"k2","remaining":300,"plannedMin":25,"bankedMin":12,"savedAt":0}"#
    d.set(Data(legacy.utf8), forKey: FocusPaused.key)
    let old = FocusPaused.load(from: d, now: Date(timeIntervalSince1970: 60))
    expect(old?.bankedSeconds == 720 && old?.pendingStopId == nil && old?.label == "Old", "paused: previous-version record reads")
    print("Focus wave-0 tests OK")
}
