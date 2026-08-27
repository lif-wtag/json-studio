/// One difference between two JSON documents, located by path. The four kinds map directly to
/// the four diff semantics in the design system (each colour + SF Symbol + label).
///
/// **Both sides are carried, not just the path.** The compare workspace (3e) needs them: it
/// anchors its synchronised scrolling on matched nodes rather than on line numbers, because the
/// two documents differ in length, and it renders the old and new values side by side. Each side
/// is a `JSONNode`, so its span comes along — spans in `before` index the **left** document and
/// spans in `after` index the **right** one, which is the one thing a consumer must not mix up.
///
/// **No user-facing copy here.** The design gives `.modified` the label "Changed" (not
/// "Modified") and gives `.typeChanged` a *dynamic* label naming the transition — "string →
/// number". JSONKit supplies the two `JSONValue.Kind`s and the UI composes that string from
/// their raw values, the same division of labour as `ParseError` and `ParseErrorCopy`.
public struct DiffChange: Sendable, Equatable {
    public enum Kind: Sendable, Equatable, CaseIterable {
        /// Present on the right, absent on the left.
        case added
        /// Present on the left, absent on the right.
        case removed
        /// Same type, different value.
        case modified
        /// Different type. Reported instead of recursing — a string that became an object has no
        /// meaningful child-level diff.
        case typeChanged
    }

    public var kind: Kind
    public var path: JSONPath
    /// The node in the **left** document. Nil for `.added`.
    public var before: JSONNode?
    /// The node in the **right** document. Nil for `.removed`.
    public var after: JSONNode?

    public init(kind: Kind, path: JSONPath, before: JSONNode? = nil, after: JSONNode? = nil) {
        self.kind = kind
        self.path = path
        self.before = before
        self.after = after
    }

    /// The type on each side. For `.typeChanged` these differ, and the UI's dynamic label is
    /// built from their raw values — `"\(from.rawValue) → \(to.rawValue)"`.
    public var typeTransition: (from: JSONValue.Kind, to: JSONValue.Kind)? {
        guard kind == .typeChanged, let before, let after else { return nil }
        return (before.kind, after.kind)
    }
}
