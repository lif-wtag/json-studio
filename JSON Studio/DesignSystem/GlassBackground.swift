import SwiftUI

/// The single home for the Liquid Glass fallback chain (ADR-08). Keeping it in one view means
/// macOS 26 glass API churn is a one-file change (risk register).
///
/// Fallback chain:
///   1. macOS 26+ and transparency allowed → Liquid Glass
///   2. else → `.regularMaterial`
///   3. Reduce Transparency on → opaque `controlBackgroundColor`
///
/// Applies ONLY to floating surfaces: command palette, popovers, sheets. **Never** the editor,
/// the inspector tree, or the status bar — those stay opaque (ADR-08).
struct GlassBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor))
        } else if #available(macOS 26, *) {
            // Phase 3a: swap in `.glassEffect(_:in:)` / GlassEffectContainer here. Using
            // `.regularMaterial` as a safe stand-in keeps the skeleton compiling on any SDK.
            content.background(.regularMaterial)
        } else {
            content.background(.regularMaterial)
        }
    }
}

extension View {
    /// Floating-surface background (palette / popover / sheet). See `GlassBackground`.
    func glassBackground() -> some View {
        modifier(GlassBackground())
    }
}
