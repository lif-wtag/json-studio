/// Aggregate counts over a JSON tree, rendered by the inspector's Statistics tab (IN-09) as a
/// typographic table — no charts.
public struct Statistics: Sendable, Equatable {
    public var objects = 0
    public var arrays = 0
    public var properties = 0
    public var strings = 0
    public var numbers = 0
    public var booleans = 0
    public var nulls = 0
    public var maxDepth = 0
    public var characterCount = 0

    public init() {}
}

/// Walks a tree once, off the main actor, producing `Statistics`.
public struct StatisticsWalker: Sendable {
    public init() {}

    public func walk(_ node: JSONNode) -> Statistics {
        // TODO Phase 2
        _ = node
        return Statistics()
    }
}
