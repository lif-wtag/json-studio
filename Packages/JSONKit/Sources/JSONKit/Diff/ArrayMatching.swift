/// How the structural diff pairs up array elements — the hard part of diffing (CP-04), and a
/// High-likelihood risk in the build guide's register precisely because getting it wrong turns a
/// useful diff into noise.
///
/// **The choice is a parameter, never a guess the engine makes.** 3e exposes it in the compare
/// workspace — the artboard draws a "Match arrays by" control — because only the person reading
/// the data knows whether their array is a sequence or a set of records.
///
/// | Strategy | Pairs elements by | Right when |
/// |---|---|---|
/// | `index` | position `i` vs position `i` | Fixed-shape tuples and positional data: a coordinate pair, an RGB triple, a fixed column order. Position *is* the meaning. |
/// | `identityKey` | the value of a named key | Arrays of records with a stable id. This is the case the design calls out: pairing by `id` means a reordered array reads as **"Identical · 0 changes"** instead of 32 changes. |
/// | `heuristic` | longest common subsequence of equal elements, then position within each gap | Order is meaningful but there is no id — a log, a changelog, an ordered list. An insertion shows as one addition rather than shifting everything after it. |
///
/// **Reordering under `identityKey` produces an empty diff**, which is the design's stated
/// behaviour, not an omission: the four diff semantics are added, removed, modified and
/// type-changed, and there is no "moved" badge to render. If move detection is ever wanted it is
/// a design change — a fifth semantic with its own colour, glyph and label — not an engine change.
public enum ArrayMatching: Sendable, Equatable {
    /// Position `i` against position `i`.
    case index
    /// Match objects by the value of this key. Elements that are not objects, or lack the key,
    /// fall back to positional pairing among themselves.
    case identityKey(String)
    /// Longest common subsequence over element equality, with positional pairing inside the gaps
    /// so an edited element reads as `modified` rather than as a removal plus an addition.
    case heuristic
}
