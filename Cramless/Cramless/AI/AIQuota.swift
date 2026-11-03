import Foundation

/// The free plan's limits (the server's meters say the same; these are what the app assumes before it has heard
/// from the server, and in builds with no relay). They pay for Cloud AI, so only Cloud AI counts against them: the offline
/// rules (T0) and this iPhone's own model (T1) cost nothing and never do.
enum AIFreeLimits {
    static func limit(_ key: QuotaMeter.Key) -> Int {
        switch key {
        case .scans: 3
        case .grades: 20
        case .tutor: 10
        case .lectures: 1
        }
    }

    /// The line when a free plan's drafts for the day are used up (the relay's own words are in plans.ts).
    static let draftsMessage = String(localized: "That's today's 3 free drafts. Capling Pro lifts the daily limit, and Cap can still answer from your notes.")

    static func period(_ key: QuotaMeter.Key) -> QuotaMeter.Period {
        switch key {
        case .scans, .lectures: .week
        case .grades, .tutor: .day
        }
    }

    /// The paywall's line when a limit is reached: the relay's own words (`supabase/functions/_shared/plans.ts`),
    /// so the line reads the same whether the server or this iPhone noticed the limit.
    static func message(for key: QuotaMeter.Key, limit: Int? = nil) -> String {
        let n = limit ?? self.limit(key)
        switch key {
        case .scans:
            return "That's this week's \(n) AI scans on the free plan. Scanning on your iPhone still works, and it resets on Monday."
        case .grades:
            return "That's today's \(n) graded answers on the free plan. Quick check still works, and it resets at midnight."
        case .tutor:
            return "That's today's \(n) tutor messages on the free plan. It resets at midnight."
        case .lectures:
            return "That's this week's AI notes for \(n) lecture on the free plan. Transcripts still work, and it resets on Monday."
        }
    }

    /// The line on the paywall card when a free limit takes Cloud AI away from a job on this iPhone's own count, in words that are
    /// true for what stopped: the free Cloud AI checks are used, and `deviceKeepsWorking` says whether this iPhone's AI is still
    /// there to do the job. (`message(for:)` is the relay's own text, which says the same for the other meters; a limit the relay
    /// reports keeps its words.)
    static func cardLine(for key: QuotaMeter.Key, limit: Int? = nil, deviceKeepsWorking: Bool) -> String {
        switch key {
        case .grades:
            let n = limit ?? self.limit(key)
            return deviceKeepsWorking
                ? "That's today's \(n) free Cloud AI checks. Your iPhone's AI keeps checking your answers, and the free ones come back at midnight."
                : "That's today's \(n) free Cloud AI checks. You can still mark your answers yourself, and the free ones come back at midnight."
        case .scans, .tutor, .lectures:
            return message(for: key, limit: limit)
        }
    }
}

/// AI use counted on this iPhone: the cloud requests sent from here, which is what the free limits count (so a limit holds before
/// the server's count has been fetched, or after midnight made it stale), and this iPhone's own model, which is only kept on the
/// side. A limit pays for Cloud AI, so this iPhone's model never counts against one. Kept in UserDefaults; the counts reset when
/// their day or week changes.
struct AIUsageLedger: Codable, Equatable, Sendable {
    /// "2026-10-22" of the counts for daily meters.
    var day = ""
    /// "2026-W43" of the counts for weekly meters.
    var week = ""
    /// Meter key → uses of this iPhone's model in its current period. Never part of a limit.
    var counts: [String: Int] = [:]
    /// Meter key → cloud requests sent from this iPhone in its current period. The server's own count, when
    /// current, already includes them: the two are combined with `max`, never added.
    var cloudCounts: [String: Int] = [:]

    static let defaultsKey = "capling.ai.usage.v1"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        week = try c.decodeIfPresent(String.self, forKey: .week) ?? ""
        counts = try c.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        cloudCounts = try c.decodeIfPresent([String: Int].self, forKey: .cloudCounts) ?? [:]
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The week as the relay counts it: starting on Monday in the person's time zone, whatever the locale's first
    /// weekday (an ISO week).
    static func weekKey(_ date: Date, calendar: Calendar) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// Clears the counts whose period has ended.
    mutating func roll(to now: Date, calendar: Calendar) {
        let d = Self.dayKey(now, calendar: calendar), w = Self.weekKey(now, calendar: calendar)
        if d != day {
            day = d
            for key in AIFreeLimits.keys where AIFreeLimits.period(key) == .day {
                counts[key.rawValue] = 0
                cloudCounts[key.rawValue] = 0
            }
        }
        if w != week {
            week = w
            for key in AIFreeLimits.keys where AIFreeLimits.period(key) == .week {
                counts[key.rawValue] = 0
                cloudCounts[key.rawValue] = 0
            }
        }
    }

    /// Uses of this iPhone's model.
    func used(_ key: QuotaMeter.Key) -> Int { counts[key.rawValue] ?? 0 }

