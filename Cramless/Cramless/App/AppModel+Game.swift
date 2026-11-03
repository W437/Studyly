import Foundation
import SwiftData
import UIKit

// The game loop: daily quests, badges, the app icons and skies they unlock, and when to ask for a rating. There is no
// currency and nothing to lose: a quest finished stays finished, a badge earned stays earned, an icon or a sky unlocked
// stays unlocked.
//
// What is stored and where:
// - The quests a day finished: `DayRecord.questMask`, one bit per `QuestKind`. It syncs and merges by OR.
// - Today's picks: `settings.questDay`, on this device (they are the same on every device unless the day's material differs).
// - Weeks of 12 quests: `settings.litWeeks`; each lit one sky (`SkyTheme.unlockOrder`).
// - Badges: worked out again from the log every time (`achievementFacts`); `settings.badges` only remembers which the person
//   has been told about, and when.

// MARK: - What the views read

/// One of today's quests as Today and the summary show it.
struct QuestRow: Identifiable, Equatable, Sendable {
    var kind: QuestKind
    var progress: QuestProgress
    /// Finished today: the day's answers say so, or the mask does.
    var isDone: Bool
    /// What the quest names, when it names something (the exam, for the exam quest).
    var subject: String?

    var id: Int { kind.rawValue }
}

struct QuestsToday: Equatable, Sendable {
    var rows: [QuestRow] = []
    /// Quests finished this calendar week, and what finishing that many lights.
    var week = 0
    var weekGoal = QuestEngine.weeklyGoal
    /// The sky a week of quests would light next (nil when every sky is lit).
    var nextSky: SkyTheme?
    /// This week has lit its sky already.
    var weekLit = false

    var done: Int { rows.filter(\.isDone).count }
    var isEmpty: Bool { rows.isEmpty }
}

/// What a finished session did to the game loop, for the summary.
struct GameOutcome: Equatable, Sendable {
    /// Quests this session finished.
    var questsDone: [QuestKind] = []
    var weekBefore = 0
    var weekAfter = 0
    var weekGoal = QuestEngine.weeklyGoal
    /// A sky the week's quests lit.
    var skyLit: SkyTheme?
    /// Badges this session earned.
    var badges: [Badge] = []

    var isEmpty: Bool { questsDone.isEmpty && skyLit == nil && badges.isEmpty }
}

/// A badge as Progress shows it.
struct BadgeStatus: Identifiable, Equatable, Sendable {
    var badge: Badge
    var progress: BadgeProgress
    /// When the person was told they had it; nil while it isn't earned.
    var earnedAt: Date?

    var id: String { badge.rawValue }
    var isEarned: Bool { earnedAt != nil || progress.isEarned }
}

/// The whole log's badge facts for one revision, so the Progress tab and the summary don't each read it again, and what the last scan
/// of the log found, so a new answer is a look at the newest entries and not the whole log again.
final class GameCache {
    var facts: (revision: Int, value: AchievementFacts)?
    var scan: LogScan?

    struct LogScan {
        /// How many answers the scan covered, and the newest of them.
        var count: Int
        var newest: Date
        var saves: Int
        var ownWords: Int
    }
}

// MARK: - Icons

/// Switching the app icon. The system's switcher shows its own alert; tests use a fake.
@MainActor
protocol AppIconSwitching {
    var supportsAlternates: Bool { get }
    var current: AppIconChoice { get }
    func apply(_ icon: AppIconChoice) async throws
}

@MainActor
struct SystemIconSwitcher: AppIconSwitching {
    var supportsAlternates: Bool { UIApplication.shared.supportsAlternateIcons }
    var current: AppIconChoice { AppIconChoice(alternateName: UIApplication.shared.alternateIconName) }

    func apply(_ icon: AppIconChoice) async throws {
        try await UIApplication.shared.setAlternateIconName(icon.alternateName)
    }
}

// MARK: - Quests

extension AppModel {
    private var todayKey: String { calendar.dayKey(for: now) }

