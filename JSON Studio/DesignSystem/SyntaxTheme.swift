import SwiftUI

/// The syntax highlighting palette and the six diff/validation semantics.
///
/// **This is the only file where literal hex colours are allowed** (locked decision #9).
/// Values come from the approved Claude Design project ("JSON Studio — Run 1"), reconciled in
/// `Design/tokens.md`, which is the specification and wins on any disagreement. Every
/// `contrastRatio` is *measured* by `Design/palette-measure.py` — re-run it after any change here,
/// it fails loudly.
///
/// The design's hue logic: structure — keys, braces, punctuation — stays on the blurple-to-neutral
/// axis, and the leaf types fan away from it by distance from "text": strings green-teal, numbers
/// amber, booleans magenta, null a chroma-free grey. A wall of quoted values therefore separates
/// from its keys by hue rather than by weight, and no two adjacent types share a neighbourhood.
///
/// Six values here differ from the design. The design's own current-line and selection washes
/// dropped four tokens below 4.5:1 (punctuation reached 3.39 in dark), and a wash sits under text.
/// Each fix moves lightness only — hue drift is ≤1.6° — so the grammar logic is untouched.
/// `Design/tokens.md` §3 records each one.
struct SyntaxTheme: Sendable {

    /// A colour with its measured contrast ratio.
    ///
    /// `contrastRatio` is the **worst applicable case**: the lowest ratio across the bare editor
    /// ground and every wash this token can actually sit under. Text is unreadable at its worst
    /// position, not its best.
    struct TokenColor: Sendable {
        var light: Color
        var dark: Color
        /// Worst measured ratio. Text ≥ 4.5; non-text indicators ≥ 3.
        var contrastRatio: Double
        /// Set where the token carries a second, non-colour distinction — see `null`.
        var isItalic: Bool = false

        func color(for scheme: ColorScheme) -> Color {
            scheme == .dark ? dark : light
        }
    }

    // MARK: - Grounds

    /// The editor ground. **Not `textBackgroundColor`** — a blue-grey at 4% chroma in dark,
    /// an off-white in light. Every ratio in this file is measured against it, which is why it
    /// cannot be swapped for the semantic colour without re-measuring the whole palette.
    /// `Design/tokens.md` §7 FLAG-1 — needs an ADR before Phase 3b.
    var editorGround: TokenColor

    // MARK: - Syntax tokens

    var objectKey: TokenColor
    var string: TokenColor
    var number: TokenColor
    var boolean: TokenColor
    var null: TokenColor
    var bracket: TokenColor
    var punctuation: TokenColor

    // MARK: - Washes

    /// Spans the whole line, so every token must stay readable on it.
    var currentLineBackground: TokenColor
    /// A 1px edge the design pairs with the current-line fill.
    var currentLineEdge: TokenColor
    var selectionBackground: TokenColor
    /// Scoped to a matched span, not the line — so only keys and strings sit on it.
    var searchMatchBackground: TokenColor
    var activeMatchBackground: TokenColor
    /// The active match's ring carries "this one" in dark mode, where a heavier fill would
    /// fight the light text on it.
    var activeMatchRing: TokenColor
    /// A **1px ring**, not a fill — so it never sits under text.
    var matchedBracketRing: TokenColor

    // MARK: - Diagnostics

    /// Chroma-exempt by design: a desaturated error marker is a worse error marker.
    var errorUnderline: TokenColor
    /// Light sits exactly on the 3:1 floor (3.00) — do not darken the light ground beneath it.
    var foldMarker: TokenColor

    /// The shipping palette. Light and dark were authored independently; dark is not an inversion.
    static let standard = SyntaxTheme(
        editorGround: .init(light: .init(hex: 0xF7F7FA), dark: .init(hex: 0x161826), contrastRatio: 1),

        objectKey:   .init(light: .init(hex: 0x5B44C8), dark: .init(hex: 0xB3A8F0), contrastRatio: 4.54),
        string:      .init(light: .init(hex: 0x0A6551), dark: .init(hex: 0x6ED3AE), contrastRatio: 4.72),
        number:      .init(light: .init(hex: 0x8C4700), dark: .init(hex: 0xEFB275), contrastRatio: 4.68),
        boolean:     .init(light: .init(hex: 0x9C2F72), dark: .init(hex: 0xE79AC9), contrastRatio: 4.61),
        // Achromatic *and* italic, so it separates from punctuation — also achromatic — without colour.
        null:        .init(light: .init(hex: 0x55596C), dark: .init(hex: 0x9EA6BE), contrastRatio: 4.65, isItalic: true),
        bracket:     .init(light: .init(hex: 0x3A3D4D), dark: .init(hex: 0xCBCFE0), contrastRatio: 7.22),
        punctuation: .init(light: .init(hex: 0x55596A), dark: .init(hex: 0xA1A6BA), contrastRatio: 4.66),

        currentLineBackground: .init(light: .init(hex: 0xEFEFF5), dark: .init(hex: 0x1D2033), contrastRatio: 1.07),
        currentLineEdge:       .init(light: .init(hex: 0xDEDEE8), dark: .init(hex: 0x2A2E45), contrastRatio: 1.25),
        selectionBackground:   .init(light: .init(hex: 0xCBD3F0), dark: .init(hex: 0x2E3768), contrastRatio: 1.39),
        // Composited from the design's alpha fills at the opacities recorded in tokens.md §3.
        searchMatchBackground: .init(light: .init(hex: 0xF1E4B4), dark: .init(hex: 0x3A3428), contrastRatio: 1.19),
        activeMatchBackground: .init(light: .init(hex: 0xF3CF90), dark: .init(hex: 0x4A412F), contrastRatio: 1.39),
        activeMatchRing:       .init(light: .init(hex: 0xA85A00), dark: .init(hex: 0xF0C24A), contrastRatio: 4.76),
        matchedBracketRing:    .init(light: .init(hex: 0x6E5FD8), dark: .init(hex: 0x8C86D6), contrastRatio: 4.58),

        errorUnderline: .init(light: .init(hex: 0xC22E2E), dark: .init(hex: 0xF2705E), contrastRatio: 5.27),
        foldMarker:     .init(light: .init(hex: 0x8A8FA3), dark: .init(hex: 0x8B92AC), contrastRatio: 3.00)
    )
}

