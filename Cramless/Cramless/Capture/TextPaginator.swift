import Foundation
import NaturalLanguage

/// Typed or pasted text as pages: about 600 words a page, broken at a paragraph when one ends late enough, a line
/// per sentence and per line break, no boxes. Line ids are `p<page>.l<n>` like everywhere else.
enum TextPaginator {
    static let wordsPerPage = 600
    /// A "line" longer than this (a run-on with no punctuation, a PDF that extracts a paragraph as one line) is cut
    /// at word boundaries, so an anchor never points at half a page.
    static let maxLineWords = 60

    static func pages(from text: String, wordsPerPage: Int = wordsPerPage) -> [CapturedPage] {
        var pages: [[String]] = []
        var current: [String] = []
        var words = 0
        var lastBreak: Int?
        for paragraph in paragraphs(of: text) {
            for line in paragraph {
                let count = wordCount(line)
                if words + count > wordsPerPage, !current.isEmpty {
                    if let cut = lastBreak, wordCount(current[..<cut]) * 3 >= wordsPerPage * 2 {
                        pages.append(Array(current[..<cut]))
                        current = Array(current[cut...])
                    } else {
                        pages.append(current)
                        current = []
                    }
                    words = wordCount(current[...])
                    lastBreak = nil
                }
                current.append(line)
                words += count
            }
            lastBreak = current.count
        }
        if !current.isEmpty { pages.append(current) }
        return pages.enumerated().map { index, texts in
            CapturedPage(pageIndex: index, label: "\(index + 1)",
                         lines: texts.enumerated().map { TextLine(id: "p\(index).l\($0.offset)", text: $0.element, box: nil) },
                         read: .typed)
        }
    }

    /// Paragraphs (split at blank lines), each as its lines: one per sentence and per line break.
    static func paragraphs(of text: String) -> [[String]] {
        normalized(text)
            .components(separatedBy: "\n\n")
            .map { lines(from: $0, splitSentences: true) }
            .filter { !$0.isEmpty }
    }

    /// One line per line break; with `splitSentences`, also one per sentence. Long runs are cut at
    /// `maxLineWords`. Whitespace is collapsed and empty lines are dropped.
    static func lines(from text: String, splitSentences: Bool) -> [String] {
        normalized(text).components(separatedBy: "\n").flatMap { raw -> [String] in
            let line = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !line.isEmpty else { return [] }
            let pieces = splitSentences || wordCount(line) > maxLineWords ? sentences(in: line) : [line]
            return pieces.flatMap(chunked)
        }
    }

    static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        return result.isEmpty ? [text] : result
    }

    static func wordCount<S: Sequence>(_ lines: S) -> Int where S.Element == String {
        lines.reduce(0) { $0 + wordCount($1) }
    }

    static func wordCount(_ line: String) -> Int {
        line.split(whereSeparator: \.isWhitespace).count
    }

    private static func chunked(_ line: String) -> [String] {
        let words = line.split(whereSeparator: \.isWhitespace)
        guard words.count > maxLineWords else { return [line] }
        return stride(from: 0, to: words.count, by: maxLineWords).map {
            words[$0..<min($0 + maxLineWords, words.count)].joined(separator: " ")
        }
    }

    /// Unix line breaks, blank lines with only spaces made truly blank, no BOM, trimmed.
    static func normalized(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        s = s.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
        s = s.replacingOccurrences(of: #"\n[ \t]+\n"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
