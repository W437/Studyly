import CoreGraphics
import Foundation
import PDFKit

/// Reads a PDF's pages (PDFKit), off the main thread.
///
/// - A page with a text layer becomes its lines, in the layer's order, without boxes (the layer has no reliable
///   line geometry, and nothing on screen needs it: the page view renders the PDF itself).
/// - An image-only page (a scan with no text layer) is rendered at 2×, kept as the page image and read by
///   `TextRecognizer`, so its lines have boxes like a camera scan and go through the same confidence gate.
/// - A text layer is cleaned of what a browser's "Save as PDF" adds around an article (`PageLayout.cleanedPDFPages`).
/// - A text layer whose typeset formulas vanished is marked `.mathLike` (`PageLayout.pagesMissingFormulas`): by the holes they leave in
///   the prose, and by the outlines the page draws where they were (`PDFInk`).
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
        /// What was taken out of the text layer: a browser's running header and footer, addresses, a reference list.
        var cleaning = PageLayout.PDFCleaning()

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
            // What each text-layer page draws as outlines (by position in `pages`), for the formulas the text layer lost.
            var outlines: [Int: PageLayout.FormulaInk] = [:]
            for index in 0..<total {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { continue }
                let captured = try await read(page, index: index, imageFolder: imageFolder, languages: preferredLanguages)
                if captured.read.engine == .pdfText, let ink = PDFInk.read(page, firstPage: index == 0) { outlines[pages.count] = ink }
                pages.append(captured)
                progress(index + 1, total)
            }
            // A PDF saved from a browser has its header and footer on every page and the article's reference list at the end, and
            // none of it is the material. Taken out of the text layer of the pages that have one, before the lines get their ids.
            let textPages = pages.indices.filter { pages[$0].read.engine == .pdfText }
            let cleaned = PageLayout.cleanedPDFPages(textPages.map { pages[$0].lines.map(\.text) })
            for (kept, index) in zip(cleaned.pages, textPages) {
                pages[index].lines = kept.enumerated().map { TextLine(id: "p\(pages[index].pageIndex).l\($0.offset)", text: $0.element, box: nil) }
            }
            // A text layer whose typeset formulas vanished is marked, so the app can say so and offer a better read.
            let lost = PageLayout.pagesMissingFormulas(textPages.map { pages[$0].lines.map(\.text) }, ink: textPages.map { outlines[$0] })
            for (flagged, index) in zip(lost, textPages) where flagged { pages[index].read.issue = .mathLike }
            return Result(title: title(of: document), pageCount: count, pages: pages, cleaning: cleaned.report)
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

// MARK: - Formulas drawn as outlines

/// The small filled shapes a PDF page draws, read off the page's drawing operators with CoreGraphics (no pixels are made: a page takes
/// about a millisecond, a fraction of what its text layer takes).
///
/// A browser that prints a Wikipedia article draws its formulas, which are SVG pictures, as filled outlines, one per symbol, and the text
/// layer has nothing there. An outline is a filled path of three curves or more (a rectangle, a rule, a bar has none) that is the size of
/// a character (at most 60 points either way); `PageLayout.inkSummaries` takes it from there (what sits together, what repeats on every
/// page, what a formula looks like).
enum PDFInk {
    static let minimumCurves = 3
    static let maximumSize = 60.0
    /// A page that takes more painting operators than this, or draws more forms (a plot's marker drawn again and again is one), is a
    /// map, a plot or a technical drawing, and is left unread; so is one with more outlines than `PageLayout.drawingInkPieces`.
    static let maximumPaints = 60_000
    static let maximumForms = 3_000

