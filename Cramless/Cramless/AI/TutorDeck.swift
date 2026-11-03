import Foundation

// Imported decks (Quizlet, Anki, CSV) as material the tutor can read, and the list of what the student has added.
// Pure values: `AppModel.tutorMaterial` turns a deck's cards into `TutorCard`s and calls `TutorMaterial.deck`; the
// retriever makes one passage of each card (`LocalRetriever`), so a card can be found, sent to the model and cited.

/// One card of an imported deck, as the tutor reads it.
struct TutorCard: Hashable, Sendable {
    /// Stable for the card (the item's id), so a passage and a citation can find it again.
    var id: String
    var front: String
    var back: String
    /// The card's extra field (Anki's "Back Extra", a CSV notes column).
    var note: String = ""

    /// The passage the card makes: "Front: … Back: …" and, when there is one, "Note: …". A citation's quote is a part of
    /// this text, which is how a quote finds its card again (`TutorMaterial.cardIndex`).
    var text: String {
        var parts = ["Front: \(Self.clean(front))", "Back: \(Self.clean(back))"]
        let extra = Self.clean(note)
        if !extra.isEmpty { parts.append("Note: \(extra)") }
        return parts.joined(separator: " ")
    }

    /// One line of single spaces.
    private static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension TutorMaterial {

    /// An imported deck: no pages, one passage per card. The cards keep the order they are given (the deck's own list in the
    /// Library), and "card 7" in a label is the seventh.
    static func deck(sourceID: UUID, title: String, kind: SourceKind = .quizlet, cards: [TutorCard]) -> TutorMaterial {
        TutorMaterial(sourceID: sourceID, title: title, kind: kind, pages: [], segments: [], cards: cards)
    }

    /// The most of a label's characters (code points) the relay takes.
    static let labelLimit = 120

    /// "Deck: Chapter 3 key terms · card 7". The importer's " (Quizlet)" / " (Anki)" / " (CSV)" after the name is left off, and a
    /// long name is cut, with "…", so that the card's place after it always fits the relay's label limit (a range of cards too:
    /// "· cards 1000-1999").
    static func deckLabel(title: String, number: Int) -> String {
        "\(deckName(title)) · card \(number)"
    }

    /// "Deck: Chapter 3 key terms · cards 1-4": the label of several neighbouring cards sent as one passage.
    static func deckRangeLabel(title: String, from first: Int, to last: Int) -> String {
        first == last ? deckLabel(title: title, number: first) : "\(deckName(title)) · cards \(first)-\(last)"
    }

    /// "Deck: Chapter 3 key terms".
    private static func deckName(_ title: String) -> String {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tag = name.range(of: #"\s*\((quizlet|anki|csv)\)$"#, options: [.regularExpression, .caseInsensitive]) {
            name.removeSubrange(tag)
        }
        name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if name.isEmpty { name = "Imported cards" }
        let room = labelLimit - "Deck: ".unicodeScalars.count - " · cards 99999-99999".unicodeScalars.count
        if name.unicodeScalars.count > room { name = name.clipped(toScalars: room - 1) + "…" }
        return "Deck: \(name)"
    }

    /// The number of the card a label names: 7 for "Deck: X · card 7", the first of the range for "… · cards 5-8"; nil for any
    /// other label.
    static func cardNumber(inLabel label: String) -> Int? {
        guard let match = label.range(of: #" · cards? (\d+)(?:-\d+)?$"#, options: .regularExpression) else { return nil }
        let digits = label[match].drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    /// The index of the card a quote came from: the first card whose passage text holds it.
    static func cardIndex(quoting quote: String, in cards: [TutorCard]) -> Int? {
        cards.firstIndex { HighlightMark.locate(quote, in: $0.text) != nil }
    }

    // MARK: What the student has added

    /// One line for `TutorRequest.materials`: the source's name and how much of it there is, "Cardiac cycle (6 pages)",
    /// "Lecture 7 (38 min)", "Classmate deck (21 cards)". Nil for a source with nothing in it.
    var listing: String? {
        let name = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let label = name.isEmpty ? "Untitled" : name
        let size: String
        if !cards.isEmpty {
            size = cards.count == 1 ? "1 card" : "\(cards.count) cards"
        } else if kind == .lecture || (pages.isEmpty && !segments.isEmpty) {
            guard let end = segments.map(\.end).max() else { return nil }
            size = "\(max(1, Int((end / 60).rounded()))) min"
        } else if !pages.isEmpty {
            size = pages.count == 1 ? "1 page" : "\(pages.count) pages"
        } else {
            return nil
        }
        // A long name gives way, never the size after it. The relay counts code points, not characters.
        let room = max(1, Self.listingLimit - size.unicodeScalars.count - 3)
        return "\(label.clipped(toScalars: room)) (\(size))".clipped(toScalars: Self.listingLimit)
    }

    /// The sources a request may list, and the longest line of one (`TutorRequest.materials`).
    static let listingCount = 20
    static let listingLimit = 120

    /// Everything the student has added to the course, one line each, in the order of the material.
    static func listing(_ material: [TutorMaterial]) -> [String] {
        Array(material.compactMap(\.listing).prefix(listingCount))
    }
}
