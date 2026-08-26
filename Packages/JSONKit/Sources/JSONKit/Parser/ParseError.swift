/// A single syntax error. Carries everything the UI needs to locate and explain the problem:
/// offset, line/column, the token found, the set of tokens that were expected, and a
/// human-readable message drawn from `Design/error-copy.md` (never improvised in code).
public struct ParseError: Sendable, Equatable, Error {
    public var offset: Int
    public var line: Int
    public var column: Int
    public var found: Token.Kind?
    public var expected: [Token.Kind]
    public var message: String

    public init(
        offset: Int,
        line: Int,
        column: Int,
        found: Token.Kind? = nil,
        expected: [Token.Kind] = [],
        message: String
    ) {
        self.offset = offset
        self.line = line
        self.column = column
        self.found = found
        self.expected = expected
        self.message = message
    }
}
