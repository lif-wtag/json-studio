import Foundation

/// Whether the file on disk still holds what the app believes it holds (DC-10).
///
/// **`nonisolated`, like `DocumentStatus`** — the app target is MainActor-by-default, and reading a
/// file is not main-thread work.
///
/// The whole difficulty of this feature is telling *someone else's* write from our own, and the
/// answer is not a timestamp. An atomic save replaces the inode, `git checkout` can restore a file
/// byte-identical with a fresh modification date, and an editor that writes the same bytes twice
/// has changed nothing. So the comparison is on **content**, with the cheap attribute check used
/// only to decide whether reading is worth it.
nonisolated enum ExternalChange {

    enum Outcome: Equatable {
        /// Disk matches what we last read or wrote.
        case unchanged
        /// Someone else has written to it. Carries what is there now.
        case changed(Data)
        /// Deleted, moved, or renamed. **Not** an alert — there is nothing to reload, and the
        /// document keeps what it has. `DocumentGroup` handles saving back to a vanished path.
        case missing
    }

    /// A cheap attribute snapshot, so the common case never reads the file.
    ///
    /// The monitor polls every couple of seconds for the life of a window; re-reading a 5 MB
    /// document each time would be megabytes a second of pointless I/O. Unequal attributes are
    /// only a reason to *look* — the answer still comes from comparing bytes.
    struct Revision: Equatable, Sendable {
        var size: Int
        var modified: Date

        static func read(_ url: URL) -> Revision? {
            // **A fresh `URL`, deliberately.** `URL` caches resource values on the instance, so
            // asking the same one twice can hand back what was true before the file changed — or
            // before it was deleted. The monitor holds one `URL` for the life of the window, which
            // is exactly the shape that trips over this.
            let uncached = URL(fileURLWithPath: url.path)
            guard let values = try? uncached.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                  ),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate
            else { return nil }
            return Revision(size: size, modified: modified)
        }
    }

    /// Compare the file at `url` against `lastKnown` — the bytes the app last read from it or
    /// wrote to it.
    ///
    /// Deliberately compares the bytes rather than trusting `Revision`: equal attributes are strong
    /// evidence of no change, but *unequal* ones are no evidence of a change at all.
    static func inspect(url: URL, lastKnown: Data?) -> Outcome {
        guard let current = try? Data(contentsOf: url) else { return .missing }
        guard let lastKnown else { return .changed(current) }
        return current == lastKnown ? .unchanged : .changed(current)
    }
}