    /// Stands in for the session of an answer that has none, when runs are counted.
    private static let noSession = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// How many answers or sessions a count needs, read without loading them.
    private func count<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        (try? context.fetchCount(descriptor)) ?? 0
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The soonest exam in the next month, which the exam quest is about.
    private func questExam() -> ExamSnapshot? {
        examSnapshots(upcomingOnly: true).first { calendar.dayDistance(from: now, to: $0.date) <= 30 }
    }

    /// What the day's picks depend on, as of now.
    func questContext() -> QuestContext {
        let items = itemSnapshots()
        let fsrs = self.fsrs
        let now = self.now
        var context = QuestContext()
        context.minuteOfDay = minuteOfDay(now)
        context.hasMaterial = !items.isEmpty
        context.examEve = examSnapshots(upcomingOnly: true).contains { calendar.dayDistance(from: now, to: $0.date) == 1 }
        context.fadingStars = items.filter {
            $0.isStudied && fsrs.retrievability(of: $0.memory, at: now) < ReviewOutcome.fadingRecall
        }.count
        context.ownWordsItems = items.filter { $0.kind.isOwnWords }.count
        context.openMixUps = confusionSnapshots().filter { $0.status == .open }.count
        context.newItems = items.filter { $0.memory.state == .new }.count
        context.checkedItems = items.filter { $0.kind != .flashcard }.count
        if let exam = questExam() { context.examItems = items.filter { exam.covers($0) }.count }
        if let stored = settings.questDay, calendar.dayNumber(forKey: stored.dayKey) == calendar.dayNumber(for: now) - 1 {
            context.yesterday = stored.kinds
        }
        return context
    }

    /// Today's quests: the picks stored for today, else what the day would pick now (not stored; `ensureQuestPicks` does).
    func todayQuestKinds() -> [QuestKind] {
        if let stored = settings.questDay, stored.dayKey == todayKey { return stored.kinds }
        return pickQuests()
    }

    /// What the engine picks for today with the material there is now (a film can name its own: `CRAMLESS_QUEST_PICKS`).
    private func pickQuests() -> [QuestKind] {
        #if DEBUG
        if let raw = TestHarness.value("CRAMLESS_QUEST_PICKS") {
            let named = raw.split(separator: ",").compactMap { name in QuestKind.allCases.first { String(describing: $0) == name } }
            if !named.isEmpty { return named }
        }
        #endif
        return QuestEngine.pick(day: calendar.dayNumber(for: now), context: questContext())
    }

    /// Picks today's quests the first time the app is opened that day, and keeps them for the day. A day with nothing to
    /// pick (no material, or exam eve) stores nothing, so the quests appear once there is something to do.
    func ensureQuestPicks() {
        guard settings.questDay?.dayKey != todayKey else { return }
        let kinds = pickQuests()
        guard !kinds.isEmpty else { return }
        settings.questDay = AppSettings.QuestDay(dayKey: todayKey, kinds: kinds)
    }

    /// What a day's answers amount to for the quests, read from the log.
    func questFacts(forDay key: String) -> QuestFacts {
        guard let number = calendar.dayNumber(forKey: key) else { return QuestFacts() }
        let start = calendar.startOfDay(dayNumber: number)
        let end = calendar.startOfDay(dayNumber: number + 1)
        var facts = QuestFacts()

        // Sessions that finished that day (one may have begun the night before).
        let quick = SessionKind.quickCheck.rawValue
        let lookback = calendar.adding(days: -1, to: start)
        let finished = fetch(FetchDescriptor<StudySession>(predicate: #Predicate {
            $0.startedAt >= lookback && $0.kindRaw != quick
        })).compactMap { session -> Date? in
            guard session.itemCount > 0, let ended = session.endedAt, ended >= start, ended < end else { return nil }
            return ended
        }
        facts.sessionsFinished = finished.count
        facts.firstFinishedMinute = finished.min().map(minuteOfDay)

