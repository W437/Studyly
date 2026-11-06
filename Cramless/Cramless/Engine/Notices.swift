import Foundation

// Cap's cards: what he noticed, which of it he brings up today, and when he may send a notification. Pure: everything comes in as
// values (`NoticeInputs`), the clock included, and the only state is the ledger, which comes in and goes back out as a value
// (`AppModel+Notices` keeps it in UserDefaults; it stays on the phone).
//
// The rules:
// - one card on Today at a time ("1 of 2"), at most three dealt a day, one per kind;
// - the deck is dealt at the first look of the day; a card that turns up later joins while there is room; one whose reason has gone
//   leaves without a word;
// - "Later" hides a card until tomorrow; acting on one hides it for 7 days; a switched-off kind never shows;
// - nothing at all when any exam is tomorrow (Cap is quiet on an eve);
// - a notification only for a card that is `notifiable`, 2 to 6 days before its exam (`pings`, `NotificationPlanner`).
//
// Adding a kind:
// 1. give it a case in `NoticeKind` (never rename a raw value: settings and the ledger store them) and add it to `NoticeKind.live`,
//    which also puts its switch in Settings (`NoticeContent.switchTitle`);
// 2. add what it knows as a case of `Notice.Evidence`, and whatever it reads to `NoticeInputs`;
// 3. write one `private func <kind>Cards() -> [Notice]` with its id, rank and cost, and list it in `NoticeEngine.candidates()`
//    (the rank decides which card shows first: see `Rank`);
// 4. say it in `NoticeContent.card(_:)` (its title, its line and its `CapNotice.Action`, and `pingBody` if it is notifiable);
// 5. if its button does something new, add a case to `CapNotice.Action.Run` and run it in `AppModel.perform(_:)`.

/// What Cap can notice.
enum NoticeKind: String, Codable, CaseIterable, Sendable {
    /// An open mix-up (`Confusion`).
    case mixUp
    /// Two questions on the same exam that look alike, before the first mistake (`LookAlikeFinder`).
    case lookAlike
    /// Overdue questions that will be under the sky's dim line on exam day (`FadeFinder`).
    case fading
    /// Back after a week or more away.
    case welcomeBack
    /// A mock exam is due for an exam 2 to 7 days away (`MockSuggestion`).
    case mockOffer
    /// Topics of an exam within 28 days with no notes yet (`ExamGaps`).
    case gap
    /// An exam date heard in a lecture, not in the plan yet (`ExamDateFinder`).
    case lectureDate

    // Reserved for cards still to come, so the settings and the ledger can already name them.
    case busyDay, tooEasy, teachBack, sameIdea

    /// The kinds that deal cards in this build, in the order Settings lists their switches.
    static let live: [NoticeKind] = [.mixUp, .lookAlike, .fading, .welcomeBack, .mockOffer, .gap, .lectureDate]
        + [.tooEasy]
}

/// The person's switches: which kinds Cap may bring up, and whether he may send a notification about them.
struct NoticeSettings: Codable, Equatable, Sendable {
    var off: Set<NoticeKind> = []
    /// "Cap noticed" notifications, in the week before an exam.
    var notify = true

    init() {}

    func allows(_ kind: NoticeKind) -> Bool { !off.contains(kind) }

    // Strings, so a kind this version doesn't know is dropped and a new kind starts on.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        off = Set((try c.decodeIfPresent([String].self, forKey: .off) ?? []).compactMap(NoticeKind.init(rawValue:)))
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(off.map(\.rawValue).sorted(), forKey: .off)
        try c.encode(notify, forKey: .notify)
    }

    private enum CodingKeys: String, CodingKey { case off, notify }
}

// MARK: - The ledger

/// Minutes "Fix my week" added to one day, and the questions they are for. Stored in the ledger, so nothing is written to the
/// questions' memory and Undo takes it all back.
struct PlanBoost: Codable, Equatable, Sendable {
    var noticeID: String
    var examID: UUID
    var examTitle: String
    /// What the minutes are for: "Lecture 3", a topic, or nil.
    var origin: String?
    var dayKey: String
    var minutes: Int
    var itemIDs: [UUID]
}

/// What happened to Cap's cards: today's deck and what was done with it, and the boosts still ahead. It stays on this phone: a second
/// device deals its own deck and its plan strip doesn't show these boosts. What does cross devices is already synced: the mix-ups
/// and the questions' memory.
struct NoticeLedger: Codable, Equatable, Sendable {
    struct Dealt: Codable, Equatable, Sendable {
        var id: String
        var kind: NoticeKind
    }

