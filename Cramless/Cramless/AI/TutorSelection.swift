import Foundation

// Which passages of the student's material go to the cloud tutor with a question. Pure: the retriever's ranking in, an
// ordered list of passages out, so the same choice can be tested and run outside the app.
//
// The model never searches, so what it is not handed it cannot answer from. With four passages a question phrased in
// other words than the notes ("what was the holding", when the notes say "the judgment should be reversed") was answered
// "your notes don't cover that" in 20 of 41 cases, though they did. So the model is handed the material itself:
//
//   - a request's size (the tutor's: 4,000 words; the assistant's 6,000) or fewer in all: EVERY passage, in reading order, whatever the question. When that is more passages than
//     a request holds (100: a deck of 150 cards, a 120-page PDF), neighbouring passages are joined until they fit, so that
//     nothing is left out: first those on one page (the shortest pairs first, so the groups stay even), then those of one
//     source across its pages and a deck's consecutive cards, and, with more than 100 sources, any neighbours. A joined
//     passage keeps every member's text whole and names the range ("Deck: X · cards 1-4"); a quote is credited to the one
//     member that holds it (`passage(named:sent:retriever:holding:)`). The same list for every question about the material,
//     byte for byte, so the provider's prompt cache pays for it once.
//   - up to `Budget.wholeWords` and `Budget.wholeBytes` of text, where a budget has such a tier (the tutor's does not; see `tutor`): the same,
//     every passage. Such a request costs about 2 cents the first time for a 15,000-word material (Terra, $1 per million input tokens; 21,000
//     tokens) and a twentieth of that while the provider's cache is warm.
//   - more: a request carries `Budget.fillWords` words (the tutor's: 4,000) of the likeliest passages. First the sources whose titles share a word
//     with what the student asked (Palsgraf, Federalist, Marbury), best match first, whole while they fit (a longer one claims its best
//     `titledWords`); the best 12 passages of the other sources go with them whatever the room. Then, until the words are used up:
//     the neighbours (the passage before and after, on the same page) of the best 6, the best passages of what the chat asked and
//     answered before (a follow-up keeps what the answer before it stood on), and every other passage in `LocalRetriever.recall`
//     order: the ones that use a word of the question or one it begins or is begun by ("Rhein", "Rheinland"), then the ones nearest
//     the best. The room is full: the old rule sent the best 30 and 6 neighbours (400 to 2,500 words) and left the line out of
//     14 of 78 turns that measured it. A named source comes first, so it is the same list at the start of the next question about it.
//
// Always in reading order within a source: its pages in order, a page's passages in the retriever's order. A question with no
// word in common with a large material ("quiz me on this", "what is this about") gets an even spread of it: each source in proportion
// to its length, `Budget.fillWords` words in all, so the model can say what the notes cover.
//
// Whatever the mode, the passages hold no more than `maxCharacters` in all: the relay refuses a request whose passages hold more
// than 200,000 (a 413 for every question). In English 6,000 words are about 40,000, but a language written without spaces
// (Japanese, Chinese, Thai) counts few "words" for a lot of text, so the limit is checked on the text itself, and the passages
// least likely to answer are the ones that go. The same text is why `wholeBytes` stands next to `wholeWords`: the money a request
// costs follows its text, not its words.

enum TutorSelection {

    /// How much of the material one request carries. The route's own limit is `maxPassages` (the relay's schema).
    struct Budget: Equatable, Sendable {
        /// Up to this many words in all, every passage goes, whatever the text.
        var everythingWords = 6_000
        /// Up to this many words in all, and `wholeBytes` of text, every passage goes too. The same as `everythingWords` is no such tier
        /// (the assistant's, which looks passages up for itself); the tutor's is `tutor`.
        var wholeWords = 6_000
        /// The most text, in UTF-8 bytes, of a material that goes whole above `everythingWords`: about 4 bytes to a token in any script,
        /// so 120,000 are 30,000 tokens, 3 cents at the first question. (English comes to 6 bytes a word, German to 8.)
        var wholeBytes = 120_000
        /// The most passages one request can carry.
        var maxPassages = 100
        /// Above `wholeWords`: the words of the likeliest passages a request carries.
        var fillWords = 6_000
        /// A source the question names with more words than `fillWords` claims its best passages up to this many words.
        var titledWords = 3_000
        /// With a title match: the best passages of the other sources that go with it whatever the room.
        var others = 12
        /// The slots of a request kept for the passages that are not a named source's, when the named sources must be joined to fit
        /// (a source of 110 passages is joined to 70). Fixed, so that a named source is the same list for every question about it.
        var reserved = 30
        /// The best few passages whose neighbours go with them.
        var neighbourTops = 6
        /// From each earlier question of the chat (and Cap's last answer): the best passages that stay for a follow-up.
        var carried = 4
        /// A word is no title's own when this share of the sources use it (a function word of the language), see `titleScore`.
        var commonShare = 0.75
        /// The most text, in UTF-16 units (how the relay counts), all the passages of a request may hold.
        var maxCharacters = 180_000
    }

