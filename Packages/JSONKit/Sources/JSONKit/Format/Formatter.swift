/// Pretty-prints or minifies a JSON tree. Round-trip must be exact (Phase 2 property test).
public struct Formatter: Sendable {
    public var options: FormatOptions

    public init(options: FormatOptions = .pretty) {
        self.options = options
    }

    public func format(_ node: JSONNode) -> String {
        // TODO Phase 2
        _ = node
        return ""
    }
}
