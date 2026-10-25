import Foundation
import SwiftData

/// The sample textbook page that ships with the app (Biology, p. 87, mitosis): for onboarding's "Use a sample
/// page" and the empty Library. Its text recognition (lines and boxes) and its curated, checked questions are
/// bundled, so the sample works the same offline, on any iPhone, with or without cloud AI. The questions are the
/// fixtures the relay's MOCK mode serves, so the sample, the demos and the tests tell one story.
enum SamplePage {
    static let title = "Biology textbook"
    static let pageLabel = "87"
    static let imageResource = "sample-mitosis-p87"

    static var imageURL: URL? { Bundle.main.url(forResource: imageResource, withExtension: "jpg") }

    struct OCRFile: Decodable {
        var width: Double
        var height: Double
        var lines: [TextLine]
    }

    /// The page's recognised lines, with boxes in page units.
    static func ocr() -> OCRFile? {
        guard let url = Bundle.main.url(forResource: imageResource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.cramless.decode(OCRFile.self, from: data)
    }

    static func generated() -> GenerateResponse? { try? RelayFixtures.load(GenerateResponse.self, "generate") }
    static func checked() -> CheckResponse? { try? RelayFixtures.load(CheckResponse.self, "check") }

    /// Creates the sample source (its page image copied into the file store) in `course`. Inserts, doesn't save.
    @discardableResult
    static func makeSource(in course: Course, context: ModelContext, now: Date) -> Source {
        let source = Source(course: course, kind: .sample, title: title, status: .read, now: now)
        context.insert(source)
        course.sources.append(source)
        let file = ocr()
        var imageName: String?
        if let url = imageURL {
            imageName = try? FileStore.copy(from: url, folder: "sources/\(source.id.uuidString)", name: "page-0.jpg")
        }
        let lines = file?.lines ?? []
        let page = SourcePage(source: source, pageIndex: 0, label: pageLabel,
                              text: lines.map(\.text).joined(separator: "\n"), lines: lines,
                              imageFileName: imageName, width: file?.width ?? 1200, height: file?.height ?? 1800)
        context.insert(page)
        source.pages.append(page)
        return source
    }

    /// The curated items with the check applied: fixed answers swapped in, unsupported items dropped.
    static func checkedItems() -> (topics: [GeneratedTopic], items: [GeneratedItem], dropped: [CheckVerdict]) {
        guard let gen = generated() else { return ([], [], []) }
        let verdicts = Dictionary(uniqueKeysWithValues: (checked()?.verdicts ?? []).map { ($0.id, $0) })
        var kept: [GeneratedItem] = []
        var dropped: [CheckVerdict] = []
        for var item in gen.items {
            guard let v = verdicts[item.id] else { kept.append(item); continue }
            switch v.verdict {
            case .supported: kept.append(item)
            case .fixed:
                if let a = v.fixedAnswer { item.answer = a }
                if let c = v.fixedChoices { item.choices = c }
                kept.append(item)
            case .unsupported: dropped.append(v)
            }
        }
        return (gen.topics, kept, dropped)
    }
}
