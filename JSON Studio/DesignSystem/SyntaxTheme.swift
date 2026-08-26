import SwiftUI

/// The syntax highlighting palette and the six diff/validation semantics.
///
/// **This is the only file where literal hex colours are allowed** (locked decision #9).
/// Values are authored in `Design/tokens.md`; every `contrastRatio` below is the *measured*
/// worst applicable case, computed by `Design/palette-measure.py`. Re-run that script after any
/// change here — it fails loudly.
///
/// The palette obeys one rule that shapes everything: **syntax lives in the cool arc
/// (144°–264°); warm hues are reserved for diagnostics.** Object keys are blue, the scalar types
/// fan across the cool arc so a type change is visible without reading the token, and structure
/// is achromatic. The consequence is the point — any warm pixel in the editor means something is
/// wrong, so an error marker is the only warm thing on screen and needs no hunting.
struct SyntaxTheme: Sendable {

    /// A syntax token colour with its measured contrast ratio.
    ///
    /// `contrastRatio` is the **worst applicable case**: the lower of the ratio against the plain
    /// editor background and against every background wash that can sit under this token. That is
    /// the only figure that matters, since text is unreadable at its worst position, not its best.
    struct TokenColor: Sendable {
        var light: Color
        var dark: Color
        /// Worst applicable measured ratio. Text ≥ 4.5, non-text indicators ≥ 3.
        var contrastRatio: Double
        /// `true` where the token also carries a non-colour distinction (see `null`).
        var isItalic: Bool = false

        func color(for scheme: ColorScheme) -> Color {
            scheme == .dark ? dark : light
        }
    }

    // MARK: - Syntax tokens

    var objectKey: TokenColor
    var string: TokenColor
    var number: TokenColor
    var boolean: TokenColor
    var null: TokenColor
    var bracket: TokenColor
    var punctuation: TokenColor

    // MARK: - Background washes

    /// Washes are held to a different standard than text: subtle enough not to fight the text on
    /// top of them. `contrastRatio` here is measured against the editor background, and the
    /// requirement is a ceiling, not a floor.
    var currentLineBackground: TokenColor
    var selectionBackground: TokenColor
    var searchMatchBackground: TokenColor
    /// Deliberately stronger than the other washes — it only ever sits under a bracket glyph,
    /// which is the highest-contrast token in the palette.
    var matchedBracketBackground: TokenColor

    // MARK: - Diagnostic indicators

    /// Exempt from the chroma gate by design: Phase 0 established the error experience as the
    /// product, and a desaturated error marker is a worse error marker.
    var errorUnderline: TokenColor
    var warningUnderline: TokenColor
    var foldMarker: TokenColor

    /// The shipping palette. Light and dark were designed independently — dark is not an
    /// inversion of light.
    static let standard = SyntaxTheme(
        objectKey:   .init(light: .init(hex: 0x0B4FA8), dark: .init(hex: 0x7FB0F0), contrastRatio: 5.34),
        string:      .init(light: .init(hex: 0x0F6E3D), dark: .init(hex: 0x5FC98A), contrastRatio: 4.60),
        number:      .init(light: .init(hex: 0x63409C), dark: .init(hex: 0xC2A0F5), contrastRatio: 5.50),
        boolean:     .init(light: .init(hex: 0x04606E), dark: .init(hex: 0x5CC8D8), contrastRatio: 5.25),
        // Achromatic *and* italic, so it is distinguishable from punctuation without colour.
        null:        .init(light: .init(hex: 0x5C5C5C), dark: .init(hex: 0xA4A4A4), contrastRatio: 4.80, isItalic: true),
        bracket:     .init(light: .init(hex: 0x1F1F1F), dark: .init(hex: 0xE8E8E8), contrastRatio: 7.29),
        punctuation: .init(light: .init(hex: 0x5A5A5A), dark: .init(hex: 0xB0B0B0), contrastRatio: 5.01),

        currentLineBackground:   .init(light: .init(hex: 0xF2F4F7), dark: .init(hex: 0x282A2E), contrastRatio: 1.16),
        selectionBackground:     .init(light: .init(hex: 0xCCDDF7), dark: .init(hex: 0x2C3749), contrastRatio: 1.39),
        searchMatchBackground:   .init(light: .init(hex: 0xFFE9A8), dark: .init(hex: 0x3F361A), contrastRatio: 1.39),
        matchedBracketBackground: .init(light: .init(hex: 0xD6E4FA), dark: .init(hex: 0x3A4A66), contrastRatio: 1.87),

        errorUnderline:   .init(light: .init(hex: 0xC4162A), dark: .init(hex: 0xFF6B7A), contrastRatio: 6.01),
        warningUnderline: .init(light: .init(hex: 0x8A5A00), dark: .init(hex: 0xE0A64A), contrastRatio: 5.93),
        foldMarker:       .init(light: .init(hex: 0x767676), dark: .init(hex: 0x9A9A9A), contrastRatio: 4.54)
    )
}

