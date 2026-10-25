import Foundation

/// Pure text work on Anki fields and templates: HTML to plain text (media dropped and counted), cloze deletions to
/// our `ClozeSpec` syntax, and which fields a card template shows on the front and the back.
enum AnkiText {
    // MARK: HTML

    struct Plain: Equatable {
        var text: String
        /// Images, sounds and videos referenced in the field (not imported).
        var media: Int
    }

    private static let mediaPatterns: [NSRegularExpression] = [
        #"<img\b[^>]*>"#, #"\[sound:[^\]]*\]"#, #"<audio\b[^>]*>.*?</audio>"#, #"<video\b[^>]*>.*?</video>"#,
        #"<(?:audio|video|source)\b[^>]*/?>"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive, .dotMatchesLineSeparators]) }
    private static let blockBreak = try? NSRegularExpression(
        pattern: #"<br\s*/?>|</(?:div|p|li|tr|h[1-6]|ul|ol|table|blockquote)>|<(?:hr)\b[^>]*>"#, options: [.caseInsensitive])
    private static let listItem = try? NSRegularExpression(pattern: #"<li\b[^>]*>"#, options: [.caseInsensitive])
    private static let tag = try? NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let styleOrScript = try? NSRegularExpression(
        pattern: #"<(style|script)\b[^>]*>.*?</\1>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])

    /// Strips tags, turns block ends into line breaks and list items into bullets, decodes entities, drops media
    /// references (counting them) and collapses whitespace.
    static func plain(_ html: String) -> Plain {
        var s = html
        var media = 0
        for pattern in mediaPatterns {
            media += pattern.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
            s = replace(pattern, in: s, with: " ")
        }
        s = replace(styleOrScript, in: s, with: "")
        s = replace(listItem, in: s, with: "\n• ")
        s = replace(blockBreak, in: s, with: "\n")
        s = replace(tag, in: s, with: "")
        s = decodeEntities(s)
        let lines = s.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
        return Plain(text: lines.joined(separator: "\n"), media: media)
    }

    private static func replace(_ regex: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let regex else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
        "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "middot": "·", "bull": "•",
        "times": "×", "divide": "÷", "deg": "°", "plusmn": "±", "micro": "µ", "copy": "©", "reg": "®",
        "rarr": "→", "larr": "←", "harr": "↔", "le": "≤", "ge": "≥", "ne": "≠", "alpha": "α", "beta": "β",
        "gamma": "γ", "delta": "δ", "pi": "π", "sigma": "σ", "mu": "μ", "lambda": "λ", "theta": "θ", "omega": "ω",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(12).firstIndex(of: ";") {
                let name = String(after[..<semi])
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    decoded = namedEntities[name.lowercased()]
                }
                if let decoded {
                    out += decoded
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        return out + rest
    }

    // MARK: Cloze

    struct Cloze: Equatable {
        /// The sentence in `ClozeSpec` syntax: this card's deletions as `{{answer}}`, the others shown as text.
        var text: String
        var answers: [String]
        var hints: [String]
    }

    /// The cloze numbers a field uses (`{{c1::…}}`, `{{c2::…}}`), in ascending order.
    static func clozeNumbers(in text: String) -> [Int] {
        var numbers = Set<Int>()
        var index = text.startIndex
        while let open = text.range(of: "{{c", range: index..<text.endIndex) {
            var cursor = open.upperBound
            var digits = ""
            while cursor < text.endIndex, text[cursor].isNumber { digits.append(text[cursor]); cursor = text.index(after: cursor) }
            if let n = Int(digits), text[cursor...].hasPrefix("::") { numbers.insert(n) }
            index = open.upperBound
        }
        return numbers.sorted()
    }

    /// Converts Anki cloze deletions for card `number`: `{{c1::anaphase::phase}}` becomes `{{anaphase}}` (hint
    /// "phase") when `number` is 1, and plain "anaphase" otherwise. Nested deletions are resolved inside out. Nil
    /// when the text has no deletion with that number.
    static func cloze(_ text: String, number: Int) -> Cloze? {
        var answers: [String] = []
        var hints: [String] = []
        let rendered = render(Substring(text), number: number, answers: &answers, hints: &hints, depth: 0)
        guard !answers.isEmpty else { return nil }
        return Cloze(text: rendered, answers: answers, hints: hints)
    }

    private static func render(_ text: Substring, number: Int, answers: inout [String], hints: inout [String], depth: Int) -> String {
        var out = ""
        var rest = text
        while let open = rest.range(of: "{{c") {
            var cursor = open.upperBound
            var digits = ""
            while cursor < rest.endIndex, rest[cursor].isNumber { digits.append(rest[cursor]); cursor = rest.index(after: cursor) }
            guard let n = Int(digits), rest[cursor...].hasPrefix("::"), depth < 8,
                  let close = matchingClose(in: rest, from: rest.index(cursor, offsetBy: 2)) else {
                out += rest[..<open.upperBound]
                rest = rest[open.upperBound...]
                continue
            }
            out += rest[..<open.lowerBound]
            let body = rest[rest.index(cursor, offsetBy: 2)..<close]
            // The hint is after the last "::" outside any nested deletion.
            var inner = body
            var hint: Substring?
            if let split = lastTopLevelSeparator(in: body) {
                inner = body[..<split.lowerBound]
                hint = body[split.upperBound...]
            }
            var nestedAnswers: [String] = []
            var nestedHints: [String] = []
            let answer = render(inner, number: number, answers: &nestedAnswers, hints: &nestedHints, depth: depth + 1)
            if n == number {
                // A deletion that is this card's: the blank covers the whole answer, nested markers included.
                let plainAnswer = answer.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "")
                answers.append(plainAnswer.trimmingCharacters(in: .whitespaces))
                if let hint, !hint.trimmingCharacters(in: .whitespaces).isEmpty {
                    hints.append(hint.trimmingCharacters(in: .whitespaces))
                }
                out += "{{\(plainAnswer.trimmingCharacters(in: .whitespaces))}}"
            } else {
                answers += nestedAnswers
                hints += nestedHints
                out += answer
            }
            rest = rest[rest.index(close, offsetBy: 2)...]
        }
        return out + rest
    }

    /// The "}}" that closes a deletion whose body starts at `start`, skipping nested "{{…}}".
    private static func matchingClose(in text: Substring, from start: Substring.Index) -> Substring.Index? {
        var depth = 0
        var index = start
        while index < text.endIndex {
            if text[index...].hasPrefix("{{") {
                depth += 1
                index = text.index(index, offsetBy: 2)
            } else if text[index...].hasPrefix("}}") {
                if depth == 0 { return index }
                depth -= 1
                index = text.index(index, offsetBy: 2)
            } else {
                index = text.index(after: index)
            }
        }
        return nil
    }

    private static func lastTopLevelSeparator(in body: Substring) -> Range<Substring.Index>? {
        var depth = 0
        var found: Range<Substring.Index>?
        var index = body.startIndex
        while index < body.endIndex {
            if body[index...].hasPrefix("{{") {
                depth += 1
                index = body.index(index, offsetBy: 2)
            } else if body[index...].hasPrefix("}}") {
                depth -= 1
                index = body.index(index, offsetBy: 2)
            } else if depth == 0, body[index...].hasPrefix("::") {
                found = index..<body.index(index, offsetBy: 2)
                index = body.index(index, offsetBy: 2)
            } else {
                index = body.index(after: index)
            }
        }
        return found
    }

    // MARK: Templates

    /// A field a template shows, and how.
    struct FieldUse: Equatable {
        var name: String
        /// The filters before the name (`text`, `type`, `hint`, `cloze`, `furigana`, `tts en_US`…).
        var filters: [String]

        var isTypeIn: Bool { filters.contains("type") }
        var isHint: Bool { filters.contains("hint") }
        var isCloze: Bool { filters.contains("cloze") }
    }

    private static let specialFields: Set<String> = ["FrontSide", "Tags", "Type", "Deck", "Subdeck", "Card", "CardFlag", "CardID"]

    /// The fields a template shows, in order, once each. Section markers (`{{#Field}}`, `{{^Field}}`,
    /// `{{/Field}}`) and special fields (`{{FrontSide}}`, `{{Tags}}`…) are not fields shown.
    static func fieldUses(in template: String) -> [FieldUse] {
        var uses: [FieldUse] = []
        var seen = Set<String>()
        var rest = Substring(template)
        while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            let inner = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            rest = rest[close.upperBound...]
            guard let first = inner.first, !"#^/!=".contains(first) else { continue }
            let parts = inner.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = parts.last, !name.isEmpty, !specialFields.contains(name) else { continue }
            let filters = parts.dropLast().map { $0.split(separator: " ").first.map(String.init) ?? $0 }
            guard seen.insert(name).inserted else { continue }
            uses.append(FieldUse(name: name, filters: filters))
        }
        return uses
    }

    /// Which fields make a card's front, its back and its extra explanation, from the card template.
    /// The front is what `qfmt` shows (a type-in box or a hint isn't front content); the back is the first field
    /// `afmt` adds; anything else `afmt` adds is extra.
    static func sides(question: String, answer: String) -> (front: [String], back: [String], extra: [String]) {
        let q = fieldUses(in: question)
        let front = q.filter { !$0.isTypeIn && !$0.isHint }.map(\.name)
        let shown = Set(front)
        let added = fieldUses(in: answer).map(\.name).filter { !shown.contains($0) }
        let typed = q.filter(\.isTypeIn).map(\.name)
        // A type-in field is the answer even when the back template only shows it through {{type:…}}.
        var back = Array(added.prefix(1))
        if back.isEmpty, let first = typed.first { back = [first] }
        let extra = added.filter { !back.contains($0) } + q.filter(\.isHint).map(\.name).filter { !back.contains($0) }
        return (front, back, extra)
    }
}
