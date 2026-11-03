import Accelerate
import Foundation
import NaturalLanguage

// What the offline tutor knows about meaning, from the models the operating system already ships: nothing here reads the network,
// asks a model on a server or sends a word anywhere. Two signals, both optional:
//
//   - `OfflineWordVectors`: the static word vectors of `NLEmbedding.wordEmbedding`. A lookup is a table read, so a sentence's
//     average vector is cheap for every sentence of the library. They place "injection" near "dose" and "quicker" near "faster".
//   - `OfflineEncoder`: the contextual (BERT style) model of `NLContextualEmbedding`, one vector for every word of a sentence. It is
//     slower (about 7 ms a sentence), so the search only asks it about the few sentences the cheap signals picked, and keeps the
//     answers (`TokenMatrix`) for the next question. It is what tells "expecting" from "pregnant" in context.
//
// Both are used only when the system has them already (`hasAvailableAssets`: this never asks for a download), for the language
// of the notes. When one is missing the search says so (`OfflineRanking.usedMeaning`) and carries on with the words alone.
//
// Measured on the 78 questions of the seven-student test (the notes in English and German, questions written to avoid the notes'
// own words): the sentence vectors of `NLEmbedding.sentenceEmbedding` ranked the right sentence first for 0 of 77 questions (it
// ranks questions and headings first, whatever they say), the contextual model with the steps below for 16 of 77 on its own.

// MARK: - Words

/// The static vectors of one language, read through a cache. Not for threads at once: the framework's embedding objects trap when
/// two threads use one together, so every call is under a lock.
final class OfflineWordVectors: @unchecked Sendable {

    private static let lock = NSLock()
    private static var byLanguage: [String: OfflineWordVectors] = [:]
    private static var missing: Set<String> = []

    /// The vectors for a language code ("en", "de"), or nil when the system has none for it.
    static func shared(_ language: String) -> OfflineWordVectors? {
        lock.lock(); defer { lock.unlock() }
        if let known = byLanguage[language] { return known }
        guard !missing.contains(language) else { return nil }
        guard let embedding = NLEmbedding.wordEmbedding(for: NLLanguage(rawValue: language)) else {
            missing.insert(language)
            return nil
        }
        let made = OfflineWordVectors(embedding)
        byLanguage[language] = made
        return made
    }

    private let embedding: NLEmbedding
    let dimension: Int
    private let lock = NSLock()
    private var cache: [String: [Float]?] = [:]

    private init(_ embedding: NLEmbedding) {
        self.embedding = embedding
        self.dimension = embedding.dimension
    }

    /// The word's vector scaled to length 1, or nil when the model does not know the word. German nouns are stored with a capital,
    /// so a lower-case word is tried as written and then capitalised.
    func vector(for word: String) -> [Float]? {
        lock.lock(); defer { lock.unlock() }
        if let known = cache[word] { return known }
        var found = embedding.vector(for: word)
        if found == nil, let first = word.first, first.isLowercase { found = embedding.vector(for: first.uppercased() + word.dropFirst()) }
        var result: [Float]?
        if let found {
            let v = found.map { Float($0) }
            let norm = OfflineMath.norm(v)
            if norm > 0 { result = v.map { $0 / norm } }
        }
        cache[word] = .some(result)
        return result
    }

    /// Whether the model knows the word at all (a name or a term it has never seen is the sign of a question about something else).
    func knows(_ word: String) -> Bool { vector(for: word) != nil }
}

// MARK: - Sentences

/// The pieces of one text as the contextual model reads it: a vector for each (512 numbers), with the whole word each piece belongs
/// to when it was asked for.
final class TokenMatrix: @unchecked Sendable {
    let rows: Int
    let dimension: Int
    /// `rows * dimension` numbers, row after row.
    let data: [Float]
    /// The whole word each row is a piece of ("pregnant" for "preg" and for "nant"), only when `OfflineEncoder.encode(_:language:pieces:)`
    /// was asked for it.
    let pieces: [String]

    init(rows: Int, dimension: Int, data: [Float], pieces: [String]) {
        self.rows = rows
        self.dimension = dimension
        self.data = data
        self.pieces = pieces
    }

    var cost: Int { data.count * MemoryLayout<Float>.stride }
}

/// The contextual model for the languages written in Latin letters (one model serves them all), loaded when it is first needed
/// (about a second, once) and kept. Every call is under a lock, and the vectors of the sentences it has read are kept in a cache
/// the system may empty when memory is short.
final class OfflineEncoder: @unchecked Sendable {