/// The six validation/diff semantics. Each is colour **plus** SF Symbol **plus** text label.
///
/// Colour is the weakest of the three channels and never carries a state alone (locked decision
/// #10). This is not belt-and-braces: measured worst-case contrast *between* the four diff
/// colours is 1.00–1.12 across normal, deuteranopic, protanopic, and grayscale vision. Four
/// colours all holding 4.5:1 against one background are necessarily close in luminance, so they
/// cannot also be far apart from each other. Better hex values cannot fix this — the glyph and
/// the label are the signal, and the colour is recognition speed for readers who can use it.
///
/// The glyphs were chosen to differ in *silhouette* for the same reason.
enum Semantic: String, CaseIterable, Sendable {
    case valid
    case invalid
    case diffAdded
    case diffRemoved
    case diffModified
    case diffTypeChanged

    /// Never abbreviate and never hide these, at any window width or density setting.
    var label: String {
        switch self {
        case .valid: "Valid JSON"
        case .invalid: "Invalid JSON"
        case .diffAdded: "Added"
        case .diffRemoved: "Removed"
        case .diffModified: "Modified"
        case .diffTypeChanged: "Type changed"
        }
    }

    var symbol: String {
        switch self {
        case .valid: "checkmark.circle.fill"
        case .invalid: "exclamationmark.triangle.fill"
        case .diffAdded: "plus.circle.fill"
        case .diffRemoved: "minus.circle.fill"
        case .diffModified: "pencil.circle.fill"
        case .diffTypeChanged: "arrow.2.squarepath"
        }
    }

    /// Measured ≥ 4.5:1 against its mode's background as label text (light 6.01–7.78,
    /// dark 6.06–8.80).
    func color(for scheme: ColorScheme) -> Color {
        let (light, dark): (UInt32, UInt32) = switch self {
        case .valid:           (0x0F6E3D, 0x5FC98A)
        case .invalid:         (0xC4162A, 0xFF6B7A)
        case .diffAdded:       (0x1A6B33, 0x6ED08F)
        case .diffRemoved:     (0xA8102A, 0xFF8A94)
        case .diffModified:    (0x0B4FA8, 0x7FB0F0)
        case .diffTypeChanged: (0x8A4B00, 0xE0A64A)
        }
        return Color(hex: scheme == .dark ? dark : light)
    }
}

/// A semantic rendered as all three channels at once. Use this rather than reaching for
/// `Semantic.color` directly — it makes the colour-independence rule the path of least resistance.
struct SemanticBadge: View {
    let semantic: Semantic
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Label {
            Text(semantic.label)
        } icon: {
            Image(systemName: semantic.symbol)
        }
        .font(Tokens.Typography.uiSecondary)
        .foregroundStyle(semantic.color(for: scheme))
        .accessibilityLabel(semantic.label)
    }
}

extension Color {
    /// 0xRRGGBB convenience — used ONLY inside the syntax palette and the six semantics
    /// (locked decision #9).
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
