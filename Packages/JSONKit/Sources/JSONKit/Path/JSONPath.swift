/// A path into a JSON document, rendered in `$.a.b[0]` form.
///
/// This is the string a developer copies out of the inspector (IN-08) and reads in the path bar
/// (IN-15), so its job is legibility, not machine round-tripping. Two consequences follow:
///
/// **Duplicate keys make a path ambiguous, and that is left visible.** `{"a": 1, "a": 2}` gives
/// both members the path `$.a`, and `PathResolver` resolves `$.a` to the first. Numbering them
/// `$.a[#2]` would invent syntax no other tool understands in order to paper over a document
/// that is almost certainly wrong — which is what the duplicate-key warning (VA-10) is for. The
/// UI navigates by span, not by re-resolving a path, so nothing depends on the ambiguity.
///
/// **There is no parser here.** Reading a path back from text is JSONPath *querying*, which is a
/// Phase 5 feature (SR-06) with its own grammar, wildcards and filters. Building half of it now
/// would be a second, weaker implementation to delete later.
public struct JSONPath: Sendable, Hashable, CustomStringConvertible {
    public enum Component: Sendable, Hashable {
        case key(String)
        case index(Int)
    }

    public var components: [Component]

    public init(_ components: [Component] = []) {
        self.components = components
    }

    /// The root path, `$`.
    public static let root = JSONPath()

    public var isRoot: Bool { components.isEmpty }

    public var description: String {
        var out = "$"
        for component in components {
            switch component {
            case .key(let key):
                out += JSONPath.isBareIdentifier(key) ? ".\(key)" : "[\(JSONPath.quoted(key))]"
            case .index(let index):
                out += "[\(index)]"
            }
        }
        return out
    }

    /// `true` for a key that can follow a dot unambiguously. Deliberately conservative: a key
    /// starting with a digit is bracketed, because `$.1` reads like an index and isn't one.
    static func isBareIdentifier(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first else { return false }   // "" is never bare
        guard first == "_" || ("a"..."z").contains(first) || ("A"..."Z").contains(first) else {
            return false
        }
        return key.unicodeScalars.allSatisfy {
            $0 == "_" || ("a"..."z").contains($0) || ("A"..."Z").contains($0)
                || ("0"..."9").contains($0)
        }
    }

    /// A double-quoted key. Double quotes rather than single so the rendering reads like the
    /// JSON it came from, and so pasting it into a JSON-aware tool stands a chance.
    static func quoted(_ key: String) -> String {
        var out = "\""
        for character in key {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default: out.append(character)
            }
        }
        return out + "\""
    }
}

