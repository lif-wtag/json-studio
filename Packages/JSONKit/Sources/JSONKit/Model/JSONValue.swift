/// A parsed JSON value.
///
/// Two storage decisions carry consequences, both recorded in `Docs/PHASE-2-PLAN.md` §2:
///
/// **Numbers keep their source text.** `9007199254740993` is in the sample payload precisely
/// because `Double` cannot hold it. `.number` stores the literal; numeric interpretation is a
/// separate, caller-driven step that can fail loudly. A side effect worth knowing: `Equatable`
/// compares number *text*, so `1` and `1.0` are different values. That is correct for an editor.
///
/// **Strings store the decoded value.** `"café"` becomes `café`. Byte-exact round-tripping
/// is the formatter's job — it has the source and every node has a span, so an unmodified value is
/// re-emitted from its original bytes rather than re-encoded. Storing raw *and* decoded on every
/// string would cost memory on exactly the documents where memory matters.
public indirect enum JSONValue: Sendable, Equatable {
    /// Members are an **array**, not a dictionary: it preserves key order (which Format must not
    /// disturb) and duplicate keys (legal JSON, almost always a bug — VA-10). A dictionary would
    /// silently discard the evidence. Lookup is O(n); callers needing random access index it.
    case object([JSONMember])
    case array([JSONNode])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    /// The type, without the payload. Mirrors the inspector's type affordance so the UI can
    /// switch on one value rather than pattern-matching the whole enum.
    public enum Kind: String, Sendable, CaseIterable {
        case object, array, string, number, boolean, null
    }

    public var kind: Kind {
        switch self {
        case .object: .object
        case .array: .array
        case .string: .string
        case .number: .number
        case .bool: .boolean
        case .null: .null
        }
    }

    /// `true` for objects and arrays — the values that can be expanded, folded, and have children.
    public var isContainer: Bool {
        switch self {
        case .object, .array: true
        default: false
        }
    }

    /// Number of direct children. Zero for every scalar.
    public var childCount: Int {
        switch self {
        case .object(let members): members.count
        case .array(let elements): elements.count
        default: 0
        }
    }

    /// First member with this key, in document order. Returns nil rather than trapping, and
    /// deliberately ignores later duplicates — matching what a JSON consumer would see.
    public func member(_ key: String) -> JSONMember? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }
    }

    /// Every member with this key. More than one means a duplicate-key warning is due.
    public func members(_ key: String) -> [JSONMember] {
        guard case .object(let members) = self else { return [] }
        return members.filter { $0.key == key }
    }

    /// Element at `index`, or nil when out of range or not an array.
    public func element(at index: Int) -> JSONNode? {
        guard case .array(let elements) = self, elements.indices.contains(index) else { return nil }
        return elements[index]
    }
}
