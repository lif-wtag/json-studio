/// A parsed JSON value.
///
/// `number` keeps the **original source text** rather than a `Double` so that large
/// integers such as `9007254740993` survive round-trips without precision loss — a
/// requirement of the Phase 1 sample payload. Numeric interpretation is a separate,
/// caller-driven step.
public indirect enum JSONValue: Sendable, Equatable {
    case object([JSONMember])
    case array([JSONNode])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}