    /// Ask Cap's tutor: the relay takes 100 sources (`TutorRequest.sources`) and 200,000 characters of them. A request carries 4,000 words: all of a
    /// material that size or smaller, else the likeliest 4,000. That makes a question cost about 1 cent (10,500 tokens, the passages' labels and
    /// the instructions included) whatever the provider's cache does, so the free plan's ten answers a day fit the relay's 10-cent day cap. Measured on
    /// the seven students' materials of 5,000 to 16,000 words (`bench select`, 78 questions whose answering line was known): the whole material
    /// (a `wholeWords` of 16,000) held the line in all 78 and cost 2.2 cents a question, and the cap came at the fifth answer, because the cache did not
    /// serve the material to one student (three fresh materials, questions 15, 25 and 40 seconds apart: 1,323 of 21,000 tokens, the instructions, were
    /// read from it); 6,000, 4,500 and 4,000 words each held the line in 77, and the answers read as well (the line shown in 26 of 34 turns on the
    /// three longest readings with 4,500 words, 23 with the whole material); 3,500 held it in 76. A German material costs a quarter more (more
    /// tokens a word). Set the three sizes to 16,000 to have the whole material back, if the cap is raised (`DAILY_COST_CAP_USD` on the relay).
    static let tutor = Budget(everythingWords: 4_000, wholeWords: 4_000, fillWords: 4_000)

    /// Ask Cap's assistant: its request takes 100 too (`AssistantRequest.sources`, `AssistantSession.maxSources`) and the same
    /// 200,000 characters; the lookups the model asks for add passages to the later rounds, so it starts lower.
    static let assistant = Budget(maxCharacters: 150_000)

    /// What a relay from before the limit was raised takes: the tutor's request was 12 passages, the assistant's 24. A request
    /// over it is answered `bad_request`, and is asked again with this many.
    static let legacyTutorLimit = 12
    static let legacyAssistantLimit = 24

    enum Mode: String, Sendable {
        /// Nothing to send.
        case nothing
        /// The whole material (up to `Budget.wholeWords`).
        case everything
        /// Too much to send: the sources named in the question, and the likeliest of the rest.
        case titledSource
        /// Too much to send: the likeliest passages, their neighbours, and what stands nearest.
        case best
        /// Too much to send, and nothing in the question matches the material ("quiz me on this", "what is this about"): an even spread
        /// of it, each source in proportion to its length, starting with its first passage.
        case overview
    }

    struct Selection: Sendable {
        var mode: Mode
        /// In reading order (the sources a title names first). Some may be several neighbouring passages joined (`everything`).
        var passages: [LocalRetriever.Passage]
        /// The same passages, the likeliest answer first: what is kept when a request can carry only some.
        var priority: [LocalRetriever.Passage]

        static let none = Selection(mode: .nothing, passages: [], priority: [])

        var isEmpty: Bool { passages.isEmpty }
        var words: Int { passages.reduce(0) { $0 + TutorSelection.wordCount($1.text) } }

        /// The best `count` passages, still in reading order.
        func reduced(to count: Int) -> Selection {
            guard passages.count > count else { return self }
            let kept = Array(priority.prefix(max(0, count)))
            let keys = Set(kept.map(\.key))
            return Selection(mode: mode, passages: passages.filter { keys.contains($0.key) }, priority: kept)
        }

        /// The text of all the passages, in UTF-16 units: how the relay counts a request's passages against its limit.
        var characters: Int { passages.reduce(0) { $0 + $1.text.utf16.count } }

