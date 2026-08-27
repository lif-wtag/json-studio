/// Strips nulls, empty strings, and empty collections from a tree (FM-08). Each rule is
/// independently toggleable so the UI can offer them separately.
///
/// **Pruning cascades, because it works bottom-up.** With `stripNulls` and `stripEmptyCollections`
/// both on, `{"a":{"b":null}}` becomes `{"a":{}}` and then `{}` in the *same* pass — the inner
/// object is emptied before its parent is asked whether to keep it. Anything else would need the
/// user to run the command twice to reach a fixed point, and would break idempotence.
///
/// **Array elements are pruned too, which shifts indices.** `[1,null,2]` becomes `[1,2]`. That is
/// a real change to positional data and is the honest reading of "strip nulls" — but it is worth
/// knowing before running it over a fixed-shape tuple.
///
/// **The root can prune away**, so `pruned(_:)` returns an optional: pruning `null` with
/// `stripNulls` leaves no document at all. Returning an empty object instead would be inventing
/// content the user never wrote.
///
/// Spans are preserved — see `TreeTransform` for why that is load-bearing rather than tidy.
public struct Pruner: Sendable {
    public var stripNulls: Bool
    public var stripEmptyStrings: Bool
    public var stripEmptyCollections: Bool

    public init(
        stripNulls: Bool = true,
        stripEmptyStrings: Bool = false,
        stripEmptyCollections: Bool = false
    ) {
        self.stripNulls = stripNulls
        self.stripEmptyStrings = stripEmptyStrings
        self.stripEmptyCollections = stripEmptyCollections
    }

    /// `nil` when the whole document pruned away.
    public func pruned(_ node: JSONNode) -> JSONNode? {
        TreeTransform.rebuild(
            node,
            rebuildObject: { members, span in
                let rebuilt = JSONNode(value: .object(members), span: span)
                return stripEmptyCollections && members.isEmpty ? nil : rebuilt
            },
            rebuildArray: { elements, span in
                let rebuilt = JSONNode(value: .array(elements), span: span)
                return stripEmptyCollections && elements.isEmpty ? nil : rebuilt
            },
            keepScalar: { scalar in
                switch scalar.value {
                case .null: !stripNulls
                case .string(let text): !(stripEmptyStrings && text.isEmpty)
                default: true
                }
            }
        )
    }

    /// `true` when no rule is enabled, so a caller can skip the walk entirely.
    public var isNoOp: Bool {
        !stripNulls && !stripEmptyStrings && !stripEmptyCollections
    }
}
