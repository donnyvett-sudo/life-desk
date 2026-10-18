import SwiftUI
import AppKit

/// NSTextView: Enter sends, Shift+Enter inserts a newline, nothing is sent while IME text is still marked.
/// Reports its content height (capped at ~6 lines) through `height`.
struct ChatInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onSend: () -> Void
    static let font = NSFont.systemFont(ofSize: 14)
    static let lineHeight: CGFloat = 17
    static let minHeight: CGFloat = 26
    static let maxHeight: CGFloat = 6 * lineHeight + 10

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.font = Self.font
        tv.isRichText = false
        tv.drawsBackground = false
        tv.textColor = .labelColor
        tv.insertionPointColor = .labelColor
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 4, height: 4)
        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.drawsBackground = false
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let tv = sv.documentView as? NSTextView {
            if tv.string != text { tv.string = text }
            context.coordinator.measure(tv)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInput
        init(_ p: ChatInput) { parent = p }
        func measure(_ tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = min(max(lm.usedRect(for: tc).height + 10, ChatInput.minHeight), ChatInput.maxHeight)
            if abs(h - parent.height) > 0.5 { DispatchQueue.main.async { self.parent.height = h } }
        }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            measure(tv)
        }
        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            guard sel == #selector(NSResponder.insertNewline(_:)), !tv.hasMarkedText(),
                  !NSEvent.modifierFlags.contains(.shift) else { return false }
            parent.text = tv.string
            parent.onSend()
            return true
        }
    }
}
