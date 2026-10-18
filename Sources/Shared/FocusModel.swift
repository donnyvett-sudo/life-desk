import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#else
import AudioToolbox
import UserNotifications
#endif

/// The running focus session: a big local countdown mirrored in the bot's focus_sessions.
/// The bot closes the session at the planned time (and messages Telegram); stopping early goes through the API.
@MainActor
final class FocusModel: ObservableObject {
    static let shared = FocusModel()
    enum Phase: Equatable { case idle, running, paused, finished(Int) }

    @Published var phase: Phase = .idle
    @Published var now = Date()
    @Published var error: String?
    @Published var busy = false
    @Published private(set) var label = ""
    @Published private(set) var courseCode: String?
    @Published private(set) var pausedRemaining: TimeInterval = 0
    private(set) var courseId: String?
    /// Focus time of earlier segments of this sitting (a pause closes the bot's session).
    private var bankedSeconds: Double = 0
    /// Bot session whose stop was not confirmed (closed again before the next resume).
    private var pendingStopId: String?
    /// When the sitting was paused: a session the bot opened after this instant may be our own unread resume.
    private var pausedAt: Date?
    private(set) var sessionId = ""
    private(set) var startedAt = Date()
    private(set) var plannedMin = 25
    private var ticker: Timer?
    private var enteredFullScreen = false

    var endDate: Date { startedAt.addingTimeInterval(Double(plannedMin) * 60) }
    var remaining: TimeInterval { phase == .paused ? pausedRemaining : max(0, endDate.timeIntervalSince(now)) }
    var progress: Double { min(1, max(0, 1 - remaining / (Double(plannedMin) * 60))) }
    var immersive: Bool { phase == .running || phase == .paused }

    private func labelKey(_ id: String) -> String { "focus.label.\(id)" }

    /// On launch (and when the page opens): pick up a session that is already running in the bot,
    /// or a sitting that was paused before the app was closed.
    func adoptIfRunning() async {
        guard phase == .idle else { return }
        let study = try? await BotAPI.fetchStudy()
        guard phase == .idle else { return }  // the user may have started a session while we waited
        guard let r = study?.focus?.running, let started = FocusLogic.parse(r.startedAt) else {
            restorePaused()
            return
        }
        // A session that ours left unconfirmed in the bot is the same sitting: keep the banked time of its paused record.
        let paused = FocusPaused.load()
        FocusPaused.clear()
        sessionId = r.id; startedAt = started; plannedMin = r.plannedMin
        let saved = FocusPaused.banked(session: r.id)
        if saved > 0 {
            bankedSeconds = saved
        } else if let p = paused, p.pendingStopId == r.id {
            // The bank already holds the segment of this very session (added when it was paused): take it out again.
            let own = FocusLogic.elapsedSeconds(from: started, to: p.savedAt, planned: r.plannedMin)
            bankedSeconds = max(0, p.bankedSeconds - own)
        } else {
            bankedSeconds = 0
        }
        pausedAt = nil
        pendingStopId = nil
        courseId = r.course?.id
        courseCode = r.course.map { Theme.folder(botShort: $0.short) }
        label = UserDefaults.standard.string(forKey: labelKey(r.id)) ?? r.course.map { Theme.short(Theme.folder(botShort: $0.short)) } ?? "Focus"
        begin(enterFullScreen: false)
    }

    func start(course: BotStudy.Course?, topic: String, minutes: Int) async {
        guard !busy, phase == .idle else { return }
        busy = true; error = nil
        defer { busy = false }
        let m = min(180, max(5, minutes))
        do {
            try await BotAPI.startFocus(courseId: course?.id, minutes: m)
        } catch BotAPI.Err.http(409) {
            error = "A focus session is already running (maybe started in Telegram) — joining it."
        } catch {
            self.error = "Couldn't start in the bot. Check the connection and try again."
            return
        }
        guard let r = (try? await BotAPI.fetchStudy())?.focus?.running, let started = FocusLogic.parse(r.startedAt) else {
            error = "Started, but couldn't read the session back. Open the page again in a moment."
            return
        }
        sessionId = r.id; startedAt = started; plannedMin = r.plannedMin
        courseId = course?.id
        bankedSeconds = 0
        pendingStopId = nil
        FocusPaused.clear()
        courseCode = course.map { Theme.folder(botShort: $0.short) }
        let t = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        label = !t.isEmpty ? t : (course.map { Theme.short(Theme.folder(botShort: $0.short)) } ?? "Free study")
        UserDefaults.standard.set(label, forKey: labelKey(sessionId))
        begin(enterFullScreen: true)
    }

