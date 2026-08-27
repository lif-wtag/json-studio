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
    @Published var text: String {
        didSet { scheduleStatusRefresh() }
    }

    /// What the status bar reports (SH-04). Recomputed off the main actor whenever `text` changes.
    @Published private(set) var status: DocumentStatus = .empty

    /// The in-flight status parse, so a newer edit can cancel an older one.
    private var statusTask: Task<Void, Never>?

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
        // `didSet` does not fire during initialisation, so the first status is asked for here.
        scheduleStatusRefresh()
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

    /// Recompute `status` off the main actor, cancelling any parse a newer edit has superseded.
    ///
    /// **This is not `ParseCoordinator`.** Task 23 owns that: a 150 ms debounce, and publication
    /// of the partial tree and the errors so the editor can underline them. This does neither. It
    /// exists because the status bar must report the document rather than a mock, and parsing on
    /// the main thread to do so would blow the 0 ms budget on any document worth opening — a
    /// 528 KB payload takes tens of milliseconds, which is several dropped frames per keystroke.
    func scheduleStatusRefresh() {
        statusTask?.cancel()
        let text = self.text
        let encoding = self.encoding

        statusTask = Task { [weak self] in
            let next = await Task.detached(priority: .userInitiated) {
                DocumentStatus.make(text: text, encoding: encoding)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.status != next else { return }
                self.status = next
            }
        }
    }

    /// Replace the whole text as one undoable operation.
    ///
    /// Registering the undo is what marks the document edited — `ReferenceFileDocument` takes its
    /// dirty state from the undo manager, so a mutation that skipped this would change the
    /// document without the close-confirmation, the edited dot or autosave noticing.
    ///
    /// The undo re-registers itself, which is what makes redo work: undoing a Format puts the
    /// original back *and* registers putting the formatted text back again.
    func replaceText(with newText: String, undoManager: UndoManager?, actionName: String) {
        let previous = text
        guard previous != newText else { return }
        text = newText
        undoManager?.registerUndo(withTarget: self) { document in
            document.replaceText(with: previous, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    /// Run one of the toolbar verbs. The menu bar (Task 17) calls the same method, so the two
    /// cannot diverge; the compare window is Task 27 and is refused rather than faked.
    func perform(
        _ command: DocumentCommand,
        indent: FormatOptions.Indent,
        undoManager: UndoManager?
    ) {
        // Formatting a recovered tree would emit valid JSON that differs from what was written.
        // The toolbar disables these; this guard is the one that actually holds, since a menu
        // item or a shortcut can reach here by another route.
        guard status.isFormattable else { return }

        let options: FormatOptions
        switch command {
        case .format: options = FormatOptions(indent: indent)
        case .minify: options = .minified
        case .compare: return
        }

        let result = Parser().parse(text)
        // Formatted against the source it was parsed from — the formatter re-emits scalars by
        // slicing their spans, which is what keeps `\u00e9` and `9007199254740993` byte-exact.
        guard let formatted = Formatter(options: options).format(result, source: text) else { return }
        replaceText(with: formatted, undoManager: undoManager, actionName: command.menuTitle)
    }
}