/// The six validation/diff semantics.
///
/// Each carries colour **plus** SF Symbol **plus** label, and the diff four additionally carry a
/// gutter sign and row-tint lightness. That triple redundancy is not belt-and-braces: measured
/// worst-case contrast *between* the four diff colours is 1.00–1.10 across normal, deuteranopic,
/// protanopic and grayscale vision. Four colours all holding 4.5:1 against one ground are
/// necessarily close in luminance, so they cannot also be far from each other. No choice of hex
/// fixes it — the design reached the same conclusion, which is why it specifies three carriers.
///
/// The design reuses syntax hues here: `diffModified` is the number amber, `diffTypeChanged` the
/// object-key blurple, and added/removed the valid/invalid pair.
enum Semantic: String, CaseIterable, Sendable {
    case valid
    case invalid
    case diffAdded
    case diffRemoved
    case diffModified
    case diffTypeChanged

    /// Never abbreviate and never hide these, at any window width or density.
    ///
    /// `invalid` and `diffTypeChanged` are dynamic in the design — the label states the error
    /// count and location, and names the actual type transition. These are the fallbacks used
    /// when no detail is available; prefer `label(detail:)`.
    var label: String {
        switch self {
        case .valid: "Valid JSON"
        case .invalid: "Invalid JSON"
        case .diffAdded: "Added"
        case .diffRemoved: "Removed"
        case .diffModified: "Changed"
        case .diffTypeChanged: "Type changed"
        }
    }

    /// The design's labels for these two states name specifics rather than categories:
    /// "1 error · line 10" and "string → number".
    func label(detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return label }
        switch self {
        case .invalid, .diffTypeChanged: return detail
        default: return label
        }
    }

    var symbol: String {
        switch self {
        case .valid: "checkmark.circle"
        case .invalid: "exclamationmark.triangle"
        case .diffAdded: "plus.square"
        case .diffRemoved: "minus.square"
        case .diffModified: "pencil.line"
        case .diffTypeChanged: "arrow.triangle.swap"
        }
    }

    /// The gutter sign for diff rows — a third carrier, independent of both colour and glyph.
    var gutterSign: String? {
        switch self {
        case .diffAdded: "+"
        case .diffRemoved: "\u{2212}"   // minus sign, not hyphen
        default: nil
        }
    }

    /// Measured ≥4.5:1 against its mode's ground as label text (light 4.99–6.51, dark 6.08–9.47).
    func color(for scheme: ColorScheme) -> Color {
        let (light, dark): (UInt32, UInt32) = switch self {
        case .valid:           (0x1C7A4B, 0x5FD39B)
        case .invalid:         (0xC22E2E, 0xF2705E)
        case .diffAdded:       (0x1C7A4B, 0x5FD39B)
        case .diffRemoved:     (0xC22E2E, 0xF2705E)
        case .diffModified:    (0x8C4700, 0xEFB275)
        case .diffTypeChanged: (0x5B44C8, 0xB3A8F0)
        }
        return Color(hex: scheme == .dark ? dark : light)
    }
}

/// A semantic rendered as every channel at once. Prefer this over reaching for `Semantic.color`
/// directly — it makes the colour-independence rule the path of least resistance rather than a
/// review checklist item.
struct SemanticBadge: View {
    let semantic: Semantic
    /// Supplies the dynamic text for `invalid` and `diffTypeChanged`.
    var detail: String? = nil
    /// Diff rows show the gutter sign; status-bar states do not.
    var showsGutterSign: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let text = semantic.label(detail: detail)
        HStack(spacing: Tokens.Spacing.xs) {
            if showsGutterSign, let sign = semantic.gutterSign {
                Text(sign)
                    .font(Tokens.Typography.gutterNumber)
                    .accessibilityHidden(true)
            }
            Image(systemName: semantic.symbol)
            Text(text)
        }
        .font(Tokens.Typography.uiSecondary)
        .foregroundStyle(semantic.color(for: scheme))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// The tree's per-node type affordance: SF Symbol plus the matching syntax colour.
///
/// Maps the design's Phosphor prototype icons onto SF Symbols. `array` is the one unfaithful
/// mapping — SF Symbols has no square-bracket glyph. `Design/tokens.md` §5 records the
/// alternative (literal `{}` / `[]` set in SF Mono); decide before Phase 3d.
enum NodeKind: String, CaseIterable, Sendable {
    case object, array, string, number, boolean, null

    var symbol: String {
        switch self {
        case .object: "curlybraces"
        case .array: "list.bullet.indent"
        case .string: "quote.opening"
        case .number: "number"
        case .boolean: "switch.2"
        case .null: "circle.dashed"
        }
    }

    /// Spoken by VoiceOver alongside the node's name, value and depth.
    var accessibilityName: String {
        switch self {
        case .object: "Object"
        case .array: "Array"
        case .string: "String"
        case .number: "Number"
        case .boolean: "Boolean"
        case .null: "Null"
        }
    }

    func color(for scheme: ColorScheme, theme: SyntaxTheme = .standard) -> Color {
        let token = switch self {
        case .object, .array: theme.bracket
        case .string: theme.string
        case .number: theme.number
        case .boolean: theme.boolean
        case .null: theme.null
        }
        return token.color(for: scheme)
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