    /// The day `dealt`, `snoozed`, `confirming` and `front` are about.
    var day = ""
    /// Today's deck, in the order it was dealt.
    var dealt: [Dealt] = []
    /// "Later": until tomorrow.
    var snoozed: Set<String> = []
    /// The day each card was acted on (card id → day key).
    var acted: [String: String] = [:]
    /// The days each card was on screen (card id → day keys).
    var seen: [String: [String]] = [:]
    /// When each card's notification goes or went out (`Notice.linkID` → date); a date still ahead can be planned again.
    var pinged: [String: Date] = [:]
    var boosts: [PlanBoost] = []
    /// The card "Fix my week" just acted on: the slot shows "Plan updated" with Undo until it is put away.
    var confirming: String?
    /// The card a notification opened: it shows first today.
    var front: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        dealt = try c.decodeIfPresent([Dealt].self, forKey: .dealt) ?? []
        snoozed = try c.decodeIfPresent(Set<String>.self, forKey: .snoozed) ?? []
        acted = try c.decodeIfPresent([String: String].self, forKey: .acted) ?? [:]
        seen = try c.decodeIfPresent([String: [String]].self, forKey: .seen) ?? [:]
        pinged = try c.decodeIfPresent([String: Date].self, forKey: .pinged) ?? [:]
        boosts = try c.decodeIfPresent([PlanBoost].self, forKey: .boosts) ?? []
        confirming = try c.decodeIfPresent(String.self, forKey: .confirming)
        front = try c.decodeIfPresent(String.self, forKey: .front)
    }

    /// How long a record is kept, in days.
    static let keptDays = 30

    /// A new day: the day's deck starts over, boosts on days gone by end (a card can come back for what they didn't reach), and old
    /// records go.
    func rolled(to key: String, now: Date, calendar: Calendar) -> NoticeLedger {
        guard key != day else { return self }
        var next = self
        next.day = key
        next.dealt = []
        next.snoozed = []
        next.confirming = nil
        next.front = nil
        let today = calendar.dayNumber(forKey: key) ?? 0
        func old(_ dayKey: String) -> Bool { (calendar.dayNumber(forKey: dayKey) ?? 0) < today - Self.keptDays }
        next.acted = acted.filter { !old($0.value) }
        next.seen = seen.compactMapValues { days in
            let kept = days.filter { !old($0) }
            return kept.isEmpty ? nil : kept
        }
        let cutoff = calendar.adding(days: -Self.keptDays, to: now)
        next.pinged = pinged.filter { $0.value >= cutoff }
        next.boosts = boosts.filter { (calendar.dayNumber(forKey: $0.dayKey) ?? 0) >= today }
        return next
    }

    func wasSeen(_ id: String, on key: String) -> Bool { seen[id]?.contains(key) == true }

    /// Today's boost in minutes (0 with none).
    func boostMinutes(on key: String) -> Int {
        boosts.filter { $0.dayKey == key }.reduce(0) { $0 + $1.minutes }
    }
}

// MARK: - What the engine reads

/// An open mix-up, as the mix-up card needs it.
struct NoticeMixUp: Equatable, Sendable {
    var note: ConfusionNote
    var itemIDs: [UUID]
    var courseID: UUID?
    var courseName: String = ""
}

/// Cap's note about an open confusion.
struct ConfusionNote: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var missCount: Int
    /// Wrong answers among the latest answers to its items, and how many answers that was.
    var recentMisses: Int
    var recentAnswers: Int
}

/// Everything Cap's cards are worked out from.
struct NoticeInputs: Sendable {
    var now: Date
    var calendar: Calendar
    var fsrs: FSRS
    var settings = NoticeSettings()
    var ledger = NoticeLedger()
    var easyDays: [Int] = []
    /// Active questions.
    var items: [ItemSnapshot] = []
    /// Upcoming exams.
    var exams: [ExamSnapshot] = []
    /// Exams already over: what tells a mix-up that's behind the student from one in a course that never had an exam.
    var finishedExams: [ExamSnapshot] = []
    /// Open mix-ups.
    var mixUps: [NoticeMixUp] = []
    /// Look-alike pairs, best first (`LookAlikeFinder`).
    var lookAlikes: [LookAlikePair] = []
    /// The day records, for "welcome back".
    var days: [DaySnapshot] = []
    var bestStreak = 0
    /// The questions in today's daily session as it stands.
    var todayItems: Set<UUID> = []
    /// Today's goal is met.
    var goalMet = false
    /// Where each overdue question came from.
    var sources: [UUID: FadeSource] = [:]
    var topicNames: [UUID: String] = [:]
    /// The look-alike lesson would use Cloud AI (which also decides what its card says it costs).
    var cloudLessons = false
    /// The exams a mock is due for.
    var mockOffers: [NoticeMockOffer] = []
    /// The exams with topics that have no notes.
    var gaps: [ExamGap] = []
    /// Exam dates heard in recent lectures that aren't in the plan.
    var heardDates: [NoticeHeardDate] = []
    /// Questions that have become too easy, the strongest first (`Ladder`).
    var tooEasy: [NoticeTooEasy] = []
}

