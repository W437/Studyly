import Foundation
import SQLite3

/// Reads an Anki package (`.apkg`, or a whole-collection `.colpkg`): a ZIP holding a SQLite collection.
///
/// **Which collection file.** `collection.anki21` (Anki 2.1 with the v2/v3 scheduler) is preferred over
/// `collection.anki2` (older exports; also the stub Anki writes beside newer formats, holding one note that says
/// to update). `collection.anki21b` is Anki's newest format (zstd-compressed, schema 18), which the Compression
/// framework can't open: a package that has it and no `collection.anki21` fails with a message saying how to
/// export again. All of these readable files use schema 11: note types live as JSON in `col.models`.
///
/// **Cards.** One item per card: a basic note's card shows the fields its template's front shows, and its back
/// the first field the answer template adds (other added fields become the explanation). A cloze note's card `n`
/// becomes a fill-in with deletion `c(n+1)` as the blank (`{{c1::anaphase::phase}}` → `{{anaphase}}`, hint
/// "phase"); the other deletions show as text. HTML is stripped; images and sounds are dropped and counted.
///
/// **Scheduling** (Anki → `MemoryState`, FSRS):
/// - `type` 0/1/2/3 → new / learning / review / relearning. New cards arrive as new (no memory).
/// - Stability: Anki's own FSRS state when the card has one (`cards.data` `{"s":…, "d":…}`); otherwise the
///   interval (`ivl`, days) for review and relearning cards, since an SM-2 interval was set to be recalled at
///   about the 90% FSRS defines stability by; 1 day for learning cards.
/// - Difficulty (1…10, higher is harder) from the ease factor (permille): 2500 (Anki's start) → 5, 1300 (the
///   floor, "ease hell") → 10, 3700 and up → 1, linear between.
/// - Due: review and day-learning cards count days from the collection's creation (`col.crt`, which sits at the
///   day's rollover hour), so due = crt + due × 1 day; intraday learning cards hold a Unix timestamp. A card in
///   a filtered deck uses its original due (`odue`).
/// - Last review: the card's latest `revlog` entry, else due − interval for review cards.
/// - `reps` and `lapses` carry over; suspended cards (`queue` −1) stay suspended.
enum AnkiImporter {
    static func preview(packageAt url: URL) throws -> ImportPreview {
        let archive = try ZipArchive(url: url)
        let names = Set(archive.names)
        let collectionName: String
        if names.contains("collection.anki21") {
            collectionName = "collection.anki21"
        } else if names.contains("collection.anki21b") {
            throw CaptureError.ankiNewestFormat
        } else if names.contains("collection.anki2") {
            collectionName = "collection.anki2"
        } else {
            throw CaptureError.ankiNoCollection
        }
        guard let entry = archive.entry(named: collectionName) else { throw CaptureError.ankiNoCollection }
        let temp = FileManager.default.temporaryDirectory.appending(path: "anki-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temp) }
        try archive.extract(entry, to: temp)
        return try preview(collectionAt: temp, fallbackTitle: url.deletingPathExtension().lastPathComponent)
    }

    /// Reads an extracted collection (SQLite, schema 11; schema 18's deck and field tables are read when the
    /// JSON is empty, with cloze notes found by their deletions).
    static func preview(collectionAt url: URL, fallbackTitle: String) throws -> ImportPreview {
        let db = try SQLiteReader(url: url)
        let col = try db.rows("SELECT crt, models, decks FROM col LIMIT 1").first
        guard let col else { throw CaptureError.ankiUnreadable("no col row") }
        let crt = Date(timeIntervalSince1970: TimeInterval(col.int(0)))
        var models = parseModels(col.text(1))
        var decks = parseDecks(col.text(2))
        let tables = Set((try? db.rows("SELECT name FROM sqlite_master WHERE type='table'"))?.map { $0.text(0) } ?? [])
        if decks.isEmpty, tables.contains("decks"), let rows = try? db.rows("SELECT id, name FROM decks") {
            for row in rows { decks[row.int(0)] = row.text(1) }
        }
        if models.isEmpty, tables.contains("fields"), let rows = try? db.rows("SELECT ntid, ord, name FROM fields ORDER BY ntid, ord") {
            for row in rows {
                models[row.int(0), default: Model(isCloze: false, fields: [], templates: [], name: "")].fields.append(row.text(2))
            }
        }

        var notes: [Int64: (model: Int64, fields: [String])] = [:]
        for row in try db.rows("SELECT id, mid, flds FROM notes") {
            notes[row.int(0)] = (row.int(1), row.text(2).components(separatedBy: "\u{1f}"))
        }
        // The stub newer Anki versions write for older readers: one note saying to update.
        if notes.count == 1, let first = notes.values.first?.fields.first?.lowercased(),
           first.contains("newer version of anki") || first.contains("update to the latest anki") {
            throw CaptureError.ankiNewestFormat
        }
        var lastReviews: [Int64: Date] = [:]
        if tables.contains("revlog") {
            for row in try db.rows("SELECT cid, MAX(id) FROM revlog GROUP BY cid") {
                lastReviews[row.int(0)] = Date(timeIntervalSince1970: TimeInterval(row.int(1)) / 1000)
            }
        }

        var cards: [ImportedCard] = []
        var media = 0
        var skippedEmpty = 0
        var skippedOcclusion = 0
        var deckNames = Set<String>()
        let rows = try db.rows("""
            SELECT id, nid, did, ord, type, queue, due, ivl, factor, reps, lapses, odue, odid, data
            FROM cards ORDER BY nid, ord
            """)
        for row in rows {
            guard let note = notes[row.int(1)] else { continue }
            let model = models[note.model]
            let deckID = row.int(12) != 0 ? row.int(12) : row.int(2)
            let deckName = decks[deckID] ?? decks[row.int(2)]
            let ord = Int(row.int(3))
            let built = card(note: note.fields, model: model, ord: ord)
            media += built.media
            guard var card = built.card else {
                if built.occlusion { skippedOcclusion += 1 } else { skippedEmpty += 1 }
                continue
            }
            card.topic = deckName.map(leafName)
            if let deckName { deckNames.insert(deckName) }
            let schedule = Schedule(type: Int(row.int(4)), queue: Int(row.int(5)), due: row.int(6), ivl: Int(row.int(7)),
                                    factor: Int(row.int(8)), reps: Int(row.int(9)), lapses: Int(row.int(10)),
                                    odue: row.int(11), odid: row.int(12), data: row.text(13))
            card.memory = memory(schedule, collectionCreated: crt, lastReview: lastReviews[row.int(0)])
            card.suspended = schedule.queue == -1
            cards.append(card)
        }

        var warnings: [String] = []
        if media > 0 {
            warnings.append("\(media) \(media == 1 ? "image or sound wasn't" : "images and sounds weren't") imported. Capling keeps each card's text.")
        }
        if skippedEmpty > 0 {
            warnings.append("\(skippedEmpty) \(skippedEmpty == 1 ? "card had" : "cards had") nothing but media on the front and \(skippedEmpty == 1 ? "was" : "were") left out.")
        }
        if skippedOcclusion > 0 {
            warnings.append("\(skippedOcclusion) image occlusion \(skippedOcclusion == 1 ? "card was" : "cards were") left out.")
        }
        guard !cards.isEmpty else {
            throw CaptureError.noCards(skippedEmpty + skippedOcclusion > 0
                ? "The cards in this deck are images or sounds only, which Capling can't import yet."
                : "This deck has no cards.")
        }
        let title = deckTitle(Array(deckNames)) ?? fallbackTitle
        let scheduled = cards.filter { $0.memory != nil }.count
        let suspended = cards.filter(\.suspended).count
        var summary = "\(cards.count) \(cards.count == 1 ? "card" : "cards")"
        if scheduled > 0 { summary += ", \(scheduled) with their review history" }
        if suspended > 0 { summary += ", \(suspended) suspended" }
        if deckNames.count > 1 { summary += ", from \(deckNames.count) decks" }
        return ImportPreview(format: .anki, title: title, cards: cards, summary: summary, warnings: warnings)
    }

    /// One deck: its own name. Several: the deepest parent they share ("Biology::Unit 3::Mitosis" and
    /// "Biology::Unit 3::Meiosis" → "Unit 3"). Anki's "Default" deck is no title.
    static func deckTitle(_ names: [String]) -> String? {
        let paths = names.map { $0.replacingOccurrences(of: "\u{1f}", with: "::").components(separatedBy: "::")
            .map { $0.trimmingCharacters(in: .whitespaces) } }
        guard var common = paths.first else { return nil }
        for path in paths.dropFirst() {
            common = Array(zip(common, path).prefix { $0 == $1 }.map(\.0))
        }
        guard let title = common.last, !title.isEmpty, title != "Default" else { return nil }
        return title
    }

    // MARK: Notes to cards

    struct Model: Equatable {
        struct Template: Equatable {
            var ord: Int
            var question: String
            var answer: String
        }

        var isCloze: Bool
        var fields: [String]
        var templates: [Template]
        var name: String
    }

    /// One card's front, back and extra, or nil (with why) when it has nothing to study.
    static func card(note fields: [String], model: Model?, ord: Int) -> (card: ImportedCard?, media: Int, occlusion: Bool) {
        let names = model?.fields ?? []
        func value(_ name: String) -> String {
            guard let index = names.firstIndex(of: name), index < fields.count else { return "" }
            return fields[index]
        }
        var media = 0
        func plain(_ html: String) -> String {
            let p = AnkiText.plain(html)
            media += p.media
            return p.text
        }

        let template = model?.templates.first { $0.ord == ord } ?? model?.templates.first
        let isCloze = model?.isCloze ?? false
        let rawCloze = fields.first { !AnkiText.clozeNumbers(in: $0).isEmpty }
        if isCloze || (model == nil && rawCloze != nil) {
            // The cloze field is the one the template shows through the cloze filter (usually "Text").
            let uses = template.map { AnkiText.fieldUses(in: $0.question) } ?? []
            let clozeName = uses.first(where: \.isCloze)?.name
            let source = clozeName.map(value) ?? rawCloze ?? fields.first ?? ""
            if source.contains("image-occlusion:") { return (nil, 0, true) }
            guard let cloze = AnkiText.cloze(plain(source), number: ord + 1) else { return (nil, media, false) }
            let extraNames = template.map { AnkiText.fieldUses(in: $0.answer).map(\.name) } ?? Array(names.dropFirst())
            let extra = extraNames.filter { $0 != clozeName }.map { plain(value($0)) }.filter { !$0.isEmpty }
            let blanks = cloze.answers.count
            var prompt = blanks == 1 ? "Fill in the blank." : "Fill in the blanks."
            if !cloze.hints.isEmpty { prompt += " Hint: \(cloze.hints.joined(separator: ", "))." }
            let card = ImportedCard(kind: .cloze, front: prompt, back: cloze.answers.joined(separator: ", "),
                                    explanation: extra.joined(separator: "\n"), cloze: ClozeSpec(text: cloze.text))
            return (card, media, false)
        }

        var frontNames: [String] = [], backNames: [String] = [], extraNames: [String] = []
        if let template {
            (frontNames, backNames, extraNames) = AnkiText.sides(question: template.question, answer: template.answer)
        }
        if frontNames.isEmpty || backNames.isEmpty || model == nil {
            // No usable template: the first field is the front, the second the back, the rest extra.
            let all = names.isEmpty ? fields.indices.map { "#\($0)" } : names
            frontNames = Array(all.prefix(1))
            backNames = Array(all.dropFirst().prefix(1))
            extraNames = Array(all.dropFirst(2))
        }
        func text(_ name: String) -> String {
            if name.hasPrefix("#"), let index = Int(name.dropFirst()), index < fields.count { return plain(fields[index]) }
            return plain(value(name))
        }
        let front = frontNames.map(text).filter { !$0.isEmpty }.joined(separator: "\n")
        let back = backNames.map(text).filter { !$0.isEmpty }.joined(separator: "\n")
        let extra = extraNames.map(text).filter { !$0.isEmpty }.joined(separator: "\n")
        guard !front.isEmpty, !back.isEmpty else { return (nil, media, false) }
        return (ImportedCard(front: front, back: back, explanation: extra), media, false)
    }

    // MARK: Scheduling

    struct Schedule: Equatable {
        var type: Int
        var queue: Int
        var due: Int64
        var ivl: Int
        var factor: Int
        var reps: Int
        var lapses: Int
        var odue: Int64 = 0
        var odid: Int64 = 0
        var data: String = ""
    }

    /// Anki's scheduling as FSRS memory (the mapping is in the type's comment). Nil for a new card.
    static func memory(_ s: Schedule, collectionCreated crt: Date, lastReview: Date?) -> MemoryState? {
        let state: CardState
        switch s.type {
        case 1: state = .learning
        case 2: state = .review
        case 3: state = .relearning
        default: return nil
        }
        let fsrs = fsrsState(s.data)
        var stability = fsrs?.stability ?? (state == .learning ? 1 : Double(max(s.ivl, 1)))
        stability = max(0.1, stability)
        let difficulty = fsrs?.difficulty ?? difficulty(fromEase: s.factor)
        let rawDue = s.odid != 0 && s.odue != 0 ? s.odue : s.due
        let due: Date?
        if rawDue > 1_000_000_000 {
            due = Date(timeIntervalSince1970: TimeInterval(rawDue))
        } else if state != .learning || s.queue == 3 {
            due = crt.addingTimeInterval(TimeInterval(rawDue) * 86_400)
        } else {
            due = nil
        }
        var last = lastReview
        if last == nil, state == .review, let due { last = due.addingTimeInterval(-TimeInterval(max(s.ivl, 1)) * 86_400) }
        return MemoryState(state: state, stability: stability, difficulty: difficulty, due: due, lastReview: last,
                           reps: max(0, s.reps), lapses: max(0, s.lapses), step: 0)
    }

    /// 2500 → 5, 1300 → 10, 3700+ → 1. A missing factor (0, learning cards in some versions) → 5.
    static func difficulty(fromEase factor: Int) -> Double {
        guard factor > 0 else { return 5 }
        let ease = Double(factor) / 1000
        return min(10, max(1, 5 + (2.5 - ease) * 5 / 1.2))
    }

    /// Anki's own FSRS memory, when the collection uses FSRS: `cards.data` = `{"s": 12.3, "d": 5.6, …}`.
    static func fsrsState(_ data: String) -> (stability: Double, difficulty: Double)? {
        guard data.contains("\"s\""), let json = data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let s = (object["s"] as? NSNumber)?.doubleValue, let d = (object["d"] as? NSNumber)?.doubleValue,
              s > 0, (1...10).contains(d)
        else { return nil }
        return (s, d)
    }

    // MARK: Collection JSON

    static func parseModels(_ json: String) -> [Int64: Model] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [:] }
        var models: [Int64: Model] = [:]
        for (key, value) in object {
            guard let id = Int64(key) ?? (value["id"] as? NSNumber)?.int64Value else { continue }
            let fields = ((value["flds"] as? [[String: Any]]) ?? [])
                .sorted { (($0["ord"] as? NSNumber)?.intValue ?? 0) < (($1["ord"] as? NSNumber)?.intValue ?? 0) }
                .compactMap { $0["name"] as? String }
            let templates = ((value["tmpls"] as? [[String: Any]]) ?? []).enumerated().map { index, t in
                Model.Template(ord: (t["ord"] as? NSNumber)?.intValue ?? index,
                               question: t["qfmt"] as? String ?? "", answer: t["afmt"] as? String ?? "")
            }
            models[id] = Model(isCloze: (value["type"] as? NSNumber)?.intValue == 1, fields: fields,
                               templates: templates, name: value["name"] as? String ?? "")
        }
        return models
    }

    static func parseDecks(_ json: String) -> [Int64: String] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [:] }
        var decks: [Int64: String] = [:]
        for (key, value) in object {
            guard let id = Int64(key) ?? (value["id"] as? NSNumber)?.int64Value, let name = value["name"] as? String else { continue }
            decks[id] = name
        }
        return decks
    }

    /// "Biology::Unit 3::Cell cycle" → "Cell cycle". Anki's old separator was "::"; newer ones store \u{1f}.
    static func leafName(_ deck: String) -> String {
        let parts = deck.replacingOccurrences(of: "\u{1f}", with: "::").components(separatedBy: "::")
        return parts.last?.trimmingCharacters(in: .whitespaces).nonEmpty ?? deck
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// A read-only SQLite connection with just what the importer needs.
final class SQLiteReader {
    struct Row {
        fileprivate var values: [Any?]

        func int(_ index: Int) -> Int64 {
            switch values[index] {
            case let v as Int64: v
            case let v as Double: Int64(v)
            case let v as String: Int64(v) ?? 0
            default: 0
            }
        }

        func text(_ index: Int) -> String {
            switch values[index] {
            case let v as String: v
            case let v as Int64: String(v)
            case let v as Double: String(v)
            default: ""
            }
        }
    }

    private var db: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw CaptureError.ankiUnreadable("open")
        }
    }

    deinit { sqlite3_close(db) }

    func rows(_ sql: String) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CaptureError.ankiUnreadable(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        var result: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw CaptureError.ankiUnreadable(String(cString: sqlite3_errmsg(db))) }
            let count = sqlite3_column_count(statement)
            var values: [Any?] = []
            values.reserveCapacity(Int(count))
            for column in 0..<count {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: values.append(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: values.append(sqlite3_column_double(statement, column))
                case SQLITE_TEXT, SQLITE_BLOB:
                    if let pointer = sqlite3_column_text(statement, column) {
                        values.append(String(cString: pointer))
                    } else {
                        values.append(nil)
                    }
                default: values.append(nil)
                }
            }
            result.append(Row(values: values))
        }
        return result
    }
}
