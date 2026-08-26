/// Resolves between source offsets and paths, in both directions (both tested in Phase 2):
///  - `path(at:)`  — the JSON path of the innermost node containing a UTF-16 offset
///                   (drives editor cursor → tree selection and path-from-cursor).
///  - `span(of:)`  — the source span a path points at
///                   (drives tree selection → editor highlight).
public struct PathResolver: Sendable {
    public let root: JSONNode

    public init(root: JSONNode) {
        self.root = root
    }

    public func path(at offset: Int) -> JSONPath? {
        // TODO Phase 2
        _ = offset
        return nil
    }

    public func span(of path: JSONPath) -> SourceSpan? {
        // TODO Phase 2
        _ = path
        return nil
    }
}