        // Mix-ups fixed that day.
        facts.mixUpsFixed = fetch(FetchDescriptor<Confusion>(predicate: #Predicate { $0.deletedAt == nil }))
            .filter { $0.status == .fixed && $0.updatedAt >= start && $0.updatedAt < end }.count

        let logs = fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.reviewedAt >= start && $0.reviewedAt < end },
                                                    sortBy: [SortDescriptor(\.reviewedAt)]))
        guard !logs.isEmpty else { return facts }
        let ids = Array(Set(logs.map(\.itemID)))
        let items = Dictionary(fetch(FetchDescriptor<StudyItem>(predicate: #Predicate { ids.contains($0.id) }))
            .map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let fsrs = self.fsrs
        let exam = questExam()
        let newState = CardState.new.rawValue
        let good = Rating.good.rawValue
        var seenNew = Set<UUID>()
        var runs: [UUID: Int] = [:]
        for log in logs {
            let item = items[log.itemID]
            let right = log.ratingRaw >= good
            if log.stateBeforeRaw == newState { seenNew.insert(log.itemID) }
            if item?.kind.isOwnWords == true { facts.ownWordsAnswers += 1 }
            // The same test as `ReviewOutcome.isSave`, worked out again from the log.
            if right, log.wasCorrect, log.stateBeforeRaw != newState,
               fsrs.retrievability(elapsedDays: log.elapsedDays, stability: log.stabilityBefore) < ReviewOutcome.fadingRecall {
                facts.saves += 1
            }
            // A run is right answers in one session; a flashcard's self-rating neither builds nor breaks it. An own-words answer the
            // person marked themselves ("self") counts like any other, by its rating, as the session's own run counts it.
            if let kind = item?.kind, kind != .flashcard {
                let session = log.sessionID ?? Self.noSession
                if right {
                    runs[session, default: 0] += 1
                    facts.bestRun = max(facts.bestRun, runs[session] ?? 0)
                } else {
                    runs[session] = 0
                }
            }
            if let exam, let item, exam.covers(ItemSnapshot(item, courseID: item.course?.id)) { facts.examAnswers += 1 }
        }
        facts.newLearned = seenNew.count
        return facts
    }

    /// Today's quests with their progress, and the week so far.
    func questsToday() -> QuestsToday {
        var out = QuestsToday()
        let key = todayKey
        let stored = dayRecord(key: key)?.questMask ?? 0
        var mask = stored
        let kinds = todayQuestKinds()
        if !kinds.isEmpty {
            let facts = questFacts(forDay: key)
            let exam = questExam()
            out.rows = kinds.map { kind in
                let progress = QuestEngine.progress(kind, facts: facts)
                let done = progress.isComplete || stored & kind.bit != 0
                if done { mask |= kind.bit }
                let subject = kind == .examTopic ? exam.map { course($0.courseID)?.name ?? $0.title } : nil
                return QuestRow(kind: kind, progress: done ? QuestProgress(done: kind.goal, goal: kind.goal) : progress,
                                isDone: done, subject: subject)
            }
        }
        out.week = questWeek(including: mask)
        out.weekLit = settings.lastLitWeek == questWeekKey
        out.nextSky = out.weekLit ? nil : SkyTheme.next(afterWeeks: settings.litWeeks)
        return out
    }

    /// At least one real session has finished (onboarding's two-question check doesn't count): quests appear after the first.
    func hasFinishedAnySession() -> Bool {
        let quick = SessionKind.quickCheck.rawValue
        var descriptor = FetchDescriptor<StudySession>(predicate: #Predicate {
            $0.endedAt != nil && $0.itemCount > 0 && $0.kindRaw != quick
        })
        descriptor.fetchLimit = 1
        return !fetch(descriptor).isEmpty
    }

    /// The first day of this calendar week, as a day key: what says which week lit a sky.
    private var questWeekKey: String {
        let start = QuestEngine.weekStart(of: calendar.dayNumber(for: now), firstWeekday: calendar.firstWeekday)
        return calendar.dayKey(for: calendar.startOfDay(dayNumber: start).addingTimeInterval(12 * 3600))
    }

    /// Quests finished this calendar week. `today` replaces today's stored mask, for the quests the answers have finished
    /// that aren't written yet.
    func questWeek(including today: Int? = nil) -> Int {
        let todayNumber = calendar.dayNumber(for: now)
        let first = QuestEngine.weekStart(of: todayNumber, firstWeekday: calendar.firstWeekday)
        let from = calendar.startOfDay(dayNumber: first)
        var masks: [Int: Int] = [:]
        for record in fetch(FetchDescriptor<DayRecord>(predicate: #Predicate { $0.day >= from })) {
            let number = calendar.dayNumber(forKey: record.dayKey) ?? calendar.dayNumber(for: record.day)
            masks[number, default: 0] |= record.questMask
        }
        if let today { masks[todayNumber, default: 0] |= today }
        return QuestEngine.weekCount(masks: masks, today: todayNumber, firstWeekday: calendar.firstWeekday)
    }

    /// Writes the bits of the quests a day's answers have finished (a mask only grows). Returns the ones that are new.
    @discardableResult
    private func settleDay(key: String, picks: [QuestKind]) -> [QuestKind] {
        let done = QuestEngine.completed(picks: picks, facts: questFacts(forDay: key))
        guard !done.isEmpty else { return [] }
        let noon = calendar.startOfDay(dayNumber: calendar.dayNumber(forKey: key) ?? calendar.dayNumber(for: now))
            .addingTimeInterval(12 * 3600)
        let record = dayRecord(key: key, date: noon)
        let old = record.questMask
        let new = done.reduce(old) { $0 | $1.bit }
        guard new != old else { return [] }
        record.questMask = new
        record.syncedAt = nil
        save()
        return done.filter { old & $0.bit == 0 }
    }

    /// A week that reached 12 quests lights the next sky, once for the week. Returns the sky it lit.
    private func lightSkyIfEarned(week count: Int) -> SkyTheme? {
        guard count >= QuestEngine.weeklyGoal, settings.litWeeks < SkyTheme.unlockOrder.count,
              settings.lastLitWeek != questWeekKey else { return nil }
        settings.lastLitWeek = questWeekKey
        settings.litWeeks += 1
        return SkyTheme.unlockOrder[settings.litWeeks - 1]
    }

    /// Settles the quests: a day the app wasn't opened after is settled with its own picks, today gets its picks, and what
    /// today's answers have finished is written. Idempotent. Returns what changed (the summary shows it).
    @discardableResult
    func settleQuests() -> GameOutcome {
        var outcome = GameOutcome()
        if let stored = settings.questDay, stored.dayKey != todayKey { settleDay(key: stored.dayKey, picks: stored.kinds) }
        ensureQuestPicks()
        let picks = todayQuestKinds()
        outcome.weekBefore = questWeek()
        if !picks.isEmpty { outcome.questsDone = settleDay(key: todayKey, picks: picks) }
        outcome.weekAfter = questWeek()
        outcome.skyLit = lightSkyIfEarned(week: outcome.weekAfter)
        return outcome
    }

    /// The game loop after a finished session: quests ticked off, a sky maybe lit, badges earned.
    @discardableResult
    func settleGame() -> GameOutcome {
        var outcome = settleQuests()
        outcome.badges = settleBadges()
        return outcome
    }
}

// MARK: - Badges

extension AppModel {
    /// What the whole history amounts to for the badges. Worked out from the log (it never shrinks), once per revision.
    func achievementFacts() -> AchievementFacts {
        if let cached = gameCache.facts, cached.revision == revision { return cached.value }
        var facts = AchievementFacts()
        let quick = SessionKind.quickCheck.rawValue
        facts.sessionsFinished = count(FetchDescriptor<StudySession>(predicate: #Predicate {
            $0.endedAt != nil && $0.itemCount > 0 && $0.kindRaw != quick
        }))
        facts.answers = count(FetchDescriptor<ReviewLog>())
        facts.repairedDays = count(FetchDescriptor<DayRecord>(predicate: #Predicate { $0.repaired == true }))
        let fixed = ConfusionStatus.fixed.rawValue
        facts.mixUpsFixed = count(FetchDescriptor<Confusion>(predicate: #Predicate {
            $0.deletedAt == nil && $0.statusRaw == fixed
        }))
        facts.bestStreak = streak().best

        // Saves and own-words answers need each answer's kind and the recall it was given at.
        let scan = logScan(total: facts.answers)
        facts.saves = scan.saves
        facts.ownWordsAnswers = scan.ownWords

        for exam in examSnapshots() {
            guard let ready = exam.readinessAtExam else { continue }
            if ready >= AchievementFacts.readyAt { facts.readyExams += 1 }
            // Called it: what Capling projected from (the readiness with the coverage taken into account, as the projection was) was
            // within a few points of the grade.
            if let grade = exam.resultScore, let projected = exam.adjustedReadinessAtExam,
               abs(grade - projected) <= AchievementFacts.calledItWithin { facts.calledItExams += 1 }
        }
        gameCache.facts = (revision, facts)
        return facts
    }

    /// Saves and own-words answers across the whole log. The log only grows, so after a scan a new answer costs a look at the answers
    /// newer than the last one scanned. If those don't account for every new answer (another device's older answers came in with a
    /// sync, or two share an instant) or the log shrank, it is scanned again from the start.
    private func logScan(total: Int) -> GameCache.LogScan {
        let fsrs = self.fsrs
        func tally(_ logs: [ReviewLog], ownWords: Set<UUID>) -> (saves: Int, ownWords: Int, newest: Date) {
            let newState = CardState.new.rawValue
            let good = Rating.good.rawValue
            var saves = 0, words = 0
            var newest = Date.distantPast
            for log in logs {
                if ownWords.contains(log.itemID) { words += 1 }
                if log.ratingRaw >= good, log.wasCorrect, log.stateBeforeRaw != newState,
                   fsrs.retrievability(elapsedDays: log.elapsedDays, stability: log.stabilityBefore) < ReviewOutcome.fadingRecall {
                    saves += 1
                }
                newest = max(newest, log.reviewedAt)
            }
            return (saves, words, newest)
        }
        func ownWordIDs() -> Set<UUID> {
            Set(fetch(FetchDescriptor<StudyItem>()).filter { $0.kind.isOwnWords }.map(\.id))
        }

        if var scan = gameCache.scan, total >= scan.count {
            if total == scan.count { return scan }
            let newest = scan.newest
            let fresh = fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.reviewedAt > newest }))
            if scan.count + fresh.count == total {
                let found = tally(fresh, ownWords: ownWordIDs())
                scan.count = total
                scan.saves += found.saves
                scan.ownWords += found.ownWords
                scan.newest = max(scan.newest, found.newest)
                gameCache.scan = scan
                return scan
            }
        }
        let ownWords = ownWordIDs()
        var saves = 0, words = 0
        var newest = Date.distantPast
        var offset = 0
        let batch = 2000
        while true {
            var descriptor = FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewedAt)])
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batch
            let logs = fetch(descriptor)
            let found = tally(logs, ownWords: ownWords)
            saves += found.saves
            words += found.ownWords
            newest = max(newest, found.newest)
            if logs.count < batch { break }
            offset += batch
        }
        let scan = GameCache.LogScan(count: total, newest: newest, saves: saves, ownWords: words)
        gameCache.scan = scan
        return scan
    }

    /// The badges the person has been told about (`settings.badges`), joined with any the history has earned since.
    func earnedBadges() -> Set<Badge> {
        let known = Set((settings.badges ?? [:]).keys.compactMap(Badge.init(rawValue:)))
        return known.union(AchievementEngine.earned(achievementFacts()))
    }

    /// Every badge with how far along it is, in the catalog's order.
    func badgeStatuses() -> [BadgeStatus] {
        let facts = achievementFacts()
        let known = settings.badges ?? [:]
        return Badge.allCases.map { badge in
            BadgeStatus(badge: badge, progress: AchievementEngine.progress(badge, facts), earnedAt: known[badge.rawValue])
        }
    }

    /// The first launch that knows about badges notes the ones already earned, without a fuss. Called at launch, before
    /// any session, so what a session earns is new.
    func baselineBadges() {
        guard settings.badges == nil else { return }
        settings.badges = Dictionary(uniqueKeysWithValues: AchievementEngine.earned(achievementFacts()).map { ($0.rawValue, now) })
    }

    /// Notes the badges history has earned since the person was last told, and returns them (in the catalog's order).
    @discardableResult
    func settleBadges() -> [Badge] {
        guard var known = settings.badges else {
            baselineBadges()
            return []
        }
        let before = Set(known.keys.compactMap(Badge.init(rawValue:)))
        let new = AchievementEngine.newlyEarned(before: before, after: AchievementEngine.earned(achievementFacts()))
        guard !new.isEmpty else { return [] }
        for badge in new { known[badge.rawValue] = now }
        settings.badges = known
        return new
    }
}