    /// Ends the session early: the bot closes it with the elapsed minutes.
    /// Ignored while another action is in flight (the buttons are disabled while `busy`).
    func stop() async {
        guard !busy, phase == .running || phase == .paused else { return }
        busy = true; defer { busy = false }
        var elapsed: Double = 0
        if phase == .running {
            elapsed = FocusLogic.elapsedSeconds(from: startedAt, to: now, planned: plannedMin)
            if !sessionId.isEmpty {
                do { try await BotAPI.stopFocus(id: sessionId) } catch {
                    self.error = "Stopped here, but the bot didn't confirm — stop it in Telegram too if it keeps running."
                }
            }
        } else if let id = pendingStopId {
            do { try await BotAPI.stopFocus(id: id) } catch BotAPI.Err.http(let c) where c == 404 || c == 409 {
                // already closed
            } catch {
                self.error = "The paused session may still be open in the bot — stop it in Telegram."
            }
        }
        // The countdown may have reached zero while we waited; it already finished the session.
        guard phase == .running || phase == .paused else { return }
        if !sessionId.isEmpty { FocusPaused.clearBanked(session: sessionId) }
        FocusPaused.clear()
        pendingStopId = nil
        finish(minutes: FocusLogic.minutes(fromSeconds: bankedSeconds + elapsed), sound: false)
    }

    /// Pause = close the bot's session with the minutes so far; resume opens a new one for what is left.
    func pause() async {
        guard phase == .running, !busy else { return }
        busy = true; defer { busy = false }
        let sid = sessionId
        let left = remaining
        let elapsed = FocusLogic.elapsedSeconds(from: startedAt, to: now, planned: plannedMin)
        var unconfirmed: String?
        if !sid.isEmpty {
            do { try await BotAPI.stopFocus(id: sid) } catch {
                unconfirmed = sid
                self.error = "Paused here, but the bot didn't confirm. It will be closed again when you resume."
            }
        }
        // The countdown ended while we waited: the session is already finished, nothing to pause.
        guard phase == .running, sessionId == sid else { return }
        if !sid.isEmpty { FocusPaused.clearBanked(session: sid) }
        bankedSeconds += elapsed
        pausedRemaining = left
        pendingStopId = unconfirmed
        pausedAt = Date()
        sessionId = ""
        ticker?.invalidate(); ticker = nil
        cancelEndNotification()
        phase = .paused
        savePaused()
    }

    func resume() async {
        guard phase == .paused, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        // A stop the bot never confirmed would make the new session fail with 409: close it first.
        if let id = pendingStopId {
            do { try await BotAPI.stopFocus(id: id) } catch BotAPI.Err.http(let c) where c == 404 || c == 409 {
                // already closed
            } catch {
                self.error = "Couldn't close the previous session in the bot. Check the connection and try again."
                return
            }
            guard phase == .paused else { return }
            pendingStopId = nil
            savePaused()
        }
        let left = pausedRemaining
        var newId = ""
        // The bot's shortest session is 5 minutes. A shorter tail runs only here and is not booked in the bot.
        if left >= 5 * 60 {
            let m = min(180, max(5, Int((left / 60).rounded())))
            var adopted: BotStudy.Focus.Running?
            do {
                try await BotAPI.startFocus(courseId: courseId, minutes: m)
            } catch BotAPI.Err.http(409) {
                // Either a foreign session (maybe from Telegram), or our own resume whose answer was lost earlier.
                // Only a session of the same course that was opened after the pause counts as ours.
                guard let other = (try? await BotAPI.fetchStudy())?.focus?.running,
                      let started = FocusLogic.parse(other.startedAt),
                      other.course?.id == courseId,
                      started >= (pausedAt ?? .distantFuture).addingTimeInterval(-5) else {
                    self.error = "Another focus session is already running in the bot. Stop it (for example in Telegram) and resume again."
                    return
                }
                adopted = other
            } catch {
                self.error = "Couldn't resume in the bot. Check the connection and try again."
                return
            }
            guard phase == .paused else { return }
            var run = adopted
            if run == nil {
                // The session is open in the bot; reading it back may need a second try.
                for attempt in 0..<3 where run == nil {
                    if attempt > 0 { try? await Task.sleep(nanoseconds: 600_000_000) }
                    run = (try? await BotAPI.fetchStudy())?.focus?.running
                }
            }
            guard phase == .paused else { return }
            guard let r = run, let started = FocusLogic.parse(r.startedAt) else {
                error = "Resumed, but couldn't read the session back. Press Resume again to pick it up."
                return
            }
            newId = r.id
            sessionId = r.id; startedAt = started; plannedMin = r.plannedMin
            UserDefaults.standard.set(label, forKey: labelKey(newId))
            FocusPaused.saveBanked(bankedSeconds, session: newId)
        } else {
            sessionId = ""
            plannedMin = max(1, Int(ceil(left / 60)))
            startedAt = Date().addingTimeInterval(left - Double(plannedMin) * 60)
        }
        pausedAt = nil
        FocusPaused.clear()
        begin(enterFullScreen: false)
    }

