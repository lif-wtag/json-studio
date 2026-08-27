import Combine
import Foundation
import JSONKit
import SwiftUI
import UniformTypeIdentifiers

/// The document (DC-01).
///
/// `ReferenceFileDocument` rather than `FileDocument` because the model is a reference type that
/// outlives any one view: the editor, the inspector and the parse coordinator all observe the same
/// instance. `FileDocument` would hand each of them a copy.
///
/// **macOS owns document management** (ADR-03). Window-per-document, system window tabs, Open
/// Recent, autosave, version browsing, dirty state and close confirmation all come from
/// `DocumentGroup` for free. None of them is reimplemented here, and there is no documents sidebar.
///
/// **`ObservableObject`, not `@Observable`.** `ReferenceFileDocument` refines `ObservableObject`,
/// so the newer macro does not satisfy it — the compiler rejects the conformance outright. The
/// rest of the app can still use `@Observable`; this one type is pinned by the protocol.
final class JSONDocument: ReferenceFileDocument, ObservableObject {

    /// The document's text. The single source of truth; the parse tree is derived from it.
    @Published var text: String

    /// How the file was encoded when it was opened, so saving preserves it (DC-09). A document
    /// that arrives as UTF-16 and leaves as UTF-8 has been silently rewritten.
    @Published private(set) var encoding: DocumentEncoding

    static var readableContentTypes: [UTType] { [.json] }
    /// Writing plain text as well, so Save As can produce a `.txt` copy without a conversion step.
    static var writableContentTypes: [UTType] { [.json, .plainText] }

    init() {
        self.text = ""
        self.encoding = .utf8
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoded = try DocumentEncoding.decode(data)
        self.text = decoded.text
        self.encoding = decoded.encoding
    }

    /// A snapshot for autosave. Taken on the main actor while the document is quiescent, then
    /// written on a background queue — which is why it is a value, not a reference to `self`.
    func snapshot(contentType: UTType) throws -> Snapshot {
        Snapshot(text: text, encoding: encoding)
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot.encoding.encode(snapshot.text))
    }

    struct Snapshot: Sendable {
        let text: String
        let encoding: DocumentEncoding
    }
}

extension JSONDocument {
    /// What the domain makes of the current text. Task 23 replaces this with a debounced,
    /// cancellable, off-main parse (`ParseCoordinator`); parsing on demand here would stall the
    /// main thread on a large document, so this is deliberately temporary.
    ///
    /// It exists at all because it is the only way to *show* that JSONKit is now running inside
    /// the app rather than assert it.
    var summary: String {
        let result = Parser().parse(text)
        guard !result.isEmpty else { return ParseErrorCopy.emptyDocument }

        if let tree = result.tree, result.errors.isEmpty,
           let statistics = try? StatisticsWalker().walk(tree) {
            return """
                \(ParseErrorCopy.statusSummary(errorCount: 0, properties: statistics.properties))
                \(encoding.label)

                objects     \(statistics.objects)
                arrays      \(statistics.arrays)
                properties  \(statistics.properties)
                max depth   \(statistics.maxDepth)
                """
        }

        let first = result.errors.first.map { result.lineIndex.position(at: $0.span.start) }
        var lines = [ParseErrorCopy.statusSummary(
            errorCount: result.errors.count, firstLine: first?.line, firstColumn: first?.column
        ), encoding.label, ""]
        // The cause, not the detection point — the copy comes from ParseErrorCopy verbatim.
        for error in result.errors.prefix(5) {
            let position = result.lineIndex.position(at: error.span.start)
            lines.append("line \(position.line): \(error.copy.title)")
            lines.append("    \(error.copy.body)")
        }
        return lines.joined(separator: "\n")
    }
}