// MARK: - Icons and skies

extension AppModel {
    private var unlocksEverything: Bool {
        #if DEBUG
        return debugUnlockAll
        #else
        return false
        #endif
    }

    /// The icons the best streak has unlocked.
    var unlockedIcons: [AppIconChoice] {
        unlocksEverything ? AppIconChoice.allCases : AppIconChoice.unlocked(best: streak().best)
    }

    /// Switches the app icon, when it is unlocked and the system allows it. The system shows its own alert.
    @discardableResult
    func setAppIcon(_ icon: AppIconChoice) async -> Bool {
        guard unlockedIcons.contains(icon), iconSwitcher.supportsAlternates else { return false }
        guard iconSwitcher.current != icon else {
            settings.appIcon = icon
            return true
        }
        do {
            try await iconSwitcher.apply(icon)
            settings.appIcon = icon
            return true
        } catch {
            AppConfig.log.error("app icon: \(error.localizedDescription, privacy: .public)")
            router.toast("Couldn't change the icon", systemImage: "exclamationmark.triangle.fill", tone: .neutral)
            return false
        }
    }

    /// The skies weeks of quests have lit, Night first.
    var unlockedSkies: [SkyTheme] {
        unlocksEverything ? SkyTheme.allCases : SkyTheme.unlocked(weeks: settings.litWeeks)
    }

