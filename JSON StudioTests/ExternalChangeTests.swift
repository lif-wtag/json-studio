import Foundation
import Testing
@testable import JSON_Studio

// Task 18. The whole difficulty of DC-10 is telling someone else's write from our own, and getting
// it wrong turns every save into a dialog. So that distinction is what is tested, against real
// files in a temporary directory — a mock filesystem would not reproduce the case that matters,
// which is an atomic replace.
//
// Deliberately nonisolated: `ExternalChange` touches no UI, and this bundle stops scheduling
// main-actor tests past the four that already exist (see RUN_LOG 2026-08-27, Task 17).

@Suite("External change")
struct ExternalChangeTests {

    /// A file in a fresh temporary directory, removed afterwards.
    private func withTemporaryFile(
        _ contents: Data,
        _ body: (URL) throws -> Void
    ) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("json-studio-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("payload.json")
        try contents.write(to: url)
        try body(url)
    }

    private let original = Data(#"{"a":1}"#.utf8)
    private let rewritten = Data(#"{"a":2}"#.utf8)

    // MARK: - The distinction that matters

    @Test("identical bytes are unchanged, however recently they were written")
    func identicalBytesAreUnchanged() throws {
        try withTemporaryFile(original) { url in
            // Rewriting the same content bumps the modification date. A monitor that trusted
            // timestamps would raise an alert here — `git checkout` restoring an unmodified file
            // does exactly this, and so does saving twice.
            try original.write(to: url)
            #expect(ExternalChange.inspect(url: url, lastKnown: original) == .unchanged)
        }
    }

    @Test("different bytes are a change, and the new contents come back with it")
    func differentBytesAreAChange() throws {
        try withTemporaryFile(original) { url in
            try rewritten.write(to: url)
            #expect(ExternalChange.inspect(url: url, lastKnown: original) == .changed(rewritten))
        }
    }

    @Test("an ATOMIC replace is detected — the case an fd watch would miss")
    func atomicReplaceIsDetected() throws {
        try withTemporaryFile(original) { url in
            // `Data.write(options: .atomic)` writes a sibling and renames it over the original, so
            // the inode changes. A `DispatchSource` opened on the old descriptor would go quiet
            // here; this is the reason the monitor polls instead.
            try rewritten.write(to: url, options: .atomic)
            #expect(ExternalChange.inspect(url: url, lastKnown: original) == .changed(rewritten))
        }
    }

    @Test("a change of the same LENGTH is still detected")
    func sameLengthChangeIsDetected() throws {
        try withTemporaryFile(original) { url in
            // Size and, on a coarse filesystem, even the timestamp can match. Content is the only
            // reliable comparison, which is why the attribute check is an optimisation and not the
            // decision.
            #expect(original.count == rewritten.count)
            try rewritten.write(to: url)
            #expect(ExternalChange.inspect(url: url, lastKnown: original) == .changed(rewritten))
        }
    }

    // MARK: - Not a change

    @Test("a deleted file is missing, not changed — there is nothing to reload")
    func deletionIsMissing() throws {
        try withTemporaryFile(original) { url in
            try FileManager.default.removeItem(at: url)
            #expect(ExternalChange.inspect(url: url, lastKnown: original) == .missing)
        }
    }

    @Test("a moved file is missing rather than reported as emptied")
    func moveIsMissing() throws {
        try withTemporaryFile(original) { url in
            let moved = url.deletingLastPathComponent().appendingPathComponent("elsewhere.json")
            try FileManager.default.moveItem(at: url, to: moved)
            #expect(ExternalChange.inspect(url: url, lastKnown: original) == .missing)
        }
    }

    @Test("a file we have never read counts as changed, not as unchanged")
    func unknownBaselineIsAChange() throws {
        try withTemporaryFile(original) { url in
            // Erring the other way would mean a document whose baseline was lost silently ignores
            // every future write to its file.
            #expect(ExternalChange.inspect(url: url, lastKnown: nil) == .changed(original))
        }
    }

    @Test("an emptied file is a change, not a missing one")
    func emptiedFileIsAChange() throws {
        try withTemporaryFile(original) { url in
            try Data().write(to: url)
            #expect(ExternalChange.inspect(url: url, lastKnown: original) == .changed(Data()))
        }
    }

    // MARK: - Revision, the cheap pre-check

    @Test("the attribute snapshot reads a real file and nothing else")
    func revisionReads() throws {
        try withTemporaryFile(original) { url in
            let revision = try #require(ExternalChange.Revision.read(url))
            #expect(revision.size == original.count)

            try FileManager.default.removeItem(at: url)
            #expect(ExternalChange.Revision.read(url) == nil)
        }
    }
}

@Suite("External change copy")
struct ExternalChangeCopyTests {

    @Test("the alert says which file, by name")
    func title() {
        #expect(ExternalChangeCopy.title(filename: "sample-payload.json")
                == "\"sample-payload.json\" changed on disk.")
    }

    @Test("the body warns about loss only when there is something to lose")
    func body() {
        let edited = ExternalChangeCopy.body(hasUnsavedChanges: true)
        let clean = ExternalChangeCopy.body(hasUnsavedChanges: false)
        #expect(edited != clean)
        #expect(edited.contains("unsaved changes"))
        // "you can undo it" is a promise the reload has to keep — `JSONDocument.reload` registers
        // undo for the text *and* the encoding together so that it does.
        #expect(edited.contains("you can undo it"))
        #expect(!clean.contains("unsaved"))
    }

    @Test("neither button is phrased as the destructive one")
    func buttons() {
        #expect(ExternalChangeCopy.reload == "Reload")
        #expect(ExternalChangeCopy.keepMyChanges == "Keep My Changes")
        // "Discard changes" was rejected in `Design/error-copy.md`: it names only the destructive
        // reading of a choice that is symmetric.
        #expect(!ExternalChangeCopy.keepMyChanges.lowercased().contains("discard"))
    }
}
