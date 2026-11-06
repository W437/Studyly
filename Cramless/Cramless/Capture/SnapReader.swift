import Foundation

/// A problem read off a photo, on this iPhone (`TextRecognizer`, math too in this version): the words the student checks before they go to
/// Cap. The image is staged only for as long as the reading takes and deleted either way, so nothing of the photo outlives this call and
/// nothing of it is ever sent.
enum SnapReader {
    struct Reading: Equatable, Sendable {
        var text: String
        var issue: PageRead.Issue?

        /// There are words to check. No text and an unsure read keep no words at all (the gate in `TextRecognizer`): try again, or type it.
        var hasWords: Bool { !text.isEmpty }
    }

    /// More than any one problem: a whole page read by mistake is the student's to cut, and the chat's message limit is far above it.
    static let maxCharacters = 4_000

    static func read(stagedAt path: String, preferredLanguages: [String] = Locale.preferredLanguages) async -> Reading {
        defer { PageImageStore.discardStaged([path]) }
        guard let page = try? await TextRecognizer.readingEnglishToo(preferredLanguages: preferredLanguages, {
            try await TextRecognizer.read(imageAt: path, pageIndex: 0, preferredLanguages: $0)
        }) else {
            return Reading(text: "", issue: .unreadable)
        }
        return reading(from: page)
    }

    /// The words of a read page, line by line in reading order. A page takes two lines of notation to count as math (`PageLayout`); a problem is
    /// a few lines, and one with a formula in it is where a misread 2x² or O₂ matters, so one line is enough for the note that says to check.
    static func reading(from page: CapturedPage) -> Reading {
        let lines = page.lines.map(\.text)
        let text = String(flowing(lines).prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        let math = page.read.issue == nil && lines.contains(where: PageLayout.isMathLike)
        return Reading(text: text, issue: math ? .mathLike : page.read.issue)
    }

    /// The lines as the problem reads: a line that only ended at the edge of the page runs on into the next, so the words fill the field and the
    /// chat's bubble. A heading, the end of a sentence, a numbered part and a line of notation keep their own line.
    static func flowing(_ lines: [String]) -> String {
        let longest = lines.map(\.count).max() ?? 0
        var out = ""
        for (index, line) in lines.enumerated() {
            guard index > 0 else {
                out = line
                continue
            }
            let previous = lines[index - 1]
            let endsThere = previous.last.map { ".?!:;".contains($0) } ?? true
            let isShort = Double(previous.count) < 0.6 * Double(longest)
            let startsAPart = line.range(of: #"^\(?([0-9]{1,2}|[a-zA-Z])[.)]\s|^[•\-–]\s"#, options: .regularExpression) != nil
            let notation = PageLayout.isMathLike(previous) || PageLayout.isMathLike(line)
            out += endsThere || isShort || startsAPart || notation ? "\n" + line : " " + line
        }
        return out
    }
}
