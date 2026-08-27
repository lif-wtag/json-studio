/// Aggregate counts over a JSON tree, rendered by the inspector's Statistics tab (IN-09) as a
/// typographic table — no charts.
///
/// Three counting rules are judgment calls rather than arithmetic, so they are stated here:
///
/// **Object keys are not counted as strings.** A key *is* a JSON string, but counting it would
/// double-count against `properties` and make `strings` mean something no reader expects. The
/// scalar counts are counts of **values**.
///
/// **`numbers` counts number tokens, not distinct numeric values.** `JSONValue.number` keeps its
/// source text (so `9007199254740993` survives), which also means `1` and `1.0` are two different
/// values. The Statistics tab is therefore reporting how many numbers were *written*, which is
/// the useful reading for a document inspector.
///
/// **`properties` counts every member, duplicates included.** Duplicate keys are legal JSON and
/// almost always a bug (VA-10); a count that quietly collapsed them would hide the evidence.
public struct Statistics: Sendable, Equatable {
    public var objects = 0
    public var arrays = 0
    /// Object members, across the whole document. Duplicate keys count once each.
    public var properties = 0
    public var strings = 0
    public var numbers = 0
    public var booleans = 0
    public var nulls = 0

    /// Container nesting levels. The outermost container is 1, and a scalar document is 0.
    ///
    /// **This is not `JSONNode.depth`.** That measures the longest chain to a leaf and so reports
    /// `{"a":{}}` as 1; this reports 2, because an empty object nested in another object plainly
    /// *is* two levels of nesting. They coincide on most documents — both give 7 for the sample
    /// payload, which is the figure the approved artboard renders — and diverge exactly when the
    /// deepest thing in the document is an empty container.
    public var maxDepth = 0

    /// Length of the root value in **UTF-16 code units**, the unit every measurement in JSONKit
    /// uses (ADR-01). It excludes whitespace outside the root value.
    ///
    /// Not grapheme clusters: the sample payload is 3,719 code units and 3,716 Characters, because
    /// of its emoji. A UI that labels this "Characters" should say which, or take a grapheme count
    /// from the document layer, which has the source text and the file size already.
    public var characterCount = 0

    public init() {}

    /// Every value in the document, containers included. Equals the node count of the tree.
    public var totalValues: Int {
        objects + arrays + strings + numbers + booleans + nulls
    }
}

/// Walks a tree once, off the main actor, producing `Statistics`.
///
/// **One walk, not one per statistic**, and **iterative** — ADR-01 Amendment 1a: any JSONKit walk
/// whose depth follows the document's nesting keeps its stack on the heap, because a recursive
/// one overflows a debug build's 512 KB concurrency-thread stack well before `Parser.maxDepth`.
/// Note that this rules out reaching for `JSONNode.depth` to fill in `maxDepth`, since that
/// property recurses; the depth is accumulated in the same pass instead.
public struct StatisticsWalker: Sendable {

    /// Cancellation is checked every this many values. Cheap but not free, and a 1 MB walk is
    /// budgeted at 50 ms, so a coarser granularity than the parser's is still responsive.
    private static let cancellationInterval = 8192

    public init() {}

    /// Counts everything in `node`.
    ///
    /// Throws `CancellationError` rather than returning a partial `Statistics` (ADR-09 names
    /// statistics as cancellable work). Half a count is not a smaller count — it is a wrong one,
    /// and showing it in the inspector would be worse than showing nothing.
    public func walk(_ node: JSONNode) throws -> Statistics {
        var stats = Statistics()
        stats.characterCount = node.span.length

        // (value, number of containers enclosing it). The root is enclosed by none.
        var stack: [(node: JSONNode, level: Int)] = [(node, 0)]
        stack.reserveCapacity(64)
        var sinceCancellationCheck = 0

        while let (current, level) = stack.popLast() {
            sinceCancellationCheck += 1
            if sinceCancellationCheck >= Self.cancellationInterval {
                sinceCancellationCheck = 0
                try Task.checkCancellation()
            }

            switch current.value {
            case .object(let members):
                stats.objects += 1
                stats.properties += members.count
                stats.maxDepth = max(stats.maxDepth, level + 1)
                for member in members { stack.append((member.node, level + 1)) }

            case .array(let elements):
                stats.arrays += 1
                stats.maxDepth = max(stats.maxDepth, level + 1)
                for element in elements { stack.append((element, level + 1)) }

            case .string:
                stats.strings += 1
            case .number:
                stats.numbers += 1
            case .bool:
                stats.booleans += 1
            case .null:
                stats.nulls += 1
            }
        }
        return stats
    }

    /// Counts a parse result. Returns nil when there is no tree, so an empty document reports as
    /// "nothing to count" rather than as a document of all zeroes.
    public func walk(_ result: ParseResult) throws -> Statistics? {
        try result.tree.map { try walk($0) }
    }
}