        /// The likeliest passages that hold no more than `limit` characters in all, still in reading order.
        func reduced(toCharacters limit: Int) -> Selection {
            var total = characters
            guard total > limit else { return self }
            var kept = priority
            while total > limit, let least = kept.popLast() { total -= least.text.utf16.count }
            let keys = Set(kept.map(\.key))
            return Selection(mode: mode, passages: passages.filter { keys.contains($0.key) }, priority: kept)
        }

        /// The passages as a request carries them: "s1", "s2", … in this order, so the list is the same for the same
        /// material, and the ids to map a citation back to its passage. (`TutorSource.fitting` makes them fit the relay.)
        var sources: [TutorSource] {
            passages.enumerated().map { n, p in TutorSource(id: "s\(n + 1)", title: p.title, label: p.label, text: p.text) }
        }

        var sent: [String: LocalRetriever.Passage] {
            Dictionary(uniqueKeysWithValues: passages.enumerated().map { ("s\($0.offset + 1)", $0.element) })
        }
    }

    // MARK: Choosing

    /// The passages for a question. `searchText` is what the retriever searches for (`AIRouter.retrieve`'s `searchText`: the
    /// question, with the chat's last turns when it is a follow-up). `titleText` is what a source's title is compared with:
    /// the student's own words only (`Retrieval.studentText`), because Cap's last answer, which a follow-up's search also
    /// reads, names materials ("I looked through Cardiac cycle (6 pages)…") and would make their titles look asked for.
    /// `earlier` is what the chat asked and answered before (the earlier questions, Cap's last answer): when the material is too long
    /// to go whole, the best passages of each stay in the request, so a follow-up does not lose what the answer before it stood on.
    static func select(retriever: LocalRetriever, searchText: String, titleText: String? = nil, earlier: [String] = [],
                       budget: Budget = tutor) -> Selection {
        choose(retriever: retriever, searchText: searchText, titleText: titleText, earlier: earlier, budget: budget)
            .reduced(toCharacters: budget.maxCharacters)
    }

