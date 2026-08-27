import Foundation

/// How a document's bytes are encoded, detected on open and preserved on save (DC-09).
///
/// **The BOM is the reason this type exists rather than a bare `String.Encoding`.** JSONKit's
/// parser rejects `U+FEFF` with `invalidLiteral` — proven by test against JSONTestSuite — because
/// a byte-order mark is not JSON whitespace under RFC 8259. Foundation's decoders strip it while
/// decoding, which is exactly why a corpus case *looked* as though the parser accepted one.
///
/// So the mark has to be remembered rather than discarded: a file that arrived with a BOM is
/// written back with a BOM, and one that did not, is not. Losing it would silently rewrite a file
/// some other tool depends on; keeping it in the text would make every such document unparseable.
enum DocumentEncoding: Sendable, Equatable {
    case utf8
    case utf8WithBOM
    case utf16LittleEndian
    case utf16BigEndian

    /// What the status bar shows (SH-04).
    var label: String {
        switch self {
        case .utf8: "UTF-8"
        case .utf8WithBOM: "UTF-8 with BOM"
        case .utf16LittleEndian: "UTF-16 LE"
        case .utf16BigEndian: "UTF-16 BE"
        }
    }

    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LEBOM: [UInt8] = [0xFF, 0xFE]
    private static let utf16BEBOM: [UInt8] = [0xFE, 0xFF]

    /// Detects the encoding from the leading bytes and decodes.
    ///
    /// Detection is by BOM, then by validity. There is no charset declaration in a JSON file to
    /// consult — RFC 8259 §8.1 says JSON is UTF-8 — so a file that is not valid UTF-8 is tried as
    /// UTF-16 before being refused, which covers the Windows-authored payloads that turn up in
    /// practice.
    static func decode(_ data: Data) throws -> (text: String, encoding: DocumentEncoding) {
        let bytes = [UInt8](data.prefix(3))

        if bytes.starts(with: utf8BOM) {
            let body = data.dropFirst(utf8BOM.count)
            guard let text = String(data: body, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return (text, .utf8WithBOM)
        }
        if bytes.starts(with: utf16LEBOM) {
            guard let text = String(data: data, encoding: .utf16LittleEndian) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return (stripLeadingBOM(text), .utf16LittleEndian)
        }
        if bytes.starts(with: utf16BEBOM) {
            guard let text = String(data: data, encoding: .utf16BigEndian) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return (stripLeadingBOM(text), .utf16BigEndian)
        }
        // **UTF-16 is tested before UTF-8, and the order is load-bearing.** NUL is a perfectly
        // legal UTF-8 byte, so ASCII-in-UTF-16LE — `7B 00 22 00 …` — decodes "successfully" as
        // UTF-8 into a string full of NULs. Trying UTF-8 first would therefore claim every
        // BOM-less UTF-16 file and hand the parser nonsense.
        //
        // The reverse mistake cannot happen: valid UTF-8 JSON contains no NUL bytes at all, so it
        // never satisfies the evidence test below.
        if looksLikeUTF16(data, littleEndian: true),
           let text = String(data: data, encoding: .utf16LittleEndian) {
            return (stripLeadingBOM(text), .utf16LittleEndian)
        }
        if looksLikeUTF16(data, littleEndian: false),
           let text = String(data: data, encoding: .utf16BigEndian) {
            return (stripLeadingBOM(text), .utf16BigEndian)
        }
        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    /// Encodes, restoring the byte-order mark the file arrived with.
    func encode(_ text: String) -> Data {
        switch self {
        case .utf8:
            Data(text.utf8)
        case .utf8WithBOM:
            Data(DocumentEncoding.utf8BOM) + Data(text.utf8)
        case .utf16LittleEndian:
            Data(DocumentEncoding.utf16LEBOM) + Data(text.utf16.flatMap {
                [UInt8($0 & 0xFF), UInt8($0 >> 8)]
            })
        case .utf16BigEndian:
            Data(DocumentEncoding.utf16BEBOM) + Data(text.utf16.flatMap {
                [UInt8($0 >> 8), UInt8($0 & 0xFF)]
            })
        }
    }

    /// Positive evidence of BOM-less UTF-16: an even byte count, and a NUL in the high half of
    /// most code units.
    ///
    /// JSON is overwhelmingly ASCII — braces, quotes, digits, key names — so in UTF-16 roughly
    /// every second byte is `0x00`, and which half holds the NUL tells the byte order apart. Real
    /// UTF-8 text and binary data both fail this comfortably. The sample is capped because the
    /// evidence is in the first few hundred bytes; reading further tells us nothing new.
    private static func looksLikeUTF16(_ data: Data, littleEndian: Bool) -> Bool {
        guard data.count >= 2, data.count.isMultiple(of: 2) else { return false }

        let sample = [UInt8](data.prefix(512))
        let pairs = sample.count / 2
        guard pairs > 0 else { return false }

        var nulls = 0
        for index in stride(from: 0, to: pairs * 2, by: 2) {
            // ASCII in UTF-16LE is `xx 00`; in UTF-16BE it is `00 xx`.
            if sample[littleEndian ? index + 1 : index] == 0 { nulls += 1 }
        }
        // Half would be pure ASCII. A quarter leaves room for non-Latin content while still
        // ruling out UTF-8 and binary, neither of which produces NULs at every other position.
        return nulls * 4 >= pairs
    }

    /// Some decoders leave the mark in the string. It must not reach the parser.
    private static func stripLeadingBOM(_ text: String) -> String {
        text.unicodeScalars.first?.value == 0xFEFF ? String(text.dropFirst()) : text
    }
}
