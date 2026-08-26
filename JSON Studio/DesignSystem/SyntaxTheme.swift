import SwiftUI

/// The syntax highlighting palette and the six diff/validation semantics.
///
/// **This is the ONLY file where literal hex colours are allowed** (ADR-09). Everything else
/// uses AppKit semantic colours. The real palette is designed in Phase 1 with measured
/// contrast ratios (text ≥ 4.5:1, non-text indicators ≥ 3:1), light and dark authored
/// independently, keys and strings separated by hue. Values below are placeholders.
struct SyntaxTheme: Sendable {
    /// A syntax token colour. Phase 1 records `contrastRatio` (measured against the mode's
    /// editor background) alongside each value.
    struct TokenColor: Sendable {
        var light: Color
        var dark: Color
        var contrastRatio: Double   // measured; must clear the minimum for its role
    }

    var key: TokenColor
    var string: TokenColor
    var number: TokenColor
    var boolean: TokenColor
    var null: TokenColor
    var bracket: TokenColor
    var punctuation: TokenColor

    // Phase 1: matched-bracket highlight, current-line background, selection, error underline,
    // search match, fold marker — each with light/dark + measured ratio.

    /// Placeholder theme so the type is usable before Phase 1. Do not ship these values.
    static let placeholder = SyntaxTheme(
        key:         .init(light: .init(hex: 0x0F62FE), dark: .init(hex: 0x78A9FF), contrastRatio: 0),
        string:      .init(light: .init(hex: 0x24A148), dark: .init(hex: 0x42BE65), contrastRatio: 0),
        number:      .init(light: .init(hex: 0x8A3FFC), dark: .init(hex: 0xBE95FF), contrastRatio: 0),
        boolean:     .init(light: .init(hex: 0xD12771), dark: .init(hex: 0xFF7EB6), contrastRatio: 0),
        null:        .init(light: .init(hex: 0x6F6F6F), dark: .init(hex: 0x8D8D8D), contrastRatio: 0),
        bracket:     .init(light: .init(hex: 0x161616), dark: .init(hex: 0xF4F4F4), contrastRatio: 0),
        punctuation: .init(light: .init(hex: 0x525252), dark: .init(hex: 0xC6C6C6), contrastRatio: 0)
    )
}

/// The six validation/diff semantics. Each is colour **plus** SF Symbol **plus** text label —
/// colour alone is never sufficient (ADR-09 / colour-independence rule). Colours here are the
/// second permitted home for literal hex; Phase 1 verifies the diff four against deuteranopia
/// and protanopia.
enum Semantic: String, CaseIterable, Sendable {
    case valid
    case invalid
    case diffAdded
    case diffRemoved
    case diffModified
    case diffTypeChanged

    var label: String {
        switch self {
        case .valid: "Valid"
        case .invalid: "Invalid"
        case .diffAdded: "Added"
        case .diffRemoved: "Removed"
        case .diffModified: "Modified"
        case .diffTypeChanged: "Type changed"
        }
    }

    var symbol: String {
        switch self {
        case .valid: "checkmark.circle"
        case .invalid: "exclamationmark.triangle"
        case .diffAdded: "plus.circle"
        case .diffRemoved: "minus.circle"
        case .diffModified: "pencil.circle"
        case .diffTypeChanged: "arrow.triangle.2.circlepath.circle"
        }
    }
}

extension Color {
    /// 0xRRGGBB convenience — used ONLY inside the syntax palette and semantics (ADR-09).
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