    private static let lock = NSLock()
    private static var byModel: [String: OfflineEncoder] = [:]
    private static var unavailable: Set<String> = []

    /// The encoder for a language code, or nil when the system has no contextual model for it on this device yet. Never requests
    /// the model's files: a device without them answers with the words alone.
    static func shared(_ language: String) -> OfflineEncoder? {
        lock.lock(); defer { lock.unlock() }
        guard !unavailable.contains(language) else { return nil }
        guard let model = NLContextualEmbedding(language: NLLanguage(rawValue: language)), model.hasAvailableAssets else {
            unavailable.insert(language)
            return nil
        }
        if let known = byModel[model.modelIdentifier] { return known }
        let made = OfflineEncoder(model)
        byModel[model.modelIdentifier] = made
        return made
    }

    /// Forget which languages were found missing (a test, or a device that has just downloaded the model).
    static func forgetMissing() {
        lock.lock(); defer { lock.unlock() }
        unavailable.removeAll()
    }

    private let model: NLContextualEmbedding
    private let lock = NSLock()
    private var loaded = false
    private var broken = false

    /// What was read, by text, oldest first, up to `keptLimit` bytes: a plain dictionary and not an `NSCache`, which empties itself when
    /// the system is short of memory, and then every question reads its candidates again (about seven milliseconds each).
    private var kept: [String: TokenMatrix] = [:]
    private var keptOrder: [String] = []
    private var keptBytes = 0
    private static let keptLimit = 32 * 1024 * 1024

    private init(_ model: NLContextualEmbedding) { self.model = model }

    var dimension: Int { model.dimension }

    /// Loads the model now (a second, once) so that the first question does not wait for it. True when it is ready.
    @discardableResult
    func warmUp() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return loadIfNeeded()
    }

    private func loadIfNeeded() -> Bool {
        if loaded { return true }
        if broken { return false }
        do {
            try model.load()
            loaded = true
        } catch {
            broken = true
        }
        return loaded
    }

    /// Forget what was read; for tests.
    func clearCache() {
        lock.lock(); defer { lock.unlock() }
        kept.removeAll()
        keptOrder.removeAll()
        keptBytes = 0
    }

    /// How many texts are kept; for tests.
    var keptCount: Int {
        lock.lock(); defer { lock.unlock() }
        return kept.count
    }

    /// The text as vectors, a row for each piece the model read it in ("preg", "nant"). With `pieces` the whole word each row belongs
    /// to comes back too ("pregnant" twice), and the result is not kept. Nil when the model cannot be loaded or read the text, or the
    /// text has no word.
    ///
    /// Which rows are kept was measured on the user test: the model's first row (a start marker) and its last when that is only
    /// punctuation ("." or "?") are left out, and the empty marker rows inside the text stay. That ranked and gated better than keeping
    /// only the rows that hold a letter: a word of the question that matches nothing in a sentence has the markers to land on instead of
    /// an unrelated word. A last row that is a word (a heading or a list item has no full stop) is kept.
    func encode(_ text: String, language: String, pieces wantPieces: Bool = false) -> TokenMatrix? {
        let key = language + "|" + text
        lock.lock(); defer { lock.unlock() }
        if !wantPieces, let hit = kept[key] { return hit }
        guard loadIfNeeded(), !text.isEmpty,
              let result = try? model.embeddingResult(for: text, language: NLLanguage(rawValue: language)) else { return nil }
        let dim = model.dimension
        var vectors: [[Float]] = []
        var ranges: [Range<String.Index>] = []
        var isWord: [Bool] = []
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, range in
            guard vector.count == dim else { return true }
            vectors.append(vector.map { Float($0) })
            ranges.append(range)
            isWord.append(!range.isEmpty && text[range].contains(where: { $0.isLetter || $0.isNumber }))
            return true
        }
        guard vectors.count > 1 else { return nil }
        let last = vectors.count - 1
        let keep = Array(1..<(isWord[last] ? vectors.count : last))
        guard keep.contains(where: { isWord[$0] }) else { return nil }
        // The word a piece belongs to: the run of word pieces that touch each other.
        var words: [String] = []
        if wantPieces {
            words = [String](repeating: "", count: keep.count)
            var n = 0
            while n < keep.count {
                var m = n
                while m + 1 < keep.count, isWord[keep[m]], isWord[keep[m + 1]], ranges[keep[m]].upperBound == ranges[keep[m + 1]].lowerBound { m += 1 }
                if isWord[keep[n]] {
                    let word = String(text[ranges[keep[n]].lowerBound..<ranges[keep[m]].upperBound])
                    for k in n...m { words[k] = word }
                }
                n = m + 1
            }
        }
        var data: [Float] = []
        data.reserveCapacity(keep.count * dim)
        for i in keep { data.append(contentsOf: vectors[i]) }
        let matrix = TokenMatrix(rows: keep.count, dimension: dim, data: data, pieces: words)
        if !wantPieces {
            kept[key] = matrix
            keptOrder.append(key)
            keptBytes += matrix.cost
            while keptBytes > Self.keptLimit, let oldest = keptOrder.first {
                keptOrder.removeFirst()
                if let gone = kept.removeValue(forKey: oldest) { keptBytes -= gone.cost }
            }
        }
        return matrix
    }
}

