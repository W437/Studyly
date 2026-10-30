import Foundation

extension Array where Element == BadgeStatus {
    /// The badges Progress shows in its row: the ones earned most recently first, then the ones closest to being earned (a
    /// badge with no progress at all comes last, in the catalog's order).
    func featured(limit: Int) -> [BadgeStatus] {
        let earned = filter(\.isEarned).sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }
        let rest = filter { !$0.isEarned }.enumerated().sorted { a, b in
            if a.element.progress.fraction != b.element.progress.fraction { return a.element.progress.fraction > b.element.progress.fraction }
            return a.offset < b.offset
        }.map(\.element)
        return Array((earned + rest).prefix(limit))
    }
}
