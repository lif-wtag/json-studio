import SwiftUI

/// The toolbar's controls, drawn to `Window.dc.html` rather than left to the system (SH-01).
///
/// **Why these are styled at all.** ADR-08's "toolbar gets whatever the system applies" is about
/// *materials* — don't add glass, don't fight the platform's vibrancy. It is not about shape. The
/// approved design specifies the pills exactly (26pt, radius 6, fill plus a 1px border) and a
/// plain `Button` in a macOS 26 toolbar renders borderless, which is what shipped in Task 16 and
/// what the user reported as not matching the mockups.
///
/// Every colour still resolves to an AppKit semantic. No literal hex survives outside
/// `SyntaxTheme.swift` (locked decision #9).
struct ToolbarPillStyle: ButtonStyle {
    /// Compare is present and disabled until Task 27; the style has to draw that state itself,
    /// because a custom background does not dim with the label.
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(PillLabelStyle())
            .font(Tokens.Typography.uiBody)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, Tokens.Spacing.s + Tokens.Spacing.xxs)
            .frame(height: Tokens.Layout.controlHeight)
            .background(
                Tokens.Surface.control,
                in: .rect(cornerRadius: Tokens.Radius.control)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.control)
                    .strokeBorder(Tokens.Surface.divider, lineWidth: Tokens.State.selectionRingWidth)
            }
            // Pressed reads as a darkening rather than a scale: the pills sit in a row, and a
            // scaling one shifts its neighbours' apparent spacing.
            .opacity(configuration.isPressed ? 0.7 : 1)
            .opacity(isEnabled ? 1 : Tokens.State.disabledOpacity)
            .contentShape(.rect(cornerRadius: Tokens.Radius.control))
    }
}

/// Icon then label, at the artboard's 6pt gap — `.titleAndIcon` leaves the spacing to the system.
private struct PillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Tokens.Spacing.xs + Tokens.Spacing.xxs) {
            configuration.icon
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}

/// The inspector toggle (28 × 26): a pill when off, accent fill **and** accent border when on.
///
/// Not a `Toggle(.button)` — that renders as a filled circle on macOS 26, which is what the user
/// saw. And never colour alone (locked decision #10): the glyph itself changes to show which side
/// is open, and the control carries an accessibility value either way.
struct InspectorToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Image(systemName: configuration.isOn
                  ? "sidebar.trailing"
                  : "rectangle.righthalf.inset.filled")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: Tokens.Layout.controlHeight)
                .background(
                    configuration.isOn
                        ? Color.accentColor.opacity(Tokens.State.accentFillOpacity)
                        : Tokens.Surface.control,
                    in: .rect(cornerRadius: Tokens.Radius.control)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.control)
                        .strokeBorder(
                            configuration.isOn
                                ? Color.accentColor.opacity(Tokens.State.accentBorderOpacity)
                                : Tokens.Surface.divider,
                            lineWidth: Tokens.State.selectionRingWidth
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
        .accessibilityValue(configuration.isOn ? "Shown" : "Hidden")
    }
}

/// The artboard's 1px × 20 separator between the pill group, the search field and the toggle.
struct ToolbarSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.Surface.divider)
            .frame(width: Tokens.Layout.dividerWidth, height: 20)
            .padding(.horizontal, Tokens.Spacing.xs + Tokens.Spacing.xxs)
            .accessibilityHidden(true)
    }
}