    private static func choose(retriever: LocalRetriever, searchText: String, titleText: String?, earlier: [String],
                               budget: Budget) -> Selection {
        let all = retriever.passages
        guard !all.isEmpty else { return .none }
        let position = Dictionary(all.enumerated().map { n, p in (p.key, n) }, uniquingKeysWith: { a, _ in a })
        let words = all.map { wordCount($0.text) }
        // Everything: not much, or (the tutor) not much more than a request the provider's cache serves for a twentieth of its price.
        let total = words.reduce(0, +)
        let whole = total <= budget.everythingWords
            || (total <= budget.wholeWords && all.reduce(0) { $0 + $1.text.utf8.count } <= budget.wholeBytes)
        // The order behind `priority`. The whole material is sent whatever it is, so only which passages go first when a request must
        // be cut again (an older relay) matters, and `search` says it; a cut selection also takes what only a related word finds.
        let scored = whole
            ? retriever.search(searchText, limit: all.count).compactMap { position[$0.passage.key] }
            : retriever.recall(searchText)
        let ranking = Ranking(all: all, scored: scored, tops: budget.neighbourTops)

        /// Groups of passage indices (neighbours that were joined, or one) as a selection.
        func make(_ mode: Mode, _ groups: [[Int]], leading: Set<UUID> = []) -> Selection {
            let rank = ranking.rank(of: groups.flatMap { $0 })
            func likeliest(_ group: [Int]) -> Int { group.map { rank[$0] ?? Int.max }.min() ?? Int.max }
            func isLeading(_ group: [Int]) -> Bool { leading.contains(all[group[0]].sourceID) }
            var made: [Int: LocalRetriever.Passage] = [:]
            for group in groups { made[group[0]] = joined(group.map { all[$0] }) }
            let reading = groups.sorted { a, b in isLeading(a) != isLeading(b) ? isLeading(a) : a[0] < b[0] }
            let likeliestFirst = groups.sorted { a, b in likeliest(a) != likeliest(b) ? likeliest(a) < likeliest(b) : a[0] < b[0] }
            return Selection(mode: mode, passages: reading.compactMap { made[$0[0]] }, priority: likeliestFirst.compactMap { made[$0[0]] })
        }

        // What can be joined to what, by index: one page; one source (a deck's cards, a PDF's pages, a lecture's windows); anything.
        let source = all.map(\.sourceID), page = all.map(\.pageIndex), card = all.map(\.isCard)
        func joinable(_ level: Int, _ a: Int, _ b: Int) -> Bool {
            switch level {
            case 0: return !card[a] && !card[b] && source[a] == source[b] && page[a] == page[b]
            case 1: return source[a] == source[b] && card[a] == card[b] && (page[a] == nil) == (page[b] == nil)
            default: return true
            }
        }

        /// Neighbouring passages joined, the shortest pairs first, until there are `limit` groups. Nothing is left out: level 0
        /// joins what is on one page, level 1 what is in one source, level 2 anything (only with more than `limit` sources). Only
        /// passages that stand next to each other in the material are joined (for a selection with gaps, the joined text is all there
        /// is between its first passage and its last).
        func pack(_ indices: [Int], to limit: Int) -> [[Int]] {
            var groups = indices.map { [$0] }
            var size = indices.map { words[$0] }
            for level in 0...2 {
                while groups.count > max(1, limit) {
                    var pick: (k: Int, words: Int)?
                    for k in 0..<(groups.count - 1)
                    where groups[k][groups[k].count - 1] + 1 == groups[k + 1][0] && joinable(level, groups[k][groups[k].count - 1], groups[k + 1][0]) {
                        let sum = size[k] + size[k + 1]
                        if pick == nil || sum < pick!.words { pick = (k, sum) }
                    }
                    guard let pair = pick else { break }
                    groups[pair.k] += groups[pair.k + 1]
                    size[pair.k] = pair.words
                    groups.remove(at: pair.k + 1)
                    size.remove(at: pair.k + 1)
                }
            }
            // Only with a limit of nothing, or a selection with too few neighbours: the likeliest groups stay.
            if groups.count > limit {
                let rank = ranking.rank(of: groups.flatMap { $0 })
                func likeliest(_ group: [Int]) -> Int { group.map { rank[$0] ?? Int.max }.min() ?? Int.max }
                groups = groups.sorted { likeliest($0) < likeliest($1) }.prefix(max(0, limit)).sorted { $0[0] < $1[0] }
            }
            return groups
        }

        // Everything, when it is not much.
        if whole {
            return make(.everything, pack(Array(all.indices), to: budget.maxPassages))
        }

        // Too much to send. The sources the student's words name: the best matches first, as long as they come to `fillWords` in all.
        var sources: [(id: UUID, indices: [Int], words: Int)] = []
        for (i, passage) in all.enumerated() {
            if let k = sources.firstIndex(where: { $0.id == passage.sourceID }) {
                sources[k].indices.append(i)
                sources[k].words += words[i]
            } else {
                sources.append((passage.sourceID, [i], words[i]))
            }
        }
        let asked = titleText ?? searchText
        // A word nearly every source uses is no source's own, in any language ("der", "die", "und").
        let common = sources.count > 1
            ? retriever.commonStems(inAtLeast: Int((Double(sources.count) * budget.commonShare).rounded(.up)))
            : []
        var matches: [(k: Int, score: Int)] = []
        for (k, s) in sources.enumerated() {
            let score = titleScore(asked, title: all[s.indices[0]].title, ignoring: common)
            if score > 0 { matches.append((k, score)) }
        }
        matches.sort { $0.score != $1.score ? $0.score > $1.score : $0.k < $1.k }
        var named: [(id: UUID, indices: [Int], words: Int)] = []
        var room = budget.fillWords
        for m in matches {
            let s = sources[m.k]
            // A source that fits goes whole; a longer one claims its best passages, up to `titledWords`.
            let cost = s.words <= budget.fillWords ? s.words : min(budget.titledWords, s.words)
            // The best match always goes; the others while they still fit. One that doesn't is left to the fill below.
            if named.isEmpty || cost <= room {
                named.append(s)
                room -= min(cost, room)
            }
        }
        named = sources.filter { s in named.contains { $0.id == s.id } }   // in reading order
        let namedIDs = Set(named.map(\.id))

        // What the chat found before: the best passages of each earlier question and of Cap's last answer.
        var carried: [Int] = []
        for text in earlier { carried += retriever.recall(text).prefix(budget.carried) }
        guard !named.isEmpty || !scored.isEmpty || !carried.isEmpty else {
            // Nothing in the question is in the material. A request such as "quiz me on this", "what should I focus on" or "what is this
            // about" has no word in common with it and needs all of it; the model decides what the notes cover. So it gets an even spread:
            // each source's part of the room in proportion to its length, the passages spaced evenly (the same list every time), the first
            // passage of each source always.
            var picked: [Int] = []
            var spare = budget.fillWords
            let allWords = max(1, sources.reduce(0) { $0 + $1.words })
            for s in sources {
                let ratio = min(1, Double(budget.fillWords) / Double(allWords))   // the same share of every source
                var credit = 0.0
                for (n, i) in s.indices.enumerated() {
                    credit += ratio * Double(words[i])
                    if (n == 0 || credit >= Double(words[i]) / 2), words[i] <= spare {
                        picked.append(i)
                        spare -= words[i]
                        credit -= Double(words[i])   // what is owed stays owed: the spacing is even
                    }
                }
            }
            if picked.count > budget.maxPassages {
                let step = Double(picked.count) / Double(budget.maxPassages)
                picked = (0..<budget.maxPassages).map { picked[Int(Double($0) * step)] }
            }
            return picked.isEmpty ? .none : make(.overview, picked.sorted().map { [$0] })
        }

        var chosen = Set<Int>()
        var used = 0
        func take(_ i: Int) { if chosen.insert(i).inserted { used += words[i] } }
        // 1. The named sources that fit, whole; a longer one, its best passages.
        let wholeNamed = named.filter { $0.words <= budget.fillWords }
        for s in wholeNamed { s.indices.forEach(take) }
        for s in named where s.words > budget.fillWords {
            var claimed = 0
            for i in ranking.order(s.indices) where claimed + words[i] <= budget.titledWords { take(i); claimed += words[i] }
        }
        // 2. Whatever the room, the best few of the other sources.
        if !named.isEmpty {
            var count = 0
            for i in scored where !namedIDs.contains(all[i].sourceID) && count < budget.others { take(i); count += 1 }
        }
        // 3. The room that is left, by likelihood: the best few with their neighbours, what the chat found before, then every passage
        //    in `ranking` order (the ones that matched, then the ones nearest to the best).
        var front: [Int] = []
        for t in scored.prefix(budget.neighbourTops) { front.append(t); front += neighbours(of: t, in: all) }
        for i in front + carried + ranking.order(Array(all.indices)) where used < budget.fillWords && !chosen.contains(i) {
            if used + words[i] <= budget.fillWords { take(i) }
        }

        // The named sources that go whole first, each into its share of the slots (the same every time, so that the provider's cache
        // can serve them); then the rest of the selection, joined only as far as the request needs.
        var space = max(0, budget.maxPassages - budget.reserved)
        var shares: [UUID: Int] = [:]
        var waiting = wholeNamed.count
        for s in wholeNamed.sorted(by: { $0.indices.count != $1.indices.count ? $0.indices.count < $1.indices.count : $0.indices[0] < $1.indices[0] }) {
            let share = min(s.indices.count, space / max(1, waiting))
            shares[s.id] = share
            space -= share
            waiting -= 1
        }
        var groups: [[Int]] = []
        for s in wholeNamed { groups += pack(s.indices, to: shares[s.id, default: 0]) }
        let inWhole = Set(wholeNamed.flatMap(\.indices))
        groups += pack(chosen.subtracting(inWhole).sorted(), to: max(0, budget.maxPassages - groups.count))
        return make(named.isEmpty ? .best : .titledSource, groups, leading: namedIDs)
    }

