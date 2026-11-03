import Foundation

// What the cloud tutor needs of the retriever that `search` does not give it: not the best four passages but an order over all of them, so
// that a request can be filled with as many as it holds (`TutorSelection`). Pure and deterministic, and in no language in particular: it
// compares the stems the material itself uses, with no list of words.

extension LocalRetriever {

    /// How much a passage that only uses a word related to the question's words counts against one that uses the words themselves: a share
    /// of the rank-fusion weight (`recall`). Measured on the user-test students' questions: from 0.3 the related words find lines that a
    /// question shares no word with ("Rhein" in "Rheinland"), and a bigger share pushes the exact matches out of a small budget.
    static let relatedWeight = 0.3

    /// The rank-fusion constant: a place in a list counts for `1 / (rankConstant + place)`.
    private static let rankConstant = 20.0

    /// The shortest stem that can be taken for the start of another word ("rhein", "licht"). Shorter ones begin too many.
    private static let relatedMinimum = 5

    /// The passages worth handing a model that can't be handed them all, as indices into `passages`, the likeliest first.
    ///   - The passages that use a word of the question, in the order `search` ranks them (BM25, a heading that is the word counting twice).
    ///   - Fused with the passages that use a word *related* to one of the question's words: one that begins it or is begun by it, five
    ///     letters or more ("Rhein" and "Rheinland", "Licht" and "Lichtreaktion", "Wirtschaft" and "Wirtschaftlich"). For German, Spanish and
    ///     French, which the stemmer does not know, that is how an inflected or compounded word is still the same word. A related word that
    ///     many passages use is a function word of the language, not a topic, and does not count.
    /// Only passages that matched something are in the list; the rest are in none (`TutorSelection` orders those by distance from the best).
    func recall(_ query: String) -> [Int] {
        let terms = queryTerms(query)
        guard !terms.isEmpty, !passages.isEmpty else { return [] }
        let exact = ranked(scores(of: terms))
        let related = relatedStems(of: terms)
        guard !related.isEmpty else { return exact }
        let loose = ranked(scores(of: related))
        return Self.fused([(1, exact), (Self.relatedWeight, loose)])
    }

    /// BM25 of every passage for `terms`, the same numbers `search` gives (the terms in the same order, so the sums are equal), and the
    /// heading bonus.
    private func scores(of terms: [String]) -> [Double] {
        let n = Double(passages.count)
        let k1 = 1.2, b = 0.75
        var out = [Double](repeating: 0, count: passages.count)
        for term in terms {
            let df = Double(documentFrequency[term] ?? 0)
            guard df > 0 else { continue }
            let idf = log(1 + (n - df + 0.5) / (df + 0.5))
            for i in passages.indices {
                guard let tf = termFrequencies[i][term], tf > 0 else { continue }
                out[i] += idf * (Double(tf) * (k1 + 1) / (Double(tf) + k1 * (1 - b + b * Double(lengths[i]) / averageLength)))
                if headings[i].contains(term) { out[i] += idf }
            }
        }
        return out
    }

    /// The passages that scored, best first (the same tie-break as `search`: the key).
    private func ranked(_ scores: [Double]) -> [Int] {
        scores.indices.filter { scores[$0] > 0 }.sorted { a, b in
            scores[a] != scores[b] ? scores[a] > scores[b] : passages[a].key < passages[b].key
        }
    }

    /// The stems of the material that begin one of the terms or are begun by one (at least `relatedMinimum` letters each), without the
    /// terms themselves and without the stems so many passages use that they are no topic. Sorted, so the same every time.
    private func relatedStems(of terms: [String]) -> [String] {
        let known = Set(terms)
        let ceiling = max(5.0, 0.08 * Double(passages.count))
        var found = Set<String>()
        for term in terms where term.count >= Self.relatedMinimum && !term.allSatisfy(\.isNumber) {
            for (stem, df) in documentFrequency where Double(df) <= ceiling {
                guard stem.utf8.starts(with: term.utf8) || term.utf8.starts(with: stem.utf8) else { continue }
                if !known.contains(stem), stem.count >= Self.relatedMinimum, !stem.allSatisfy(\.isNumber) { found.insert(stem) }
            }
        }
        return found.sorted()
    }

    /// Reciprocal-rank fusion: each list gives a passage `weight / (rankConstant + place)`; best total first, equal totals in reading order.
    private static func fused(_ lists: [(weight: Double, order: [Int])]) -> [Int] {
        var total: [Int: Double] = [:]
        for list in lists {
            for (place, i) in list.order.enumerated() { total[i, default: 0] += list.weight / (rankConstant + Double(place)) }
        }
        return total.keys.sorted { a, b in total[a]! != total[b]! ? total[a]! > total[b]! : a < b }
    }

    // MARK: Words every source uses

    /// The stems that at least `count` of the material's sources use. In a language the stop-word list does not know, these are its
    /// function words ("der", "die", "und"): no topic of one source. `TutorSelection` leaves them out of the words a title can be named by.
    func commonStems(inAtLeast count: Int) -> Set<String> {
        var bySource: [UUID: Set<String>] = [:]
        for (i, passage) in passages.enumerated() { bySource[passage.sourceID, default: []].formUnion(termFrequencies[i].keys) }
        var seen: [String: Int] = [:]
        for stems in bySource.values { for stem in stems { seen[stem, default: 0] += 1 } }
        return Set(seen.filter { $0.value >= count }.keys)
    }
}
