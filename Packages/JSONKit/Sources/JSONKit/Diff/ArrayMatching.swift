/// How the structural diff pairs up array elements — the hard part of diffing (CP-04).
///
///  - `index`:        position i vs position i. Right for fixed-shape tuples and positional data.
///  - `identityKey`:  match objects by a stable key (e.g. `"id"`). Right for arrays of records,
///                    where index-wise matching turns one insertion into a cascade of noise.
///  - `heuristic`:    LCS over per-element digests. Right when there's no identity key but order
///                    is meaningful.
public enum ArrayMatching: Sendable, Equatable {
    case index
    case identityKey(String)
    case heuristic
}