    /// The passages for one search the assistant's model asked for: the best few and the neighbours of the top ones, in
    /// reading order.
    static func lookup(retriever: LocalRetriever, query: String, best: Int = 8, neighbourTops: Int = 3) -> [LocalRetriever.Passage] {
        let all = retriever.passages
        let position = Dictionary(all.enumerated().map { n, p in (p.key, n) }, uniquingKeysWith: { a, _ in a })
        let hits = retriever.search(query, limit: best).compactMap { position[$0.passage.key] }
        var chosen = Set(hits)
        for t in hits.prefix(neighbourTops) { chosen.formUnion(neighbours(of: t, in: all)) }
        return chosen.sorted().map { all[$0] }
    }

    /// The passage before and the passage after, when they are on the same page (or the same stretch of a lecture). Cards
    /// of a deck have no neighbours: the next card is another idea.
    static func neighbours(of index: Int, in all: [LocalRetriever.Passage]) -> [Int] {
        let here = all[index]
        guard !here.isCard else { return [] }
        return [index - 1, index + 1].filter { n in
            all.indices.contains(n) && !all[n].isCard && all[n].sourceID == here.sourceID && all[n].pageIndex == here.pageIndex
        }
    }

    // MARK: Joining

    /// Neighbouring passages as one: the first one's place, every member's text whole, and a label that names the range
    /// ("Deck: X · cards 1-4", "Slides p. 11-14"). `members` keeps what it was made of, so a quote in it is credited to the one
    /// member that holds it.
    static func joined(_ parts: [LocalRetriever.Passage]) -> LocalRetriever.Passage {
        guard var first = parts.first, parts.count > 1 else { return parts[0] }
        let last = parts[parts.count - 1]
        first.members = parts.flatMap { $0.members.isEmpty ? [$0.key] : $0.members }
        first.key = "\(first.key)+\(parts.count - 1)"
        first.text = parts.map(\.text).joined(separator: " ")
        first.anchorIDs = parts.flatMap(\.anchorIDs)
        if first.isCard, parts.allSatisfy({ $0.sourceID == first.sourceID }),
           let from = TutorMaterial.cardNumber(inLabel: first.label), let to = TutorMaterial.cardNumber(inLabel: last.label) {
            first.label = TutorMaterial.deckRangeLabel(title: first.title, from: from, to: to)
        } else {
            first.label = rangeLabel(first.label, last.label)
        }
        return first
    }

