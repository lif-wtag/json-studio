/// How the structural diff pairs up array elements — the hard part of diffing (CP-04).
///
///  - `index`:        position i vs position i. Right for fixed-shape tuples and positional data.
///  - `identityKey`:  match objects by a stable key (e.g. `"id"`). Right for arrays of records,
///                    where index-wise matching turns one insertion into a cascade of noise.
///  - `heuristic`:    LCS over per-element digests. Right when there's no identity key but order
///                    is meaningful.
///
/// The choice is a **parameter, not something the engine guesses**, because 3e exposes it in the
/// UI: for arrays of records the difference between identity-key and index-wise matching is the
/// difference between a useful diff and noise, and only the person reading the data knows which
/// their array is.
///
/// **`identityKey` and `heuristic` are not implemented yet — Task 10.** Until then
/// `StructuralDiff` treats them as `index` and says so in its own documentation, rather than
/// failing: JSONKit is not yet linked into the app (Phase 3a), so no caller can be misled, and a
/// visible fallback with a test asserting it beats a `fatalError` on a half-built feature.
public enum ArrayMatching: Sendable, Equatable {
    case index
    case identityKey(String)
    case heuristic

    /// `true` while this strategy still falls back to index-wise pairing (Task 10 removes this).
    public var isImplemented: Bool {
        if case .index = self { return true }
        return false
    }
}
