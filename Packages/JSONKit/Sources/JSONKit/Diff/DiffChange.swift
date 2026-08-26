/// One difference between two JSON documents, located by path. The four kinds map directly to
/// the four diff semantics in the design system (each colour + SF Symbol + label).
public struct DiffChange: Sendable, Equatable {
    public enum Kind: Sendable, Equatable, CaseIterable {
        case added
        case removed
        case modified
        case typeChanged
    }

    public var kind: Kind
    public var path: JSONPath

    public init(kind: Kind, path: JSONPath) {
        self.kind = kind
        self.path = path
    }
}