    func reset() {
        guard !busy else { return }
        ticker?.invalidate(); ticker = nil
        cancelEndNotification()
        phase = .idle; error = nil
        bankedSeconds = 0; pendingStopId = nil; sessionId = ""
        FocusPaused.clear()
    }

    // MARK: pause survives a restart

    private func savePaused() {
        FocusPaused.save(FocusPaused(label: label, courseId: courseId, courseCode: courseCode, remaining: pausedRemaining,
                                     plannedMin: plannedMin, bankedSeconds: bankedSeconds, pendingStopId: pendingStopId, savedAt: Date()))
    }

    private func restorePaused() {
        guard let p = FocusPaused.load() else { return }
        label = p.label; courseId = p.courseId; courseCode = p.courseCode
        pausedRemaining = p.remaining; plannedMin = p.plannedMin; bankedSeconds = p.bankedSeconds
        pendingStopId = p.pendingStopId
        pausedAt = p.savedAt
        sessionId = ""
        phase = .paused
    }

    private func begin(enterFullScreen: Bool) {
        phase = .running
        now = Date()
        ticker?.invalidate()
        // .common mode keeps the clock running while menus are open or the window is being resized.
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        #if canImport(AppKit)
        if enterFullScreen, FocusStyleStore.shared.style.autoFullScreen, let w = mainWindow(), !w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil); enteredFullScreen = true }
        #endif
        scheduleEndNotification()
    }

    private func tick() {
        let n = Date()
        // The clock shows whole seconds: publishing four times a second would redraw every observer for nothing.
        if Int(n.timeIntervalSince1970) != Int(now.timeIntervalSince1970) { now = n }
        if phase == .running, remaining <= 0 { finish(minutes: FocusLogic.minutes(fromSeconds: bankedSeconds + Double(plannedMin) * 60), sound: n.timeIntervalSince(endDate) < 3) }
    }

    private func finish(minutes: Int, sound: Bool) {
        if !sessionId.isEmpty { FocusPaused.clearBanked(session: sessionId) }
        ticker?.invalidate(); ticker = nil
        phase = .finished(minutes)
        let s = FocusStyleStore.shared.style.sound
        #if canImport(AppKit)
        if sound, s != "None" { NSSound(named: NSSound.Name(s))?.play() }
        if enteredFullScreen, let w = mainWindow(), w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        #else
        if sound, s != "None" { AudioServicesPlaySystemSound(1007) }
        #endif
        enteredFullScreen = false
        cancelEndNotification()
    }

    #if canImport(AppKit)
    private func mainWindow() -> NSWindow? { NSApp.windows.first { $0.title == "Life Desk" } }
    private func scheduleEndNotification() {}
    private func cancelEndNotification() {}
    #else
    /// iPhone: a local notification at the planned end, so the timer rings with the screen locked.
    private func scheduleEndNotification() {
        let secs = endDate.timeIntervalSinceNow
        guard secs > 1 else { return }
        let c = UNMutableNotificationContent()
        c.title = "Focus finished"; c.body = label.isEmpty ? "Time is up." : "\(label): time is up."; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "life.focus.end", content: c,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: secs, repeats: false)))
    }
    private func cancelEndNotification() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["life.focus.end"]) }
    #endif
}
