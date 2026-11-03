import Foundation

extension SourcePage {
    /// How this page's text was read (`PageRead`); nil while it hasn't been read yet.
    var read: PageRead? {
        get { readData.flatMap { try? JSONDecoder.cramless.decode(PageRead.self, from: $0) } }
        set { readData = newValue.flatMap(encodeBlob) }
    }

    /// The page would read better from a cloud transcription of its photo (handwriting, math, another script).
    var wantsBetterRead: Bool { read?.wantsBetterRead ?? false }

    /// This PDF page's text layer lost its typeset formulas (`PageRead.formulasMayBeMissing`).
    var formulasMayBeMissing: Bool { read?.formulasMayBeMissing ?? false }

    /// Writes a reader's result into this page.
    func apply(_ page: CapturedPage) {
        label = page.label
        text = page.text
        lines = page.lines
        width = page.width
        height = page.height
        if let image = page.imageFileName { imageFileName = image }
        read = page.read
    }
}

extension Source {
    /// Pages whose text would read better from a cloud transcription of the photo.
    var pagesWantingBetterRead: [SourcePage] { sortedPages.filter(\.wantsBetterRead) }

    /// PDF pages whose text layer lost its formulas.
    var pagesWithMissingFormulas: [SourcePage] { sortedPages.filter(\.formulasMayBeMissing) }

    /// The plain note shown on the source and on the review when `pagesWithMissingFormulas` isn't empty.
    static let missingFormulasNote = "Formulas may be missing from this PDF. Read the page with Cloud AI to get them."
}
