import Foundation

/// The free plan's limits (the server's meters say the same; these are what the app assumes before it has heard
/// from the server, and in builds with no relay). The offline rules (T0) never count against them.
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
}

/// AI use counted on this iPhone against the free limits: this iPhone's own model (which the server never sees),
/// and the cloud requests sent from here (so a limit holds before the server's count has been fetched, or after
/// midnight made it stale). Kept in UserDefaults; the counts reset when their day or week changes.
struct AIUsageLedger: Codable, Equatable, Sendable {
    /// "2026-10-22" of the counts for daily meters.
    var day = ""
    /// "2026-W43" of the counts for weekly meters.
    var week = ""
    /// Meter key → uses of this iPhone's model in its current period.
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

extension AIFreeLimits {
    /// Every meter, in the order the UI lists them. (A list here rather than a `CaseIterable` conformance on the
    /// contract's type, which belongs to the orchestrator.)
    static let keys: [QuotaMeter.Key] = [.scans, .grades, .tutor, .lectures]
}
