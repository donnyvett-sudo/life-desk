import SwiftUI

/// iOS 26 Liquid Glass, used only where Apple says it belongs: controls that float over content (composer, choice
/// chips, quote bar). Content (cards, lists, charts) stays opaque. With Reduce Transparency the glass becomes a solid fill.
struct GlassCapsule: ViewModifier {
    var tint: Color? = nil
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var solid

    func body(content: Content) -> some View {
        if solid {
            content.background(Theme.surface, in: Capsule()).overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        } else {
            content.glassEffect(glass, in: Capsule())
        }
    }
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.35)) }
        return interactive ? g.interactive() : g
    }
}

struct GlassRounded: ViewModifier {
    var radius: CGFloat = 18
    @Environment(\.accessibilityReduceTransparency) private var solid

    func body(content: Content) -> some View {
        if solid { content.background(Theme.surface, in: RoundedRectangle(cornerRadius: radius)) }
        else { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius)) }
    }
}

extension View {
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View { modifier(GlassCapsule(tint: tint, interactive: interactive)) }
    func glassRounded(_ radius: CGFloat = 18) -> some View { modifier(GlassRounded(radius: radius)) }
}