/// An exam date heard in a lecture, for its card: the date, and the words the student can check it against.
struct NoticeHeardDate: Equatable, Sendable {
    var sourceID: UUID
    var lectureTitle: String
    var mentionID: String
    /// As the lecturer said it.
    var quote: String
    var date: Date
    var title: String
}

/// A question that has become too easy, and the harder way to ask its idea.
struct NoticeTooEasy: Equatable, Sendable {
    var itemID: UUID
    var next: ItemKind
    var topicName: String?
}

/// A mock that is due for an exam: which exam, and how long the mock would be.
struct NoticeMockOffer: Equatable, Sendable {
    var examID: UUID
    var examTitle: String
    var examDate: Date
    var questions: Int
    var minutes: Int
}

// MARK: - A card

/// One thing Cap noticed. `NoticeContent` turns it into words.
struct Notice: Identifiable, Equatable, Sendable {
    enum Evidence: Equatable, Sendable {
        case mixUp(ConfusionNote)
        case lookAlike(LookAlikePair)
        case fading(FadeRescue)
        /// `best`: the person's best streak, in days; 0 in Quiet mode, where the card doesn't name it.
        case welcomeBack(best: Int)
        case mockOffer(NoticeMockOffer)
        case gap(ExamGap)
        case lectureDate(NoticeHeardDate)
        case tooEasy(NoticeTooEasy)
    }

    /// What pressing its button costs, as the card says it.
    enum Cost: Equatable, Sendable {
        case none
        case cloud
        case drafts(Int)
        /// May use AI as it always does, and costs nothing (a mock marks short answers with what the person's plan allows).
        case free
    }

    /// Stable for what it is about: `mix-<confusion>`, `pair-<hash of the two questions>`, `fade-<exam>-<day>`, `back-<last day studied>`, `mock-<exam>`,
    /// `gap-<exam>`, `heard-<lecture>-<mention>`, `easy-<question>`.
    var id: String
    var kind: NoticeKind
    var rank: Double
    var examID: UUID?
    var examDate: Date?
    var examTitle: String?
    var evidence: Evidence
    var cost: Cost = .none
    /// May be sent as a notification (in the exam's week).
    var notifiable = false

    /// What a notification links to and what "once per card" is counted on: the id, without the day for a card whose id changes
    /// daily (a fading card tomorrow is the same card).
    var linkID: String {
        guard kind == .fading, let examID else { return id }
        return "fade-\(examID.uuidString)"
    }

    /// This card is the one a notification's link names.
    func matches(link: String) -> Bool { id == link || linkID == link }
}

/// The card on Today and its place: "2 of 3".
struct NoticeSlot: Equatable, Sendable {
    var notice: Notice
    var position: Int
    var count: Int
}

/// A notification Cap would send, on which day (0 today, 1 tomorrow).
struct NoticePing: Equatable, Sendable {
    var linkID: String
    var kind: NoticeKind
    var examDate: Date
    var dayOffset: Int
    var body: String
}

// MARK: - The engine

/// Which cards there are, which are dealt, and which may notify.
struct NoticeEngine: Sendable {
    static let dailyCap = 3
    /// A card acted on stays away this long.
    static let quietDays = 7
    /// How many days of one absence "welcome back" shows on.
    static let welcomeBackDays = 2
    static let welcomeBackAfterDays = 7
    static let welcomeBackMinStudyDays = 3
    /// A notification only this many days before the card's exam.
    static let pingWindow = 2...6
    /// A mix-up may notify when an exam that covers it is this close.
    static let mixUpPingDays = 7

