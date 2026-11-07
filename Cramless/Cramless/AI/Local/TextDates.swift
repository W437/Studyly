import Foundation

/// The dates in a line of text, on the student's calendar. `NSDataDetector` finds them and understands many languages, but it counts every
/// relative word from the moment it runs and takes "Oct 3" as this year's even after it has gone by. So what it says is used for the words it
/// matched and their month, day and weekday, and the day is worked out here, from `anchor`: the day a lecture was recorded, or today for a
/// syllabus. Nothing reads the clock, so a lecture read a month later means what it meant, and a test means the same on any day.
enum TextDates {
    struct Hit: Equatable, Sendable {
        /// yyyy-MM-dd.
        var day: String
        var hour: Int?
        var minute: Int?
        /// The words that say it.
        var quote: String
        var range: Range<String.Index>
        /// The words count from `anchor` ("next Friday", "in two weeks"), rather than naming a day.
        var isRelative: Bool

        /// HH:mm, when the words give a time.
        var time: String? {
            guard let hour, let minute else { return nil }
            return String(format: "%02d:%02d", hour, minute)
        }
    }

    nonisolated(unsafe) private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    nonisolated(unsafe) private static let inSoMany = try? NSRegularExpression(
        pattern: #"\bin\s+(a|an|one|two|three|four|five|six|seven|eight|nine|ten|\d{1,2})\s+(day|week)s?\b"#, options: [.caseInsensitive])
    nonisolated(unsafe) private static let aClockTime = try? NSRegularExpression(
        pattern: #"\d{1,2}:\d{2}|\b\d{1,2}\s*(?:am|pm|a\.m\.|p\.m\.)|\bat\s+\d{1,2}\b|\bnoon\b"#, options: [.caseInsensitive])
    nonisolated(unsafe) private static let aFullYear = try? NSRegularExpression(pattern: #"\b(?:19|20)\d{2}\b|/\d{2}\b"#)
    /// A clock time with no day, in the words a detector takes for one: "at 1", "at nine".
    nonisolated(unsafe) private static let aBareTime = try? NSRegularExpression(
        pattern: #"^\s*(?:at|by|around|a\s+las?|um|à|alle|ore)?\s*(?:\d{1,2}(?::\d{2})?(?:\s*(?:am|pm|a\.m\.|p\.m\.|uhr|h))?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|noon)\s*$"#, options: [.caseInsensitive])

    private static let monthWords = ["january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
                                     "september": 9, "sept": 9, "sep": 9, "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12]
    /// A day of the month as a recogniser writes it when it spells it out.
    private static let dayWords: [String: Int] = {
        var table: [String: Int] = [:]
        let ones = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth"]
        let plainOnes = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        for (i, word) in ones.enumerated() {
            table[word] = i + 1
            table["twenty \(word)"] = 21 + i
        }
        table["thirty first"] = 31
        for (i, word) in plainOnes.enumerated() { table["twenty \(word)"] = 21 + i }
        table["thirty one"] = 31
        for (i, word) in ["tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth"].enumerated() { table[word] = 10 + i }
        table["thirtieth"] = 30
        return table
    }()
    private static let dayWordPattern = #"(?:(?:twenty|thirty)[\s-](?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|one|two|three|four|five|six|seven|eight|nine)|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|twentieth|thirtieth)"#
    private static let monthPattern = #"(?:january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)\.?"#
    /// "November twenty third", "the twentieth of November". In digits, with or without a year, the detector reads them.
    nonisolated(unsafe) private static let monthThenDay = try? NSRegularExpression(pattern: #"\b("# + monthPattern + #")\s+(?:the\s+)?("# + dayWordPattern + #")\b"#, options: [.caseInsensitive])
    nonisolated(unsafe) private static let dayOfMonth = try? NSRegularExpression(pattern: #"\bthe\s+("# + dayWordPattern + #")\s+of\s+("# + monthPattern + #")"#, options: [.caseInsensitive])
    /// "on the twentieth": the next time that day comes round.
    nonisolated(unsafe) private static let onTheDay = try? NSRegularExpression(pattern: #"\b(?:on|by)\s+the\s+("# + dayWordPattern + #"|\d{1,2}(?:st|nd|rd|th))\b(?!\s+of\b)"#, options: [.caseInsensitive])
    /// "11月20日 11時", "2026年11月16日": written dates in Japanese and Chinese, which the detector doesn't read.
    nonisolated(unsafe) private static let cjkDate = try? NSRegularExpression(pattern: #"(?:(\d{4})\s*年\s*)?(\d{1,2})\s*月\s*(\d{1,2})\s*[日号](?:\s*(\d{1,2})\s*[時时点])?"#)
    /// A time at the end of what the detector read, with no day: "starts at 1".
    nonisolated(unsafe) private static let endsInATime = try? NSRegularExpression(pattern: #"\b(?:at|by|around)\s+\d{1,2}(?::\d{2})?(?:\s*(?:am|pm))?\s*$"#, options: [.caseInsensitive])
    /// A day the detector can read, in English.
    nonisolated(unsafe) private static let namesADay = try? NSRegularExpression(pattern: #"\b(?:sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat)(?:day|nesday|rsday|urday|sday)?\b|\b(?:today|tonight|tomorrow|next|this)\b|\b"# + monthPattern, options: [.caseInsensitive])
    /// "a week from Monday".
    nonisolated(unsafe) private static let weekFrom = try? NSRegularExpression(
        pattern: #"\b(a|an|one|two|three)\s+weeks?\s+from\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#, options: [.caseInsensitive])

    private static let counts = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// The dates in `text`, in order. A date said to be in the past ("last Friday") isn't one.
    static func find(in text: String, from anchor: Date, calendar: Calendar) -> [Hit] {
        guard let detector, !text.isEmpty else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        // Said aloud, a date comes in words the detector doesn't read, or reads as something else ("a week from Monday" as this Monday): these come first.
        var hits = spokenDates(in: text, from: anchor, calendar: calendar)
        for match in detector.matches(in: text, range: whole) {
            guard let found = hit(from: match, in: text, anchor: anchor, calendar: calendar), !hits.contains(where: { $0.range.overlaps(found.range) }) else { continue }
            hits.append(found)
        }
        // "in two weeks" where the detector doesn't read it (it depends on the words around it).
        for match in inSoMany?.matches(in: text, range: whole) ?? [] {
            guard let range = Range(match.range, in: text), !hits.contains(where: { $0.range.overlaps(range) }),
                  let amount = Range(match.range(at: 1), in: text), let unit = Range(match.range(at: 2), in: text),
                  let days = days(amount: String(text[amount]), unit: String(text[unit])) else { continue }
            hits.append(Hit(day: calendar.dayKey(for: calendar.adding(days: days, to: anchor)), quote: String(text[range]), range: range, isRelative: true))
        }
        return hits.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func dayNumber(_ words: String) -> Int? {
        let lower = words.lowercased().replacingOccurrences(of: "-", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let known = dayWords[lower] { return known }
        return Int(lower.prefix { $0.isNumber })
    }

    private static func spokenDates(in text: String, from anchor: Date, calendar: Calendar) -> [Hit] {
        let whole = NSRange(text.startIndex..., in: text)
        var out: [Hit] = []
        func add(_ match: NSTextCheckingResult, month: Int, day: Int) {
            guard let range = Range(match.range, in: text), !out.contains(where: { $0.range.overlaps(range) }),
                  let found = nextOccurrence(month: month, day: day, year: nil, anchor: anchor, calendar: calendar) else { return }
            out.append(Hit(day: calendar.dayKey(for: found), quote: String(text[range]), range: range, isRelative: false))
        }
        func word(_ match: NSTextCheckingResult, _ group: Int) -> String? { Range(match.range(at: group), in: text).map { String(text[$0]).lowercased() } }
        func month(_ words: String) -> Int? { monthWords[words.trimmingCharacters(in: CharacterSet(charactersIn: "."))] }
        for match in monthThenDay?.matches(in: text, range: whole) ?? [] {
            if let m = word(match, 1).flatMap(month), let d = word(match, 2).flatMap(dayNumber) { add(match, month: m, day: d) }
        }
        for match in dayOfMonth?.matches(in: text, range: whole) ?? [] {
            if let d = word(match, 1).flatMap(dayNumber), let m = word(match, 2).flatMap(month) { add(match, month: m, day: d) }
        }
        for match in onTheDay?.matches(in: text, range: whole) ?? [] {
            guard let d = word(match, 1).flatMap(dayNumber), (1...31).contains(d), let range = Range(match.range, in: text), !out.contains(where: { $0.range.overlaps(range) }) else { continue }
            let start = calendar.startOfDay(for: anchor)
            for ahead in 0...2 {
                guard let first = calendar.date(byAdding: .month, value: ahead, to: start) else { continue }
                var parts = calendar.dateComponents([.year, .month], from: first)
                parts.day = d
                parts.hour = 12
                if let date = calendar.date(from: parts), calendar.component(.day, from: date) == d, date >= start {
                    out.append(Hit(day: calendar.dayKey(for: date), quote: String(text[range]), range: range, isRelative: false))
                    break
                }
            }
        }
        for match in cjkDate?.matches(in: text, range: whole) ?? [] {
            guard let range = Range(match.range, in: text), let m = word(match, 2).flatMap({ Int($0) }), let d = word(match, 3).flatMap({ Int($0) }),
                  let found = nextOccurrence(month: m, day: d, year: word(match, 1).flatMap { Int($0) }, anchor: anchor, calendar: calendar) else { continue }
            let hour = word(match, 4).flatMap { Int($0) }
            out.append(Hit(day: calendar.dayKey(for: found), hour: hour, minute: hour == nil ? nil : 0, quote: String(text[range]), range: range, isRelative: false))
        }
        for match in weekFrom?.matches(in: text, range: whole) ?? [] {
            guard let range = Range(match.range, in: text), let amount = word(match, 1), let n = counts[amount], let name = word(match, 2),
                  let weekday = weekdayNames.firstIndex(of: name) else { continue }
            let next = nextWeekday(weekday + 1, after: anchor, skippingThisWeek: false, calendar: calendar)
            out.append(Hit(day: calendar.dayKey(for: calendar.adding(days: n * 7, to: next)), quote: String(text[range]), range: range, isRelative: true))
        }
        return out
    }

    /// The date at `hour:minute` (9:00 without a time) on a day given as yyyy-MM-dd. Nil for a day that doesn't exist.
    static func date(day: String, time: String? = nil, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var hour = 9, minute = 0
        if let clock = time?.split(separator: ":").compactMap({ Int($0) }), clock.count == 2, (0...23).contains(clock[0]), (0...59).contains(clock[1]) {
            hour = clock[0]
            minute = clock[1]
        }
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute)),
              calendar.component(.day, from: date) == parts[2] else { return nil }
        return date
    }

    private static func days(amount: String, unit: String) -> Int? {
        let lower = amount.lowercased()
        guard let n = Int(lower) ?? counts[lower], n > 0 else { return nil }
        return unit.lowercased().hasPrefix("week") ? n * 7 : n
    }

    private static func hit(from match: NSTextCheckingResult, in text: String, anchor: Date, calendar: Calendar) -> Hit? {
        guard let date = match.date, let range = Range(match.range, in: text) else { return nil }
        let quote = String(text[range])
        let lower = quote.lowercased()
        if lower.contains("last ") || lower.contains("yesterday") || lower.contains("ago") || lower.contains("from today") { return nil }
        // A time with no day says nothing about when ("starts at 1 MSS").
        let quoted = NSRange(quote.startIndex..., in: quote)
        if aBareTime?.firstMatch(in: quote, range: quoted) != nil { return nil }
        if let time = endsInATime?.firstMatch(in: quote, range: quoted), namesADay?.firstMatch(in: quote, range: quoted) == nil, let at = Range(time.range, in: quote),
           !quote[..<at.lowerBound].contains(where: \.isNumber) {
            return nil
        }
        // The detector's answer is in this device's time zone (or the one it read), whatever calendar the app is on.
        var detected = Calendar(identifier: .gregorian)
        detected.timeZone = match.timeZone ?? .current
        let parts = detected.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        let whole = NSRange(lower.startIndex..., in: lower)
        let hasTime = aClockTime?.firstMatch(in: lower, range: whole) != nil
        let hour = hasTime ? parts.hour : nil
        let minute = hasTime ? (parts.minute ?? 0) : nil

        func relative(_ day: Date) -> Hit {
            Hit(day: calendar.dayKey(for: day), hour: hour, minute: minute, quote: quote, range: range, isRelative: true)
        }
        if lower.contains("tomorrow") { return relative(calendar.adding(days: 1, to: anchor)) }
        if lower.contains("today") || lower.contains("tonight") { return relative(anchor) }
        if let amount = inSoMany?.firstMatch(in: lower, range: whole), let a = Range(amount.range(at: 1), in: lower),
           let u = Range(amount.range(at: 2), in: lower), let days = days(amount: String(lower[a]), unit: String(lower[u])) {
            return relative(calendar.adding(days: days, to: anchor))
        }
        // A month and a day (a weekday beside them changes nothing): the first time it comes round. The digits have to be the date's, not a time's.
        var withoutTime = lower
        for time in (aClockTime?.matches(in: lower, range: whole) ?? []).reversed() {
            if let r = Range(time.range, in: withoutTime) { withoutTime.removeSubrange(r) }
        }
        if withoutTime.contains(where: \.isNumber), let month = parts.month, let day = parts.day {
            let named = aFullYear?.firstMatch(in: lower, range: whole) != nil ? parts.year : nil
            guard let found = nextOccurrence(month: month, day: day, year: named, anchor: anchor, calendar: calendar) else { return nil }
            return Hit(day: calendar.dayKey(for: found), hour: hour, minute: minute, quote: quote, range: range, isRelative: false)
        }
        // A weekday, in any language the detector knows.
        guard let weekday = parts.weekday else { return nil }
        // "viernes 15": a weekday with a day of the month after it. A Friday that isn't the 15th was misheard.
        let after = text[range.upperBound...].drop { $0 == " " }.prefix { $0.isNumber }
        if let said = Int(after), (1...31).contains(said) {
            let start = calendar.startOfDay(for: anchor)
            for ahead in 0...6 {
                guard let month = calendar.date(byAdding: .month, value: ahead, to: start) else { continue }
                var want = calendar.dateComponents([.year, .month], from: month)
                want.day = said
                want.hour = 12
                if let date = calendar.date(from: want), calendar.component(.day, from: date) == said, date >= start {
                    return calendar.component(.weekday, from: date) == weekday ? relative(date) : nil
                }
            }
            return nil
        }
        let startsNext = lower.hasPrefix("next ")
        return relative(nextWeekday(weekday, after: anchor, skippingThisWeek: startsNext, calendar: calendar))
    }

    /// This month and day on or after `anchor`: this year's or next year's, or the year named.
    private static func nextOccurrence(month: Int, day: Int, year: Int?, anchor: Date, calendar: Calendar) -> Date? {
        func make(_ y: Int) -> Date? {
            guard let date = calendar.date(from: DateComponents(year: y, month: month, day: day, hour: 12)),
                  calendar.component(.day, from: date) == day else { return nil }
            return date
        }
        if let year { return make(year) }
        let start = calendar.startOfDay(for: anchor)
        let thisYear = calendar.component(.year, from: anchor)
        for y in [thisYear, thisYear + 1, thisYear + 2] {
            if let date = make(y), date >= start { return date }
        }
        return nil
    }

    /// The next time it is that weekday, after `anchor`. "Next Friday", said on a Wednesday, means the one after this week's.
    private static func nextWeekday(_ weekday: Int, after anchor: Date, skippingThisWeek: Bool, calendar: Calendar) -> Date {
        let today = calendar.component(.weekday, from: anchor)
        var ahead = (weekday - today + 7) % 7
        if ahead == 0 { ahead = 7 }
        if skippingThisWeek {
            let intoWeek = (today - calendar.firstWeekday + 7) % 7
            if intoWeek + ahead < 7 { ahead += 7 }
        }
        return calendar.adding(days: ahead, to: anchor)
    }
}

/// The words for an exam, shared by a syllabus and a lecture. "Final paper" and "test tube" aren't exams.
enum ExamWords {
    struct Found: Equatable, Sendable {
        /// "Midterm", "Final exam", "Quiz 2".
        var title: String
        var range: Range<String.Index>
    }

    nonisolated(unsafe) private static let pattern: NSRegularExpression? = {
        let notExam = #"(?!\s+(?:of\b|shows?|battles?|wars?|acts?|scenes?|episodes?|seasons?|tubes?|cases?|subjects?|results?|scores?|answers?|steps?|pages?|slides?|products?|stages?|phases?|versions?|rounds?|drafts?|days?|weeks?|chapters?|sections?|grades?|rooms?|halls?|dates?|times?|strips?|runs?|drives?|cells?|samples?|groups?|conditions?|papers?|projects?|essays?|reports?|presentations?|thoughts?|words?|say|points?|reviews?|prep|policy|format|schedule)\b)"#
        let words = #"mid-?terms?(?:\s+[1-4](?![\d%]))?|finals?(?:\s+exams?)?|quiz(?:zes)?(?:\s+\d{1,2})?|tests?(?:\s+\d{1,2})?|exams?(?:\s+\d{1,2})?|"#
            + #"examen|exámenes|parcial|partiel|interro|contrôle|prüfung|klausur|esame|prova"#
        return try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}-])(?:"# + words + #")(?![\p{L}\p{N}-])"# + notExam + #"|מבחן|בחינה|試験|テスト|考试|시험"#, options: [.caseInsensitive])
    }()

    /// Every exam word in `text`, in order.
    static func all(in text: String) -> [Found] {
        guard let pattern else { return [] }
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return Found(title: title(of: String(text[range])), range: range)
        }
    }

    static func first(in text: String) -> Found? { all(in: text).first }

    /// "mid-term" is "Midterm", "finals" is "Final", "final exam" is "Final exam", "QUIZ 2" is "Quiz 2".
    static func title(of word: String) -> String {
        let lower = word.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if lower.hasPrefix("mid") {
            let number = lower.split(separator: " ").dropFirst().first
            return number.map { String(localized: "Midterm \(String($0))") } ?? String(localized: "Midterm")
        }
        if lower.hasPrefix("final") { return lower.contains("exam") ? String(localized: "Final exam") : String(localized: "Final") }
        if lower.hasPrefix("quiz") {
            let number = lower.split(separator: " ").dropFirst().first
            return number.map { String(localized: "Quiz \(String($0))") } ?? String(localized: "Quiz")
        }
        return Lexicon.capitalizedFirst(lower.hasSuffix("s") && !lower.contains(" ") ? String(lower.dropLast()) : lower)
    }

    /// Two names for the same exam ("Midterm" and "Bio 101 Midterm", "Final" and "Final exam").
    static func sameExam(_ a: String, _ b: String) -> Bool {
        let words = { (name: String) -> Set<String> in
            Set(all(in: name).map { $0.title.lowercased().replacingOccurrences(of: " exam", with: "") })
        }
        let left = words(a), right = words(b)
        return !left.isEmpty && !left.isDisjoint(with: right)
    }
}
