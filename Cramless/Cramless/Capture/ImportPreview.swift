import Foundation

/// The deck formats Capling imports.
enum DeckFormat: String, Codable, Sendable, CaseIterable {
    case anki, quizlet, csv

    var origin: ItemOrigin {
        switch self {
        case .anki: .anki
        case .quizlet: .quizlet
        case .csv: .csv
        }
    }

    var sourceKind: SourceKind {
        switch self {
        case .anki: .anki
        case .quizlet: .quizlet
        case .csv: .csv
        }
    }

    var displayName: String {
        switch self {
        case .anki: "Anki"
        case .quizlet: "Quizlet"
        case .csv: "CSV"
        }
    }
}

/// One card read from a deck, before it becomes a `StudyItem`.
struct ImportedCard: Hashable, Sendable {
    /// `.flashcard`, or `.cloze` for Anki cloze notes.
    var kind: ItemKind = .flashcard
    var front: String
    var back: String
    /// Extra fields (Anki's "Back Extra", a CSV "Notes" column): shown after answering.
    var explanation: String = ""
    var cloze: ClozeSpec?
    /// The deck or column it belongs to, which becomes a topic in the course.
    var topic: String?
    /// Scheduling carried over (Anki); nil for a new card.
    var memory: MemoryState?
    /// Suspended in Anki: imported as suspended, so the person's own choice to pause it survives the move.
    var suspended = false
}

/// What an import will add, shown before anything is committed: the count, a few sample rows, how the file was
/// read and what was left out.
struct ImportPreview: Hashable, Sendable {
    var format: DeckFormat
    /// A suggested title for the source ("Unit 3 terms"), from the deck or the file name.
    var title: String
    var cards: [ImportedCard]
    /// How the file was read, for a caption: "Tab between term and definition, one card per line".
    var summary: String
    /// What was skipped or changed, one sentence each: "12 images and sounds weren't imported".
    var warnings: [String] = []

    var count: Int { cards.count }
    var sampleRows: [ImportedCard] { Array(cards.prefix(5)) }
    /// Cards that arrive with their scheduling (Anki review history).
    var scheduledCount: Int { cards.filter { $0.memory != nil }.count }
    var suspendedCount: Int { cards.filter(\.suspended).count }
}

/// What a committed import added.
struct ImportOutcome: Sendable {
    var sourceID: UUID
    var added: Int
    /// Cards already in the course with the same front and back, skipped.
    var duplicates: Int
}

/// Reads a deck file into a preview, choosing the importer from the file: `.apkg`/`.colpkg` (Anki), `.csv`/`.tsv`
/// (CSV), `.txt` (a Quizlet export, or CSV when it has a header row).
enum DeckImporter {
    static let maxTextBytes = 20 << 20

    static func preview(fileAt url: URL) throws -> ImportPreview {
        try withFileAccess(url) {
            let ext = url.pathExtension.lowercased()
            let title = url.deletingPathExtension().lastPathComponent
            switch ext {
            case "apkg", "colpkg":
                return try AnkiImporter.preview(packageAt: url)
            case "csv", "tsv", "txt", "text", "":
                let text = try readText(url)
                if ext == "txt" || ext == "text" || ext == "" {
                    return try preview(text: text, format: nil, title: title)
                }
                return try CSVImporter.preview(text, title: title)
            default:
                throw CaptureError.unsupportedFile(ext)
            }
        }
    }

    /// Pasted or typed text. With no format given, a header row with known column names reads as CSV; anything
    /// else as a Quizlet export.
    static func preview(text: String, format: DeckFormat?, title: String) throws -> ImportPreview {
        switch format {
        case .csv: return try CSVImporter.preview(text, title: title)
        case .quizlet: return try QuizletImporter.preview(text, title: title)
        case .anki: throw CaptureError.unsupportedFile("txt")
        case nil:
            if CSVImporter.hasKnownHeader(text) { return try CSVImporter.preview(text, title: title) }
            return try QuizletImporter.preview(text, title: title)
        }
    }

    /// Text in UTF-8, UTF-16 (with a byte-order mark: Excel's "Unicode text") or Windows-1252.
    static func readText(_ url: URL) throws -> String {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) } catch { throw CaptureError.unsupportedFile(url.pathExtension) }
        guard data.count <= maxTextBytes else { throw CaptureError.fileTooLarge }
        return decodeText(data)
    }

    static func decodeText(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return text }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1252) { return text }
        return String(decoding: data, as: UTF8.self)
    }
}