    /// The order cards come in, highest first.
    enum Rank {
        static let welcomeBack = 1000.0
        static func fading(dimShare: Double, daysLeft: Int) -> Double { 500 + 200 * dimShare - 10 * Double(daysLeft) }
        static func mixUp(misses: Int) -> Double { 400 + 20 * Double(min(misses, 10)) }
        /// A mix-up only on finished exams, while another exam is to come: after all of it, as in the session (`ExamIndex.isDone(with:)`).
        /// Below the lowest a look-alike reaches, three weeks out.
        static func finishedMixUp(misses: Int) -> Double { 100 + Double(min(misses, 10)) }
        static func mockOffer(daysLeft: Int) -> Double { 450 - 10 * Double(daysLeft) }
        /// Nothing is at risk, so it waits behind what needs help: above only a mix-up on a finished exam.
        static let tooEasy = 150.0
        static func lookAlike(similarity: Double, linked: Bool, daysLeft: Int) -> Double {
            300 + 100 * similarity + (linked ? 50 : 0) - 10 * Double(daysLeft)
        }
        /// Topics that can't count toward readiness at all: more pressing the closer the exam.
        static func gap(daysLeft: Int) -> Double { 480 - 10 * Double(daysLeft) }
        /// An exam the plan doesn't know about matters more than anything inside the plan. Below "welcome back" and a bad fade.
        static let lectureDate = 650.0
    }

    var inputs: NoticeInputs

    init(_ inputs: NoticeInputs) { self.inputs = inputs }

    private var dayKey: String { inputs.calendar.dayKey(for: inputs.now) }

    /// What Cap has noticed right now, most important first (ties by id). Empty when an exam is tomorrow. Switched-off kinds are left
    /// out; what's been put off or acted on is the deck's business.
    func candidates() -> [Notice] {
        let calendar = inputs.calendar, now = inputs.now
        guard !inputs.exams.contains(where: { $0.date > now && calendar.dayDistance(from: now, to: $0.date) == 1 }) else { return [] }
        let cards = mixUpCards() + lookAlikeCards() + fadingCards() + welcomeBackCards() + mockOfferCards() + gapCards() + lectureDateCards()
            + tooEasyCards()
        return cards.filter { inputs.settings.allows($0.kind) }
            .sorted { $0.rank != $1.rank ? $0.rank > $1.rank : $0.id < $1.id }
    }

    /// The ledger with today's deck dealt: at most `dailyCap` cards, one per kind. What's dealt stays dealt (cards that turn up later
    /// join while there's room); a card a notification opened takes its kind's place, or the last place when the deck is full.
    func dealt(_ candidates: [Notice]) -> NoticeLedger {
        var next = inputs.ledger
        let waiting = candidates.filter { !isHidden($0.id) }
        if let front = next.front, let card = waiting.first(where: { $0.matches(link: front) }),
           !next.dealt.contains(where: { $0.id == card.id }) {
            let entry = NoticeLedger.Dealt(id: card.id, kind: card.kind)
            if let same = next.dealt.firstIndex(where: { $0.kind == card.kind }) {
                next.dealt[same] = entry
            } else if next.dealt.count >= Self.dailyCap {
                next.dealt[next.dealt.count - 1] = entry
            } else {
                next.dealt.append(entry)
            }
        }
        var kinds = Set(next.dealt.map(\.kind))
        for card in waiting where next.dealt.count < Self.dailyCap && !kinds.contains(card.kind) {
            next.dealt.append(NoticeLedger.Dealt(id: card.id, kind: card.kind))
            kinds.insert(card.kind)
        }
        return next
    }

    /// Today's cards still to show, the first one on screen: the dealt ones still true, not put off or acted on, in the order they were
    /// dealt, with the one a notification opened first.
    func deck(_ candidates: [Notice], ledger: NoticeLedger) -> [Notice] {
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var cards = ledger.dealt.compactMap { byID[$0.id] }.filter { !isHidden($0.id, in: ledger) }
        if let front = ledger.front, let at = cards.firstIndex(where: { $0.matches(link: front) }), at > 0 {
            cards.insert(cards.remove(at: at), at: 0)
        }
        return cards
    }

    /// The card on screen and its place among today's: the ones already dealt with count, so after "Later" on the first of three the
    /// next one says "2 of 3".
    func slot(_ deck: [Notice], ledger: NoticeLedger) -> NoticeSlot? {
        guard let first = deck.first else { return nil }
        let handled = ledger.dealt.filter { ledger.snoozed.contains($0.id) || ledger.acted[$0.id] == dayKey }.count
        return NoticeSlot(notice: first, position: handled + 1, count: handled + deck.count)
    }