// MARK: - Arithmetic

/// The arithmetic on vectors, all of it through Accelerate (which is fast even in a build with no optimisation).
enum OfflineMath {

    /// The mean of the rows of several matrices together.
    static func meanRow(of matrices: [(data: [Float], rows: Int)], dimension: Int) -> [Float] {
        var sum = [Float](repeating: 0, count: dimension)
        var total = 0
        sum.withUnsafeMutableBufferPointer { acc in
            for matrix in matrices where matrix.rows > 0 {
                matrix.data.withUnsafeBufferPointer { base in
                    for r in 0..<matrix.rows {
                        vDSP_vadd(acc.baseAddress!, 1, base.baseAddress! + r * dimension, 1, acc.baseAddress!, 1, vDSP_Length(dimension))
                    }
                }
                total += matrix.rows
            }
        }
        guard total > 0 else { return sum }
        let scale = 1 / Float(total)
        return sum.map { $0 * scale }
    }

    /// Every row with `mean` taken away and scaled to length 1 (a row that is all zeros stays zeros).
    static func centeredUnitRows(_ data: [Float], rows: Int, dimension: Int, mean: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: rows * dimension)
        out.withUnsafeMutableBufferPointer { dst in
            data.withUnsafeBufferPointer { src in
                for r in 0..<rows {
                    let row = dst.baseAddress! + r * dimension
                    vDSP_vsub(mean, 1, src.baseAddress! + r * dimension, 1, row, 1, vDSP_Length(dimension))
                    var squares: Float = 0
                    vDSP_svesq(row, 1, &squares, vDSP_Length(dimension))
                    let norm = squares.squareRoot()
                    if norm > 1e-9 {
                        var scale = 1 / norm
                        vDSP_vsmul(row, 1, &scale, row, 1, vDSP_Length(dimension))
                    }
                }
            }
        }
        return out
    }

    /// For each row of the query, its best cosine with any row of `candidate`, then the mean of those, weighted by `weights`.
    /// All rows are unit length already. This is the "late interaction" score: every word of the question looks for the word of the
    /// sentence that is nearest to it in meaning.
    static func maxSimilarity(query: [Float], queryRows: Int, weights: [Float], candidate: [Float], candidateRows: Int,
                              dimension: Int) -> Double {
        guard queryRows > 0, candidateRows > 0 else { return -1 }
        var transposed = [Float](repeating: 0, count: dimension * candidateRows)
        vDSP_mtrans(candidate, 1, &transposed, 1, vDSP_Length(dimension), vDSP_Length(candidateRows))
        var products = [Float](repeating: 0, count: queryRows * candidateRows)
        vDSP_mmul(query, 1, transposed, 1, &products, 1, vDSP_Length(queryRows), vDSP_Length(candidateRows), vDSP_Length(dimension))
        var weighted: Float = 0
        var total: Float = 0
        for r in 0..<queryRows {
            var best: Float = 0
            products.withUnsafeBufferPointer { vDSP_maxv($0.baseAddress! + r * candidateRows, 1, &best, vDSP_Length(candidateRows)) }
            weighted += best * weights[r]
            total += weights[r]
        }
        return total > 0 ? Double(weighted / total) : -1
    }

    /// The length of a vector.
    static func norm(_ v: [Float]) -> Float {
        var squares: Float = 0
        vDSP_svesq(v, 1, &squares, vDSP_Length(v.count))
        return squares.squareRoot()
    }

    /// The cosine of two vectors that are unit length already.
    static func dot(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return Double(result)
    }

    /// Standard scores: each value's distance from the mean in standard deviations (all zeros when the values do not differ).
    static func zScores(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return values.map { _ in 0 } }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let deviation = variance.squareRoot()
        guard deviation > 1e-9 else { return values.map { _ in 0 } }
        return values.map { ($0 - mean) / deviation }
    }
}
