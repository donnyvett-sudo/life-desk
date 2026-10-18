import SwiftUI

/// A short message with an optional Undo, at the bottom of the screen for 5 seconds.
@MainActor
final class Toasts: ObservableObject {
    static let shared = Toasts()
    struct Toast: Identifiable { let id = UUID(); let text: String; let undo: (() -> Void)? }
    @Published private(set) var current: Toast?

    func show(_ text: String, undo: (() -> Void)? = nil) {
        AccessibilityNotification.Announcement(text).post()   // VoiceOver: the banner disappears on its own
        let t = Toast(text: text, undo: undo)
        current = t
        Task { try? await Task.sleep(nanoseconds: 5_000_000_000); if current?.id == t.id { current = nil } }
    }
    func dismiss() { current = nil }
}

struct ToastHost: View {
    @ObservedObject private var toasts = Toasts.shared
    var body: some View {
        if let t = toasts.current {
            HStack(spacing: 12) {
                Text(t.text).font(.body13).foregroundStyle(Theme.text)
                if let undo = t.undo { Button("Undo") { toasts.dismiss(); undo() }.buttonStyle(QuietButton()) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
            .padding(.bottom, 12)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }
}