    /// The notifications Cap may send, with the day each is for (0 today, 1 tomorrow): the best notifiable card for each, in its
    /// exam's window, never one already sent; today's never one the person has already put off, acted on or seen today; tomorrow's
    /// never one acted on or the one today's is about ("Later" makes a card tomorrow's candidate).
    func pings(_ candidates: [Notice]) -> [(notice: Notice, dayOffset: Int)] {
        guard inputs.settings.notify else { return [] }
        let calendar = inputs.calendar, now = inputs.now, ledger = inputs.ledger, today = dayKey
        func eligible(_ card: Notice, dayOffset: Int) -> Bool {
            guard card.notifiable, let examDate = card.examDate else { return false }
            let left = calendar.dayDistance(from: now, to: examDate) - dayOffset
            guard Self.pingWindow.contains(left) else { return false }
            if let sent = ledger.pinged[card.linkID], sent <= now { return false }
            return !isActedOn(card.id)
        }
        var out: [(notice: Notice, dayOffset: Int)] = []
        let first = candidates.first { card in
            eligible(card, dayOffset: 0) && !ledger.snoozed.contains(card.id) && !ledger.wasSeen(card.id, on: today)
        }
        if let first { out.append((first, 0)) }
        // Tomorrow: another card if there is one, else this one again, for when today's time has already gone by. The planner sends a card
        // once, on the first of these days it can.
        let later = candidates.filter { eligible($0, dayOffset: 1) }
        if let second = later.first(where: { $0.linkID != first?.linkID }) ?? later.first {
            out.append((second, 1))
        }
        return out
    }

    // MARK: Hidden

    private func isHidden(_ id: String, in ledger: NoticeLedger? = nil) -> Bool {
        let ledger = ledger ?? inputs.ledger
        return ledger.snoozed.contains(id) || isActedOn(id, in: ledger)
    }

    private func isActedOn(_ id: String, in ledger: NoticeLedger? = nil) -> Bool {
        guard let key = (ledger ?? inputs.ledger).acted[id], let day = inputs.calendar.dayNumber(forKey: key) else { return false }
        return inputs.calendar.dayNumber(for: inputs.now) - day < Self.quietDays
    }

    // MARK: Mix-ups

    /// Every open mix-up, the most missed first. It leaves when it is fixed.
    private func mixUpCards() -> [Notice] {
        guard !inputs.mixUps.isEmpty else { return [] }
        let index = ExamIndex(inputs.exams + inputs.finishedExams, after: inputs.now, calendar: inputs.calendar)
        var byID: [UUID: ItemSnapshot] = [:]
        let wanted = Set(inputs.mixUps.flatMap(\.itemIDs))
        for item in inputs.items where wanted.contains(item.id) { byID[item.id] = item }
        return inputs.mixUps.map { mixUp in
            let items = mixUp.itemIDs.compactMap { byID[$0] }
            let exam = items.compactMap { index.soonest(covering: $0) }.min { $0.date < $1.date }
            let daysLeft = exam.flatMap { index.daysLeft[$0.id] }
            let misses = mixUp.note.missCount
            let rank = Self.isBehindTheStudent(items, index: index) ? Rank.finishedMixUp(misses: misses) : Rank.mixUp(misses: misses)
            return Notice(id: Self.mixUpID(mixUp.note.id), kind: .mixUp, rank: rank,
                          examID: exam?.id, examDate: exam?.date, examTitle: exam?.title, evidence: .mixUp(mixUp.note),
                          notifiable: daysLeft.map { $0 <= Self.mixUpPingDays } ?? false)
        }
    }

    static func mixUpID(_ confusion: UUID) -> String { "mix-\(confusion.uuidString)" }

    /// These questions' exams are all over, and another exam is still to come.
    static func isBehindTheStudent(_ items: [ItemSnapshot], index: ExamIndex) -> Bool {
        !index.all.isEmpty && !items.isEmpty && items.allSatisfy { index.isDone(with: $0) }
    }

    // MARK: Look-alikes

    private func lookAlikeCards() -> [Notice] {
        inputs.lookAlikes.map { pair in
            Notice(id: pair.id, kind: .lookAlike,
                   rank: Rank.lookAlike(similarity: pair.similarity, linked: pair.linked, daysLeft: pair.daysLeft),
                   examID: pair.examID, examDate: pair.examDate, examTitle: pair.examTitle, evidence: .lookAlike(pair),
                   cost: inputs.cloudLessons ? .cloud : .none, notifiable: true)
        }
    }

    // MARK: Fading

