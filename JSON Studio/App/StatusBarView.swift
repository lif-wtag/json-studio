import JSONKit
import SwiftUI

/// The status bar (SH-04): validity · properties · size · encoding, then cursor · indent mode.
///
/// **Never glass** (ADR-08) and never colour alone (locked decision #10) — the validity state is
/// a glyph *and* a label, and the label is the only thing that changes size, so the bar does not
/// reflow as a document goes in and out of validity.
///
/// Clicking to navigate to the first error is **Task 24**, along with the underlines and the ruler
/// markers it has to agree with. This renders the states; it does not yet act on them.
struct StatusBarView: View {
    let status: DocumentStatus
    var cursor: CursorPosition = CursorPosition()
    var indent: FormatOptions.Indent = .spaces(2)

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale

    var body: some View {
        let segments = StatusBarSegments.make(
            status: status, cursor: cursor, indent: indent, locale: locale
        )

        HStack(spacing: Tokens.Spacing.s) {
            if let semantic = status.semantic {
                Image(systemName: semantic.statusBarSymbol)
                    .font(Tokens.Typography.statusBarLabel)
                    .foregroundStyle(semantic.color(for: scheme))
            }
            run(segments.leading, tint: status.semantic?.color(for: scheme))

            Spacer(minLength: Tokens.Spacing.s)

            run(segments.trailing, tint: nil)
        }
        .padding(.horizontal, Tokens.Spacing.s + Tokens.Spacing.xxs)
        .frame(height: Tokens.Layout.statusBarHeight)
        .frame(maxWidth: .infinity)
        .background(Tokens.Surface.window)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.accessibilityText)
    }

    /// One group of segments, interleaved with the design's dim middle dot.
    ///
    /// `tint` colours the **first** segment only — the validity label. Everything after it is
    /// secondary, so the one thing worth glancing at is the one thing that carries colour.
    @ViewBuilder
    private func run(_ segments: [StatusBarSegments.Segment], tint: Color?) -> some View {
        HStack(spacing: Tokens.Spacing.s) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text(verbatim: "·")
                        .font(Tokens.Typography.statusBarLabel)
                        .foregroundStyle(.tertiary)
                }
                Text(segment.text)
                    .font(segment.isFigure
                          ? Tokens.Typography.statusBarFigure
                          : Tokens.Typography.statusBarLabel)
                    .foregroundStyle(index == 0 ? (tint ?? .secondary) : .secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

extension Semantic {
    /// The filled variant, which `Design/error-copy.md` §Status bar names explicitly for this
    /// context. It differs from `symbol` — the stroked glyph the artboard draws and the diff rows
    /// use — because at 11pt on a 24pt bar the filled form is the one that reads. The copy
    /// document is the more specific source here, so it wins.
    var statusBarSymbol: String {
        switch self {
        case .valid: "checkmark.circle.fill"
        case .invalid: "exclamationmark.triangle.fill"
        default: symbol
        }
    }
}

#Preview("Valid") {
    // The fixture's own figures, which are also the ones the artboard renders.
    var statistics = Statistics()
    statistics.properties = 119
    statistics.maxDepth = 7
    return StatusBarView(
        status: DocumentStatus(
            validity: .valid, statistics: statistics, byteCount: 3719, encoding: .utf8
        ),
        cursor: CursorPosition(line: 30, column: 20)
    )
    .frame(width: 720)
}

#Preview("Invalid") {
    StatusBarView(
        status: DocumentStatus(
            validity: .invalid(errorCount: 1, firstLine: 42, firstColumn: 18),
            byteCount: 3719,
            encoding: .utf16LittleEndian
        )
    )
    .frame(width: 720)
}