    /// The sky to draw: the chosen one, or Night when the choice isn't unlocked.
    var skyTheme: SkyTheme {
        unlockedSkies.contains(settings.skyTheme) ? settings.skyTheme : .night
    }

    @discardableResult
    func setSkyTheme(_ theme: SkyTheme) -> Bool {
        guard unlockedSkies.contains(theme) else { return false }
        settings.skyTheme = theme
        return true
    }
}

// MARK: - Asking for a rating

extension AppModel {
    /// The marketing version, which the rating prompt is limited to once per.
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// What `ReviewPromptPolicy` needs to know about a session that just finished. `milestone` is the streak milestone it
    /// reached, if any.
    func reviewPromptFacts(for summary: SessionSummary, milestone: Int?) -> ReviewPromptPolicy.Facts {
        var facts = ReviewPromptPolicy.Facts()
        facts.answered = summary.itemsReviewed
        facts.rightFirstTime = summary.correctFirstTry
        facts.saves = summary.starsSaved
        facts.streakMilestone = milestone
        facts.examEve = summary.stopNow || summary.kind == .examEve
        facts.sessionsFinished = achievementFacts().sessionsFinished
        facts.daysSinceInstall = settings.installedAt.map { calendar.dayDistance(from: $0, to: now) } ?? 0
        facts.daysSincePrompt = settings.reviewPromptedAt.map { calendar.dayDistance(from: $0, to: now) }
        facts.promptedThisVersion = settings.reviewPromptedVersion == Self.marketingVersion
        // Never in the harness, and never in tests (they run without side effects).
        facts.harness = config.isHarness || !sideEffectsEnabled
        return facts
    }

    func noteReviewPrompted() {
        settings.reviewPromptedAt = now
        settings.reviewPromptedVersion = Self.marketingVersion
    }
}
