/// A path into a JSON document, rendered in `$.a.b[0]` form.
public struct JSONPath: Sendable, Equatable, CustomStringConvertible {
    public enum Component: Sendable, Equatable {
        case key(String)
        case index(Int)
    }

    public var components: [Component]

    public init(_ components: [Component] = []) {
        self.components = components
    }

    public var description: String {
        // TODO Phase 2: bracket-quote keys that aren't identifiers, e.g. $["with space"].
        var out = "$"
        for component in components {
            switch component {
            case .key(let k): out += ".\(k)"
            case .index(let i): out += "[\(i)]"
            }
        }
        return out
    }
}
