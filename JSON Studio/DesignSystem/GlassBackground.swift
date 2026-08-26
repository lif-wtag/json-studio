import SwiftUI

/// Glass for the **command palette only** (SH-14, Phase 4) — the one floating surface with no
/// system presentation behind it.
///
/// **Do not reach for this for popovers or sheets.** Per ADR-08 Amendment 1: on macOS 26, Liquid
/// Glass *is* the system design language, and an app built against the macOS 26 SDK adopts it
/// automatically on standard components — `.popover` and `.sheet` included. System materials also
/// honour Reduce Transparency and Increase Contrast on their own. So a real `.popover` gets the
/// right material on every OS version for free, and gets the dismissal semantics, the keyboard
/// handling, and the accessibility behaviour with it.
///
/// Hand-rolling a popover as a custom overlay in order to style it is a defect, not a shortcut.
/// If you find `glassBackground()` on anything but the command palette, that is a bug.
///
/// Fallback chain, for the palette:
///   1. Reduce Transparency on → opaque `controlBackgroundColor`
///   2. macOS 26+ → Liquid Glass
///   3. else → `.regularMaterial`
///
/// **Never** the editor, the gutter, syntax, error text, the inspector tree, or the status bar.
struct GlassBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat = Tokens.Radius.surface

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                Color(nsColor: .controlBackgroundColor),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else if #available(macOS 26, *) {
            // Phase 4: swap in `.glassEffect(.regular, in: .rect(cornerRadius:))` inside a
            // `GlassEffectContainer` here. `.regularMaterial` keeps this compiling on any SDK.
            content.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    /// Command-palette background. See `GlassBackground` — popovers and sheets must use the real
    /// system presentations instead.
    func glassBackground(cornerRadius: CGFloat = Tokens.Radius.surface) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}