    private func fadingCards() -> [Notice] {
        let boosted = Set(inputs.ledger.boosts.flatMap(\.itemIDs))
        let finder = FadeFinder(fsrs: inputs.fsrs, calendar: inputs.calendar, now: inputs.now, easyDays: inputs.easyDays,
                                goalMet: inputs.goalMet)
        return finder.rescues(items: inputs.items, exams: inputs.exams, todayItems: inputs.todayItems, boosted: boosted,
                              sources: inputs.sources, topicNames: inputs.topicNames, hidden: { isHidden($0) }).map { rescue in
            Notice(id: rescue.noticeID, kind: .fading, rank: Rank.fading(dimShare: rescue.dimShare, daysLeft: rescue.daysLeft),
                   examID: rescue.examID, examDate: rescue.examDate, examTitle: rescue.examTitle, evidence: .fading(rescue),
                   notifiable: true)
        }
    }

    // MARK: Welcome back

    /// A week or more without studying, by someone who has studied on at least three days: shown on at most two days of the
    /// absence, gone after a session today. Never sent as a notification.
    private func welcomeBackCards() -> [Notice] {
        let studied = inputs.days.filter(\.studied)
        guard studied.count >= Self.welcomeBackMinStudyDays, !inputs.items.isEmpty,
              let last = studied.max(by: { $0.day < $1.day }),
              inputs.calendar.dayDistance(from: last.day, to: inputs.now) >= Self.welcomeBackAfterDays else { return [] }
        let id = "back-\(last.dayKey)"
        let days = inputs.ledger.seen[id] ?? []
        guard days.count < Self.welcomeBackDays || days.contains(dayKey) else { return [] }
        return [Notice(id: id, kind: .welcomeBack, rank: Rank.welcomeBack, evidence: .welcomeBack(best: inputs.bestStreak))]
    }

    /// One card per kind means one exam's mock at a time: the nearest ranks first. Never sent as a notification, and never on the eve or
    /// the day (`MockSuggestion.days`).
    private func mockOfferCards() -> [Notice] {
        inputs.mockOffers.compactMap { offer in
            let days = inputs.calendar.dayDistance(from: inputs.now, to: offer.examDate)
            guard MockSuggestion.days.contains(days) else { return nil }
            return Notice(id: Self.mockOfferID(offer.examID), kind: .mockOffer, rank: Rank.mockOffer(daysLeft: days), examID: offer.examID,
                          examDate: offer.examDate, examTitle: offer.examTitle, evidence: .mockOffer(offer), cost: .free)
        }
    }

    static func mockOfferID(_ examID: UUID) -> String { "mock-\(examID.uuidString)" }

    // MARK: Gaps

    /// One card per kind means the nearest exam's gaps come up first. Sent as a notification in the exam's week.
    private func gapCards() -> [Notice] {
        inputs.gaps.filter { !$0.topics.isEmpty && ExamGaps.noticeDays.contains($0.daysLeft) }.map { gap in
            Notice(id: Self.gapID(gap.examID), kind: .gap, rank: Rank.gap(daysLeft: gap.daysLeft), examID: gap.examID, examDate: gap.examDate,
                   examTitle: gap.examTitle, evidence: .gap(gap), cost: .free, notifiable: true)
        }
    }

    static func gapID(_ examID: UUID) -> String { "gap-\(examID.uuidString)" }

    // MARK: Dates heard in a lecture

    /// A date that may be wrong isn't worth a notification, and it has no exam yet to be in the week of.
    private func lectureDateCards() -> [Notice] {
        inputs.heardDates.filter { $0.date > inputs.now }.map { heard in
            Notice(id: Self.heardID(sourceID: heard.sourceID, mentionID: heard.mentionID), kind: .lectureDate, rank: Rank.lectureDate,
                   evidence: .lectureDate(heard), cost: .free)
        }
    }

    static func heardID(sourceID: UUID, mentionID: String) -> String { "heard-\(sourceID.uuidString)-\(mentionID)" }

    // MARK: Questions that have become too easy

    /// One idea at a time, the strongest. Never a notification: there's no hurry in it. It writes a draft, which the card says it spends.
    private func tooEasyCards() -> [Notice] {
        inputs.tooEasy.prefix(1).map { offer in
            Notice(id: Self.tooEasyID(offer.itemID), kind: .tooEasy, rank: Rank.tooEasy, evidence: .tooEasy(offer), cost: .drafts(1))
        }
    }

    static func tooEasyID(_ itemID: UUID) -> String { "easy-\(itemID.uuidString)" }
}
