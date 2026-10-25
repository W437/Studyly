import CoreGraphics
import Foundation
import PDFKit

/// Reads a PDF's pages (PDFKit), off the main thread.
///
/// - A page with a text layer becomes its lines, in the layer's order, without boxes (the layer has no reliable
///   line geometry, and nothing on screen needs it: the page view renders the PDF itself).
/// - An image-only page (a scan with no text layer) is rendered at 2×, kept as the page image and read by
///   `TextRecognizer`, so its lines have boxes like a camera scan and go through the same confidence gate.
/// - At most `maxPages`; `Result.truncated` says when the rest was left out.
enum PDFReader {
    static let maxPages = 300
    /// A text layer with fewer letters than this is a scan's stray marks, not text: the page is read as an image.
    static let minTextLetters = 20
    static let renderScale: CGFloat = 2

    struct Result: Sendable {
        var title: String?
        /// Pages in the document; more than `pages.count` when it was truncated.
        var pageCount: Int
        var pages: [CapturedPage]

        var truncated: Bool { pageCount > pages.count }
    }

    /// - Parameters:
    ///   - imageFolder: where rendered image-only pages are kept (`sources/<id>`), relative to `FileStore.root`.
    ///   - progress: pages done and the total, from a background thread.
    static func read(_ url: URL, imageFolder: String, maxPages: Int = maxPages,
                     preferredLanguages: [String] = Locale.preferredLanguages,
                     progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else { throw CaptureError.pdfUnreadable }
            if document.isLocked, !document.unlock(withPassword: "") { throw CaptureError.pdfLocked }
            let count = document.pageCount
            guard count > 0 else { throw CaptureError.pdfEmpty }
            let total = min(count, max(1, maxPages))
            var pages: [CapturedPage] = []
            pages.reserveCapacity(total)
            for index in 0..<total {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { continue }
                pages.append(try await read(page, index: index, imageFolder: imageFolder, languages: preferredLanguages))
                progress(index + 1, total)
            }
            return Result(title: title(of: document), pageCount: count, pages: pages)
        }.value
    }

    static func read(_ page: PDFPage, index: Int, imageFolder: String, languages: [String]) async throws -> CapturedPage {
        let position = "\(index + 1)"
        let pdfLabel = page.label.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let text = page.string ?? ""
        let letters = text.unicodeScalars.lazy.filter { CharacterSet.letters.contains($0) }.count
        let box = page.bounds(for: .mediaBox)
        if letters >= minTextLetters {
            let texts = TextPaginator.lines(from: text, splitSentences: false)
            return CapturedPage(pageIndex: index, label: printedNumber(in: texts) ?? pdfLabel ?? position,
                                lines: texts.enumerated().map { TextLine(id: "p\(index).l\($0.offset)", text: $0.element, box: nil) },
                                width: box.width, height: box.height, read: .pdfText)
        }
        guard let image = render(page, scale: renderScale) else { throw CaptureError.pdfUnreadable }
        let stored = try PageImagePipeline.normalize(cgImage: image)
        let path = try FileStore.write(stored.jpeg, folder: imageFolder, name: PageImageStore.pageFileName(index))
        var captured = try await TextRecognizer.read(image, pageIndex: index, preferredLanguages: languages)
        captured.imageFileName = path
        captured.width = Double(stored.width)
        captured.height = Double(stored.height)
        if captured.label == position, let pdfLabel { captured.label = pdfLabel }
        return captured
    }

    /// The page drawn upright on white at `scale` (honouring `/Rotate`), at most 4000 px on the long edge.
    static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        guard let pageRef = page.pageRef else { return nil }
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let rotation = ((page.rotation % 360) + 360) % 360
        let swapped = rotation == 90 || rotation == 270
        let displayWidth = swapped ? box.height : box.width
        let displayHeight = swapped ? box.width : box.height
        let effective = min(scale, 4000 / max(displayWidth, displayHeight))
        let width = Int((displayWidth * effective).rounded()), height = Int((displayHeight * effective).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: effective, y: effective)
        // `/Rotate` turns the page clockwise for display; CG's y axis points up. The last transform applies first.
        switch rotation {
        case 90:
            context.translateBy(x: 0, y: box.width)
            context.rotate(by: -.pi / 2)
        case 180:
            context.translateBy(x: box.width, y: box.height)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: box.height, y: 0)
            context.rotate(by: .pi / 2)
        default:
            break
        }
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(pageRef)
        return context.makeImage()
    }

    /// The document's own title, unless it's a placeholder an exporter left ("Untitled", "Microsoft Word - x.docx").
    static func title(of document: PDFDocument) -> String? {
        guard var title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        for prefix in ["Microsoft Word - ", "Microsoft PowerPoint - ", "Microsoft Excel - "] where title.hasPrefix(prefix) {
            title = String(title.dropFirst(prefix.count))
        }
        for suffix in [".docx", ".doc", ".pptx", ".ppt", ".key", ".pages", ".pdf"] where title.lowercased().hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
        }
        let lowered = title.lowercased()
        guard !title.isEmpty, !["untitled", "untitled document", "document", "slide 1"].contains(lowered) else { return nil }
        return title
    }

    /// A page number printed as the first or last line of a text layer (a header or a footer).
    static func printedNumber(in lines: [String]) -> String? {
        for line in [lines.first, lines.last].compactMap({ $0 }) {
            if let number = PageLayout.pageNumberText(line) { return number }
        }
        return nil
    }
}
