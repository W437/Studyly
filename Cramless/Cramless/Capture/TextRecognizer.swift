import CoreGraphics
import Foundation
import ImageIO
import Vision

/// On-device text recognition for page images: Vision's Swift API, on this iPhone, off the main thread.
///
/// **Which request.** `RecognizeTextRequest` (accurate, with language correction). It was probed against iOS 26's
/// `RecognizeDocumentsRequest` on the bundled sample page and on rendered hard inputs (macOS 26.6 Vision, Oct
/// 2026). Both returned the same 40 lines with the same text, boxes and order; the
/// documents request adds paragraphs, lists and a table for the phase grid, which `PageLayout` recovers from the
/// boxes anyway. The text request wins on the one thing we can't rebuild, a confidence that separates real text
/// from garbage:
///
/// | input (rendered, then recognised)            | text request          | documents request        |
/// |----------------------------------------------|-----------------------|--------------------------|
/// | sample page, 40 printed lines                | 1.00 on every line    | 0.32–0.73 (mean 0.59)    |
/// | printed control, handwriting-style fonts      | 1.00                  | 0.43–0.64                |
/// | Hebrew (unsupported script)                  | 1 garbage line, 0.50  | 2 garbage lines, 0.13–0.24 |
/// | Devanagari (unsupported script)              | nothing               | 3 garbage lines, 0.10–0.21 |
/// | math (∫, Σ, superscripts)                    | 3 garbled at 1.00, 1 at 0.50 | 0.52–0.87         |
///
/// The documents request scores a correct printed line (0.32) barely above a hallucinated one (0.24), and it
/// hallucinates where the text request returns nothing. Automatic language detection was probed too: it added
/// garbage lines on unsupported scripts (Devanagari, 0.30) and changed nothing for Latin pages, so the
/// recognition languages are set explicitly from the person's preferred languages instead.
///
/// **The gate** (ml-honesty: empty is better than wrong). Lines under `lineFloor` are dropped, so one
/// hallucinated row can't ride in on a good page; a page whose mean confidence (over every line Vision returned)
/// is under `pageFloor` keeps no lines at all and is marked `.unreadable`. Its photo is kept, so a cloud
/// transcription (offered only when photos may be sent) can read it later. Math garbles at full confidence, so
/// confidence can't catch it: a page that is a quarter notation is kept and marked `.mathLike` instead.
/// `OCRTests` keeps the probe alive on the iPhone's own Vision: it reads the sample page, a rendered printed
/// control and rendered Hebrew, logs the confidences and asserts the pair (garbage gated to empty, real text
/// kept), so an OS update that moves these buckets fails a test instead of filling pages with garbage.
enum TextRecognizer {
    /// Between the hallucination buckets (0.30, 0.50) and real text (1.00).
    static let lineFloor = 0.6
    /// A page of real text averages 1.00; one hallucinated line among ten real ones still passes (0.95).
    static let pageFloor = 0.8

    /// Reads a stored page image (relative to `FileStore.root`).
    static func read(imageAt relativePath: String, pageIndex: Int,
                     preferredLanguages: [String] = Locale.preferredLanguages) async throws -> CapturedPage {
        let url = FileStore.url(for: relativePath)
        return try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw CaptureError.unreadableImage }
            var page = try await read(image, pageIndex: pageIndex, preferredLanguages: preferredLanguages)
            page.imageFileName = relativePath
            return page
        }.value
    }

    /// Reads an upright image. Runs wherever it's called from; `read(imageAt:)` hops off the main actor.
    static func read(_ image: CGImage, pageIndex: Int,
                     preferredLanguages: [String] = Locale.preferredLanguages) async throws -> CapturedPage {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = languages(preferred: preferredLanguages, supported: request.supportedRecognitionLanguages)
        let observations = try await request.perform(on: image, orientation: .up)
        let raw = observations.compactMap(rawLine)
        return page(from: raw, pageIndex: pageIndex, width: Double(image.width), height: Double(image.height))
    }

    /// The person's first few languages that Vision reads, in their order, then English.
    static func languages(preferred: [String], supported: [Locale.Language]) -> [Locale.Language] {
        func key(_ language: Locale.Language) -> String {
            let full = Locale.Language(identifier: language.maximalIdentifier)
            return "\(full.languageCode?.identifier ?? "")-\(full.script?.identifier ?? "")"
        }
        var result: [Locale.Language] = []
        var seen = Set<String>()
        for identifier in preferred.prefix(4) + ["en-US"] {
            let wanted = key(Locale.Language(identifier: identifier))
            guard let match = supported.first(where: { key($0) == wanted }), seen.insert(wanted).inserted else { continue }
            result.append(match)
        }
        return result.isEmpty ? [Locale.Language(identifier: "en-US")] : result
    }

    static func rawLine(_ observation: RecognizedTextObservation) -> RawLine? {
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let text = clean(candidate.string)
        guard !text.isEmpty else { return nil }
        let r = observation.boundingBox
        // Vision's origin is bottom-left; pages are stored top-left.
        let box = NormRect(x: unit(r.origin.x), y: unit(1 - r.origin.y - r.height), w: unit(r.width), h: unit(r.height))
        return RawLine(text: text, box: box, confidence: Double(candidate.confidence))
    }

    /// The gate, the reading order, the anchor ids and the page label. Pure, so it is tested without Vision.
    static func page(from raw: [RawLine], pageIndex: Int, width: Double, height: Double) -> CapturedPage {
        let position = "\(pageIndex + 1)"
        guard !raw.isEmpty else {
            return CapturedPage(pageIndex: pageIndex, label: position, lines: [], width: width, height: height,
                                read: PageRead(engine: .vision, confidence: 0, issue: .noText))
        }
        let confidence = (raw.map(\.confidence).reduce(0, +) / Double(raw.count) * 1000).rounded() / 1000
        let kept = raw.filter { $0.confidence >= lineFloor }
        guard confidence >= pageFloor, !kept.isEmpty else {
            return CapturedPage(pageIndex: pageIndex, label: position, lines: [], width: width, height: height,
                                read: PageRead(engine: .vision, confidence: confidence, issue: .unreadable,
                                               droppedLines: raw.count))
        }
        let lines = PageLayout.readingOrder(kept).enumerated().map { index, line in
            TextLine(id: "p\(pageIndex).l\(index)", text: line.text, box: line.box)
        }
        let issue: PageRead.Issue? = PageLayout.isMathLike(page: lines.map(\.text)) ? .mathLike : nil
        return CapturedPage(pageIndex: pageIndex, label: PageLayout.pageNumber(in: kept) ?? position, lines: lines,
                            width: width, height: height,
                            read: PageRead(engine: .vision, confidence: confidence, issue: issue,
                                           droppedLines: raw.count - kept.count))
    }

    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func unit(_ value: CGFloat) -> Double {
        (min(1, max(0, Double(value))) * 1000).rounded() / 1000
    }
}
