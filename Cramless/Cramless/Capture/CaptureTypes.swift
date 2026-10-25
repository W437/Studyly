import Foundation

// The values the capture code produces before anything is stored: a read page, how far to trust its text, the
// progress of a long read, and the errors a person can see. Nothing here calls AI: capture delivers sources with
// pages and lines, and generation (the AI lane) starts from there.

/// How a page's text was read, and how far to trust it. Stored on `SourcePage` (`SourcePage.read`).
struct PageRead: Codable, Hashable, Sendable {
    enum Engine: String, Codable, Sendable {
        /// On-device text recognition (Vision) on the page image.
        case vision
        /// The PDF's own text layer.
        case pdfText
        /// Typed or pasted text.
        case typed
        /// The bundled sample page (its recognition ships with the app).
        case sample
        /// A cloud transcription of the page photo. Its lines have no boxes.
        case cloud
    }

    enum Issue: String, Codable, Sendable {
        /// No text was found: a photo, a diagram, a blank page.
        case noText
        /// Recognition wasn't sure (handwriting, a script it doesn't read). The lines were left out rather than
        /// kept as plausible-looking garbage; the photo is kept, so a better read can start from it.
        case unreadable
        /// Much of the page is math or chemistry notation, which on-device recognition garbles while still
        /// reporting full confidence. The lines are kept; a better read is offered.
        case mathLike
    }

    var engine: Engine
    /// 0…1. For Vision, the mean confidence of every line it returned, before the floor; 1 for text that was
    /// never recognised (typed, a PDF's text layer, the sample).
    var confidence: Double
    var issue: Issue?
    /// Lines Vision returned below the confidence floor, left out.
    var droppedLines: Int = 0

    init(engine: Engine, confidence: Double = 1, issue: Issue? = nil, droppedLines: Int = 0) {
        self.engine = engine
        self.confidence = confidence
        self.issue = issue
        self.droppedLines = droppedLines
    }

    /// The page would read better from a cloud transcription of its photo. The UI offers it only when the person
    /// allows sending photos (`settings.sendPhotos`), and says that this path leaves the iPhone.
    var wantsBetterRead: Bool { engine == .vision && issue != nil }

    static let typed = PageRead(engine: .typed)
    static let pdfText = PageRead(engine: .pdfText)
    static let sample = PageRead(engine: .sample)
}

/// One page as a reader produced it, before it becomes a `SourcePage`.
struct CapturedPage: Hashable, Sendable {
    /// 0-based position in the source.
    var pageIndex: Int
    /// The printed page number if one was found ("87"), else the position ("1").
    var label: String
    /// In reading order, ids `p<pageIndex>.l<n>`.
    var lines: [TextLine]
    /// Pixel size of the page image; 0 for pages with no image.
    var width: Double = 0
    var height: Double = 0
    var read: PageRead
    /// The page image under `FileStore.root`, when there is one.
    var imageFileName: String?

    var text: String { lines.map(\.text).joined(separator: "\n") }
}

/// Where a long read is, for the processing screen ("Reading page 3 of 12").
struct CaptureProgress: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case preparing
        /// Text recognition or a PDF's text layer, one page at a time.
        case reading
        case saving
    }

    var stage: Stage
    var completed: Int
    var total: Int

    var fraction: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }

    static let preparing = CaptureProgress(stage: .preparing, completed: 0, total: 0)
}

/// What can go wrong in capture and imports, in words the person can act on.
enum CaptureError: LocalizedError, Equatable, Sendable {
    case unreadableImage
    case noPages
    case emptyText
    case pdfLocked
    case pdfUnreadable
    case pdfEmpty
    case damagedArchive
    case unsupportedArchiveEntry(String)
    case ankiNewestFormat
    case ankiNoCollection
    case ankiUnreadable(String)
    case quizletLink
    case noCards(String)
    case unsupportedFile(String)
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "Couldn't open that image. Try another photo."
        case .noPages: "There are no pages to read."
        case .emptyText: "There's no text to add yet."
        case .pdfLocked:
            "This PDF is password-protected. Remove the password in Files or Preview, then import it again."
        case .pdfUnreadable: "Couldn't open this PDF. It may be damaged."
        case .pdfEmpty: "This PDF has no pages."
        case .damagedArchive: "This deck file looks damaged. Export it from Anki again and try once more."
        case .unsupportedArchiveEntry: "This deck file is packed in a way Capling can't open. Export it from Anki again."
        case .ankiNewestFormat:
            "This deck uses Anki's newest format. In Anki, export again with 'Support older Anki versions' turned on."
        case .ankiNoCollection: "This file doesn't contain an Anki deck."
        case .ankiUnreadable: "Couldn't read the cards in this deck. Export it from Anki again and try once more."
        case .quizletLink:
            "Quizlet links can't be read directly. In Quizlet, open the set, choose Export, copy the text and paste it here."
        case .noCards(let why): why
        case .unsupportedFile(let ext):
            "Capling can't open \(ext.isEmpty ? "this file" : ".\(ext) files"). Try a PDF, an Anki deck (.apkg), or a CSV or text file."
        case .fileTooLarge: "This file is too large to import."
        }
    }
}

/// Runs `body` with access to a URL that may be security-scoped (a file picked in Files). Files handed over by
/// "Open in Capling" are copies in the app's inbox and need no scope; starting one that isn't scoped is harmless.
func withFileAccess<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try body()
}
