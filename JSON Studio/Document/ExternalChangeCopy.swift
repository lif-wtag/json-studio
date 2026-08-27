import Foundation

/// The alert's exact words, transcribed from `Design/error-copy.md` §File changed on disk.
///
/// Same split as `ParseErrorCopy`: the copy lives in the document, the code holds a transcription,
/// and neither the monitor nor the view composes prose. The copy was written into that document
/// **before** this file existed, which is the order the contract fixes.
enum ExternalChangeCopy {

    static func title(filename: String) -> String {
        "\"\(filename)\" changed on disk."
    }

    /// Two bodies, because the stakes differ. With unsaved edits the developer is being told what
    /// they stand to lose *and* that it is recoverable; without them there is nothing to warn about.
    static func body(hasUnsavedChanges: Bool) -> String {
        hasUnsavedChanges
            ? "Someone else has written to this file since you opened it, and you have unsaved "
              + "changes. Reloading replaces what is in the editor; you can undo it."
            : "Someone else has written to this file since you opened it."
    }

    /// Neither button is the destructive one. Reload leaves the undo stack intact; Keep My Changes
    /// leaves the file on disk untouched until the next save.
    static let reload = "Reload"
    static let keepMyChanges = "Keep My Changes"
}