    /// Cloud requests sent from this iPhone.
    func cloudUsed(_ key: QuotaMeter.Key) -> Int { cloudCounts[key.rawValue] ?? 0 }

    mutating func record(_ key: QuotaMeter.Key, now: Date, calendar: Calendar) {
        roll(to: now, calendar: calendar)
        counts[key.rawValue, default: 0] += 1
    }

    mutating func recordCloud(_ key: QuotaMeter.Key, now: Date, calendar: Calendar) {
        roll(to: now, calendar: calendar)
        cloudCounts[key.rawValue, default: 0] += 1
    }

    static func load(from defaults: UserDefaults) -> AIUsageLedger {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder.cramless.decode(AIUsageLedger.self, from: data) else { return AIUsageLedger() }
        return value
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder.cramless.encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// The relay's scan window, as far as this iPhone can follow it, so a scan is counted once however many requests make it up.
///
/// A "scan" is one capture session (`cramless_consume_scan`): the first page reading or question-writing request opens a window
/// and costs one scan; the requests that follow ride on it for free while it is open (30 minutes, the same week) and its pages stay
/// within the plan's, with one exception: a question-writing request closes the window (`generated`), so the next one opens a
/// new window and costs another scan. So a page read followed by one generate is one scan; two generates are two.
///
/// Only successful requests are recorded (the relay gives a failed request's scan back).
struct ScanWindow: Equatable, Sendable {
    enum Kind: Sendable { case transcribe, generate }

    private(set) var openedAt: Date?
    private(set) var week = ""
    private(set) var generated = true
    private(set) var pages = 0

    static let lifetime: TimeInterval = 30 * 60

    /// A question-writing request now would ride on the open window, and so cost nothing.
    func canRideGenerate(at now: Date, week: String) -> Bool { isOpen(at: now, week: week) }

    private func isOpen(at now: Date, week: String) -> Bool {
        guard let openedAt, !generated, self.week == week else { return false }
        return now.timeIntervalSince(openedAt) < Self.lifetime
    }

    /// Records a request that succeeded. True when it opened a new window, which is a new scan.
    mutating func record(_ kind: Kind, pages requestPages: Int, at now: Date, week: String, pageCap: Int) -> Bool {
        if isOpen(at: now, week: week), kind == .generate || pages + requestPages <= pageCap {
            if kind == .transcribe { pages += requestPages } else { generated = true }
            return false
        }
        openedAt = now
        self.week = week
        pages = requestPages
        generated = kind == .generate
        return true
    }
}

extension AIFreeLimits {
    /// Every meter, in the order the UI lists them. (A list here rather than a `CaseIterable` conformance on the
    /// contract's type, which belongs to the orchestrator.)
    static let keys: [QuotaMeter.Key] = [.scans, .grades, .tutor, .lectures]
}

/// What one reading may ask of Cloud AI: the pages the relay takes in one scan, and the questions a source earns.
extension AIFreeLimits {
    /// Pages in one AI scan on the free plan and on a paid one: the relay's `PAGES_PER_SCAN`
    /// (`supabase/functions/_shared/plans.ts`). A longer reading is cut into parts that fit; each part is a scan.
    static let pagesPerScanFree = 10
    static let pagesPerScanPaid = 40

    static func pagesPerScan(_ plan: Plan) -> Int { plan.isPaid ? pagesPerScanPaid : pagesPerScanFree }

    /// A set has about one question for every 150 words of the source, at least 8, and at most 24 on the free plan and 40
    /// on a paid one. The free cap is deliberate: 40 questions cost the relay about 5 cents of model calls, and one account
    /// may spend 10 cents a day.
    static let wordsPerQuestion = 150
    static let minimumQuestions = 8
    static let maximumQuestionsFree = 24
    static let maximumQuestionsPaid = 40

    static func maximumQuestions(_ plan: Plan) -> Int { plan.isPaid ? maximumQuestionsPaid : maximumQuestionsFree }

    /// One generate request writes its questions in a single call, at about three seconds each (a live request for 14
    /// questions took 46 seconds; the route's timeout is 120 and a Supabase function stops at about 150). So no request asks
    /// for more than 20, whatever the plan. A source that deserves more is written in parts: a paid plan splits above 20; a
    /// free reading is split only by its 10-page cap and never to reach a higher count.
    static let maximumQuestionsPerRequest = 20

    /// The questions to ask for from a source of `words` words.
    static func questionCount(words: Int, plan: Plan) -> Int {
        let wanted = Int((Double(max(0, words)) / Double(wordsPerQuestion)).rounded())
        return min(maximumQuestions(plan), max(minimumQuestions, wanted))
    }

    /// Questions asked for from a recorded lecture's transcript.
    static let lectureQuestions = 10

    /// This iPhone's own model is slow and less accurate on a long reading, so it keeps aiming for 16 questions however
    /// long the source is (the offline rules and Cloud AI take the larger count).
    static let onDeviceQuestions = 16
}