    /// The page's outlines, or nil when its drawing couldn't be read or is too big to be a page of text. `firstPage`: the page opens
    /// the document, so what is above its first sentence is a masthead (a site's logo) and is set aside.
    static func read(_ page: PDFPage, firstPage: Bool) -> PageLayout.FormulaInk? {
        guard let reference = page.pageRef, let dictionary = reference.dictionary else { return nil }
        let rotation = ((page.rotation % 360) + 360) % 360
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let swapped = rotation == 90 || rotation == 270
        let size = CGSize(width: swapped ? box.height : box.width, height: swapped ? box.width : box.height)
        let scan = Scan(transform: reference.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: size), rotate: 0,
                                                                 preserveAspectRatio: true),
                        width: Double(size.width), height: Double(size.height))
        var resources: CGPDFDictionaryRef?
        CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
        scan.resources = resources
        let content = CGPDFContentStreamCreateWithPage(reference)
        scan.run(content)
        CGPDFContentStreamRelease(content)
        guard !scan.exhausted else { return nil }
        var ink = PageLayout.FormulaInk(pieces: scan.pieces)
        if firstPage, rotation == 0 { ink.ignoreAbove = firstSentenceTop(of: page) ?? .infinity }
        return ink
    }

    /// The top edge of the page's first sentence, in points from the top: its first line of four words or more (or of twenty letters
    /// or more, for a script with no spaces) that is below the top margin, where a browser prints its date and the page's title. Nil
    /// when the page has none.
    static func firstSentenceTop(of page: PDFPage) -> Double? {
        let box = page.bounds(for: .mediaBox)
        guard let selection = page.selection(for: box) else { return nil }
        var top: Double?
        for line in selection.selectionsByLine() {
            guard let text = line.string,
                  text.split(whereSeparator: \.isWhitespace).count >= 4 || text.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 20
            else { continue }
            let y = Double(box.maxY - line.bounds(for: page).maxY)
            if y >= 0.05 * Double(box.height) { top = min(top ?? y, y) }
        }
        return top
    }

    /// One walk over a content stream (and the forms it draws): the transformation, the path being built, the outlines found.
    private final class Scan {
        var transform: CGAffineTransform
        var saved: [CGAffineTransform] = []
        var resources: CGPDFDictionaryRef?
        var streams: [CGPDFContentStreamRef] = []
        var pieces: [PageLayout.FormulaInk.Piece] = []
        var paints = 0
        var forms = 0
        var exhausted = false
        let width: Double, height: Double
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        var curves = 0
        /// A number that is not one (a damaged stream) was in the path being built.
        var broken = false

        init(transform: CGAffineTransform, width: Double, height: Double) {
            self.transform = transform
            self.width = width
            self.height = height
        }

        func point(_ x: Double, _ y: Double) {
            let p = CGPoint(x: x, y: y).applying(transform)
            guard p.x.isFinite, p.y.isFinite else { broken = true; return }
            minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
            minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
        }

        func clearPath() {
            minX = .infinity; minY = .infinity; maxX = -.infinity; maxY = -.infinity
            curves = 0
            broken = false
        }

        /// A painting operator ends the path: a filled one of a character's size with curves in it is an outline.
        func paint(filled: Bool, _ scanner: CGPDFScannerRef) {
            defer { clearPath() }
            paints += 1
            if paints > PDFInk.maximumPaints || pieces.count > PageLayout.drawingInkPieces {
                exhausted = paints > PDFInk.maximumPaints
                CGPDFScannerStop(scanner)
                return
            }
            guard filled, !broken, curves >= PDFInk.minimumCurves, minX <= maxX else { return }
            let across = maxX - minX, tall = maxY - minY
            guard across <= PDFInk.maximumSize, tall <= PDFInk.maximumSize, max(across, tall) >= 1 else { return }
            // Drawn off the page, it is not on it.
            guard minX > -100, maxX < width + 100, minY > -100, maxY < height + 100 else { return }
            pieces.append(.init(x: minX, y: height - maxY, width: across, height: tall))
        }

        deinit { if let table { CGPDFOperatorTableRelease(table) } }

        /// The operators read, made once for the page and every form on it.
        private lazy var table: CGPDFOperatorTableRef? = Scan.makeTable()

        func run(_ stream: CGPDFContentStreamRef) {
            guard let table else { return }
            streams.append(stream)
            defer { streams.removeLast() }
            let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(self).toOpaque())
            CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
        }

        private static func makeTable() -> CGPDFOperatorTableRef? {
            guard let table = CGPDFOperatorTableCreate() else { return nil }
            let set = { (name: String, callback: @escaping CGPDFOperatorCallback) in CGPDFOperatorTableSetCallback(table, name, callback) }
            set("q") { _, info in let scan = Scan.from(info); scan.saved.append(scan.transform) }
            set("Q") { _, info in let scan = Scan.from(info); if let last = scan.saved.popLast() { scan.transform = last } }
            set("cm") { scanner, info in
                guard let v = Scan.numbers(scanner, 6) else { return }
                let scan = Scan.from(info)
                scan.transform = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(scan.transform)
            }
            set("m") { scanner, info in if let v = Scan.numbers(scanner, 2) { Scan.from(info).point(v[0], v[1]) } }
            set("l") { scanner, info in if let v = Scan.numbers(scanner, 2) { Scan.from(info).point(v[0], v[1]) } }
            set("c") { scanner, info in
                guard let v = Scan.numbers(scanner, 6) else { return }
                let scan = Scan.from(info)
                scan.point(v[0], v[1]); scan.point(v[2], v[3]); scan.point(v[4], v[5]); scan.curves += 1
            }
            set("v") { scanner, info in
                guard let v = Scan.numbers(scanner, 4) else { return }
                let scan = Scan.from(info)
                scan.point(v[0], v[1]); scan.point(v[2], v[3]); scan.curves += 1
            }
            set("y") { scanner, info in
                guard let v = Scan.numbers(scanner, 4) else { return }
                let scan = Scan.from(info)
                scan.point(v[0], v[1]); scan.point(v[2], v[3]); scan.curves += 1
            }
            set("re") { scanner, info in
                guard let v = Scan.numbers(scanner, 4) else { return }
                let scan = Scan.from(info)
                scan.point(v[0], v[1]); scan.point(v[0] + v[2], v[1] + v[3])
            }
            for name in ["f", "F", "f*", "B", "B*", "b", "b*"] {
                set(name) { scanner, info in Scan.from(info).paint(filled: true, scanner) }
            }
            for name in ["S", "s", "n"] {
                set(name) { scanner, info in Scan.from(info).paint(filled: false, scanner) }
            }
            set("Do") { scanner, info in Scan.from(info).draw(scanner) }
            return table
        }

        /// A form XObject is another content stream drawn here, with its own matrix and resources.
        func draw(_ scanner: CGPDFScannerRef) {
            var name: UnsafePointer<Int8>?
            var xObjects: CGPDFDictionaryRef?
            var form: CGPDFStreamRef?
            guard streams.count < 8, !exhausted, CGPDFScannerPopName(scanner, &name), let name, let current = resources,
                  CGPDFDictionaryGetDictionary(current, "XObject", &xObjects), let xObjects,
                  CGPDFDictionaryGetStream(xObjects, name, &form), let form, let dictionary = CGPDFStreamGetDictionary(form) else { return }
            var subtype: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype, String(cString: subtype) == "Form" else { return }
            forms += 1
            if forms > PDFInk.maximumForms {
                exhausted = true
                CGPDFScannerStop(scanner)
                return
            }
            let before = (transform, saved, current)
            var array: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(dictionary, "Matrix", &array), let array {
                var m = [CGPDFReal](repeating: 0, count: 6)
                if (0..<6).allSatisfy({ CGPDFArrayGetNumber(array, $0, &m[$0]) }) {
                    transform = CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5]).concatenating(transform)
                }
            }
            var own: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(dictionary, "Resources", &own), let own { resources = own }
            let content = CGPDFContentStreamCreateWithStream(form, resources ?? current, streams[streams.count - 1])
            run(content)
            CGPDFContentStreamRelease(content)
            (transform, saved, resources) = before
            if exhausted { CGPDFScannerStop(scanner) }
        }

        static func from(_ info: UnsafeMutableRawPointer?) -> Scan { Unmanaged<Scan>.fromOpaque(info!).takeUnretainedValue() }

        /// The last `count` numbers on the operand stack, in the order they were written.
        static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [Double]? {
            var values = [Double](repeating: 0, count: count)
            for i in stride(from: count - 1, through: 0, by: -1) {
                var value: CGPDFReal = 0
                guard CGPDFScannerPopNumber(scanner, &value) else { return nil }
                values[i] = Double(value)
            }
            return values
        }
    }
}
