import Foundation

extension String {
    /// At most `limit` Unicode scalars, cut between characters. The relay counts code points, not the characters a
    /// reader sees: a decomposed "é" or an emoji with a skin tone is several, so `prefix(n)` on characters can still
    /// exceed the limit and the request is refused.
    func clipped(toScalars limit: Int) -> String {
        guard limit > 0 else { return "" }
        if unicodeScalars.count <= limit { return self }
        var count = 0
        var end = startIndex
        for index in indices {
            let next = unicodeScalars.distance(from: index, to: self.index(after: index))
            if count + next > limit { break }
            count += next
            end = self.index(after: index)
        }
        return String(self[startIndex..<end])
    }
}

extension String {
    /// Cloud vision writes a subscript c, which Unicode has no letter for, as U+A700 (a Chinese tone mark: it renders as a stray glyph
    /// and nothing can search for it). It becomes a plain "c" after its base letter: "T꜀" reads "Tc".
    var withPlainSubscriptC: String {
        replacingOccurrences(of: "\u{A700}", with: "c")
    }
}