    /// "Slides p. 11" and "Slides p. 14" → "Slides p. 11-14"; "Lecture 6 · 07:40" and "Lecture 6 · 09:12" →
    /// "Lecture 6 · 07:40-09:12"; labels that differ more are both given ("Notes p. 3 - Slides p. 1").
    static func rangeLabel(_ first: String, _ last: String) -> String {
        guard first != last else { return first }
        let a = first.split(separator: " ").map(String.init), b = last.split(separator: " ").map(String.init)
        var common = 0
        while common < a.count, common < b.count, a[common] == b[common] { common += 1 }
        if common > 0, a.count == common + 1, b.count == common + 1 {
            return (Array(a[..<common]) + ["\(a[common])-\(b[common])"]).joined(separator: " ")
        }
        return "\(first) - \(last)"
    }

    // MARK: Which passage a quote is from

    /// The passage of the retriever a quote comes from. The passage the model named wins when it holds the quote (a sentence
    /// said twice in a lecture, text two cards share: the one the model was reading is the one it meant). A passage that was sent
    /// joined from several is searched only among those it was made of, and a quote no single one holds (it straddles the seam
    /// between two) is none. When the named passage doesn't hold it, the other passages sent, in the order they were sent, and then
    /// the rest of the material are searched. Nil: the quote is not in the student's notes, so it is not shown as one.
    static func passage(named: LocalRetriever.Passage?, sent: [String: LocalRetriever.Passage], retriever: LocalRetriever,
                        holding holds: (LocalRetriever.Passage) -> Bool) -> LocalRetriever.Passage? {
        let byKey = Dictionary(retriever.passages.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        func exact(_ candidate: LocalRetriever.Passage) -> LocalRetriever.Passage? {
            if candidate.members.isEmpty { return holds(candidate) ? candidate : nil }
            return candidate.members.compactMap { byKey[$0] }.first(where: holds)
        }
        if let named, let hit = exact(named) { return hit }
        let order = sent.sorted { (Int($0.key.dropFirst()) ?? Int.max, $0.key) < (Int($1.key.dropFirst()) ?? Int.max, $1.key) }
        for (_, candidate) in order {
            if let hit = exact(candidate) { return hit }
        }
        return retriever.passages.first(where: holds)
    }

    // MARK: Ranking

    /// The retriever's ranking over every passage, and a way to order any part of them best first: the passages that scored,
    /// in rank order; then the rest, nearest first to the best few that scored (in the same source before another one), then
    /// in reading order.
    private struct Ranking {
        let all: [LocalRetriever.Passage]
        /// Indices of the passages that matched a word of the question, best first.
        let scored: [Int]
        /// How many of the best the rest are measured from.
        let tops: Int

        func order(_ subset: [Int]) -> [Int] {
            let inside = Set(subset)
            let head = scored.filter(inside.contains)
            let headSet = Set(head)
            let nearest = Array(head.prefix(tops))
            let rest = subset.filter { !headSet.contains($0) }.sorted { a, b in
                let da = distance(a, to: nearest), db = distance(b, to: nearest)
                return da != db ? da < db : a < b
            }
            return head + rest
        }

        /// Each index's place in `order` of the same indices.
        func rank(of indices: [Int]) -> [Int: Int] {
            Dictionary(order(Array(Set(indices)).sorted()).enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        }

        private func distance(_ i: Int, to tops: [Int]) -> Int {
            tops.map { t in all[t].sourceID == all[i].sourceID ? abs(t - i) : 1_000_000 + abs(t - i) }.min() ?? Int.max
        }
    }

    // MARK: Titles

    /// How many of the source's title words the question uses: 0 when none ("What was the holding in Palsgraf?" and
    /// "Palsgraf v. Long Island R.R." share one). Words that every material has in its titles ("reading", "notes", "chapter"),
    /// numbers, and the small words of a question don't count.
    /// `common` are the stems that nearly every source of the material uses (`LocalRetriever.commonStems`): in a language the stop words
    /// don't cover they are its function words, which a title does not own.
    static func titleScore(_ question: String, title: String, ignoring common: Set<String> = []) -> Int {
        let asked = distinctive(question, dropping: [])
        guard !asked.isEmpty else { return 0 }
        var shared = Set<String>()
        for word in distinctive(title, dropping: titleStems.union(common)) where asked.contains(where: { Lexicon.match($0, word) != nil }) {
            shared.insert(word.stem)
        }
        // A question about "the picture", "the diagram" or "an arrow" names a kind of source, not a topic: the source whose title says it is a
        // figure ("Printed diagrams: the water cycle") is what it is about, though they share no word with it (a label is one or two words, and a
        // reader may have misspelled it). In a large material (24,850 words: two readings, a novel and a diagrams source of 534) that source was sent
        // for one of three picture questions, by the words "water table", and is now sent for all three; a question that does not point at a picture
        // is not affected.
        if asked.contains(where: { figureQuestionStems.contains($0.stem) }),
           Lexicon.tokens(title).contains(where: { figureTitleStems.contains($0.stem) }) {
            shared.insert("figure")
        }
        return shared.count
    }

    /// Words of a question that point at a picture, and words of a title that say a source is one (stemmed: "diagrams" is "diagram").
    private static let figureTitleStems: Set<String> = Set([
        "picture", "image", "diagram", "figure", "illustration", "drawing", "chart", "graph", "sketch",
    ].map(Lexicon.stem))
    private static let figureQuestionStems: Set<String> = figureTitleStems.union(["arrow", "label", "labelled", "labeled"].map(Lexicon.stem))

    static func titleMatches(_ question: String, title: String, ignoring common: Set<String> = []) -> Bool {
        titleScore(question, title: title, ignoring: common) > 0
    }

    private static func distinctive(_ text: String, dropping extra: Set<String>) -> [Lexicon.Token] {
        Lexicon.tokens(text).filter { token in
            token.isContent && !token.isNumber && token.stem.count >= 3 && !LocalGenerator.genericStems.contains(token.stem)
                && !LocalRetriever.questionWords.contains(token.stem) && !extra.contains(token.stem)
        }
    }

    /// What a title says about the kind of material, not what it is about.
    private static let titleStems: Set<String> = Set([
        "reading", "read", "textbook", "book", "notes", "note", "slides", "slide", "lecture", "chapter", "unit", "week", "class",
        "course", "page", "pages", "handout", "worksheet", "workbook", "reader", "summary", "overview", "intro", "introduction",
        "review", "study", "guide", "deck", "card", "cards", "term", "terms", "key", "quizlet", "anki", "csv", "classmate",
        "imported", "pdf", "scan", "photo", "sample", "text", "part", "section", "topic", "post", "forum",
    ].map(Lexicon.stem))

    // MARK: Words

    static func wordCount(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
}
