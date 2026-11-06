import Foundation

/// What Today says and offers on each kind of day, as plain values, so every state is tested without a view: Cap and the sky in
/// the band (`TodaySkyHero`), and the day card under it (`TodayDayCard`): a chip naming the exam and when it is, a title, one reason,
/// the readiness rings (now and about N% after today), the day's one button and "Why these?".
///
/// | Day | Chip | Title | Button |
/// |---|---|---|---|
/// | Plan (a session for one exam) | "For Chem 110 Quiz" · "Sun · in 2 days" | up to two topics | "Study · 15 min" |
/// | Catch-up | the same | the same, the backlog as the reason | "Study · 15 min" |
/// | No exam (or none the session serves, `SessionFocus`) | none | its topics or courses | "Study · 15 min" |
/// | Exam eve | moon, the exam · "Tomorrow · 10:00" | "Tonight: weak spots only" | "Tonight · 4 min" (the session's own minutes) |
/// | Eve, nothing weak | the same | "Nothing left to review tonight" | none |
/// | Eve, done | the same | "That's enough for tonight" | "Your last look" (quiet), when it has ideas |
/// | Done | "Done for today" · "15 min · 24 answers" | "Bright tonight" | "5 more minutes" (quiet) |
/// | All lit | none | "All lit" | "Practice Limiting reagents · 5 min", or "Practice · 5 min" when that doesn't fit |
/// | No questions yet | none | "Let's make your first set" / "Add your first material" | "Try a sample page", "Scan a page" |
struct TodayHeroContent: Equatable, Sendable {
    /// How the band's sky is drawn.
    enum Sky: Equatable, Sendable {
        /// The person's own sky.
        case live
        /// Exam eve: the exam's region lit, everything else dimmed.
        case regionLit(UUID)
        /// Nothing studied yet: outline stars, unlit.
        case outline
    }

    struct Action: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case session(SessionKind, minutes: Int?, examID: UUID?)
            /// A short practice on one topic.
            case practice(topicID: UUID, courseID: UUID, minutes: Int)
            case sample
            case scan
            /// The last look on an exam's eve.
            case lastLook(examID: UUID)
        }

        var kind: Kind
        var title: LocalizedStringResource
        var systemImage: String
        /// The day's one big button (tangerine), or a quiet extra.
        var prominent: Bool
        /// What VoiceOver says for it, when the title alone is terse ("Study for 15 minutes").
        var spoken: LocalizedStringResource? = nil
        /// What the button says when `title` doesn't fit on one line ("Practice · 5 min").
        var shortTitle: LocalizedStringResource? = nil

        /// The session this action starts, if it starts one.
        var request: SessionRequest? {
            switch kind {
            case .session(let kind, let minutes, let examID):
                return SessionRequest(kind: kind, examID: examID, minutes: minutes)
            case .practice(let topicID, let courseID, let minutes):
                return SessionRequest(kind: .practice, courseID: courseID, minutes: minutes, topicID: topicID)
            case .sample, .scan, .lastLook:
                return nil
            }
        }
    }

    /// The chip at the top of the card: who the day is for.
    struct Chip: Equatable, Sendable {
        enum Tone: Equatable, Sendable { case exam, eve, done }
        var text: String
        var symbol: String
        var tone: Tone
    }

    /// Readiness now, and about where today's session takes it (a projection, drawn dashed).
    struct Rings: Equatable, Sendable {
        var now: Double
        /// Shown only when today moves it by a point or more.
        var after: Double?
        /// "Based on 7 questions so far." when the exam has few questions yet.
        var footnote: String?
    }

    /// The done card's exam: "Chem 110 Quiz: 52% ready" and "+10% today · 2 days to go".
    struct RingLine: Equatable, Sendable {
        var value: Double
        var title: String
        var detail: String
        /// The change today, for the arrow beside the detail.
        var change: Double = 0
    }

    var cap: CapMoment
    var sky: Sky
    /// The sky twinkles. Off once there is nothing more to do tonight.
    var twinkles = true
    var chip: Chip?
    /// When the chip's exam is ("Sun · in 2 days"), or on a done day what was done ("15 min · 24 answers").
    var when: String?
    var title: String
    var titleSymbol: String?
    var reason: String
    var rings: Rings?
    var ringLine: RingLine?
    /// Zero, one or two: the day's button, and a quiet extra.
    var actions: [Action] = []
    /// "Why these?" explains the session.
    var showsWhy = false

    // MARK: Making it

    /// The card for `snapshot`.
    static func make(_ snapshot: TodaySnapshot) -> TodayHeroContent {
        let summary = snapshot.summary
        switch snapshot.hero {
        case .empty:
            return TodayHeroContent(
                cap: .watchingTheSky, sky: .outline, title: String(localized: "Let's make your first set"),
                reason: String(localized: "Scan a page from class and Capling turns it into questions. Every one becomes a star."),
                actions: [.sample, .scan(prominent: false)])

        case .noMaterial:
            return TodayHeroContent(
                cap: .watchingTheSky, sky: .outline, title: String(localized: "Add your first material"),
                reason: String(localized: "Scan a page, add a PDF or record a lecture, and today's session builds itself."),
                actions: [.sample, .scan(prominent: false)])

        case .session, .catchUp:
            let catchUp = snapshot.hero == .catchUp
            let action = Action.study(catchUp ? .catchUp : .daily, minutes: summary.plannedMinutes)
            var reason: String
            if catchUp {
                reason = TodayCopy.catchUp(due: summary.dueTotal, goal: summary.minutesGoal, days: summary.catchUpDaysToClear)
            } else if let focus = snapshot.focus {
                reason = TodayCopy.reason(weak: focus.weakCount > 0, due: focus.dueCount, new: focus.newCount, forExam: true)
            } else {
                reason = TodayCopy.reason(weak: summary.weakSpots > 0, due: summary.reviews, new: summary.newItems, forExam: false)
            }
            if summary.minutesDone > 0, !catchUp {
                reason = "\(TodayCopy.partWay(done: summary.minutesDone, goal: summary.minutesGoal)) \(reason)"
            }
            guard let focus = snapshot.focus else {
                let title = snapshot.sessionTopics.isEmpty ? String(localized: "Today's questions") : TodayCopy.topics(snapshot.sessionTopics)
                return TodayHeroContent(cap: .watchingTheSky, sky: .live, title: title, reason: reason, actions: [action],
                                        showsWhy: true)
            }
            let exam = focus.exam
            let after = focus.forecast - exam.readiness >= 0.01 ? focus.forecast : nil
            let footnote = exam.itemsInScope < TodayCopy.fewQuestions ? TodayCopy.basedOn(exam.itemsInScope) : nil
            return TodayHeroContent(
                cap: .watchingTheSky, sky: .live,
                chip: Chip(text: String(localized: "For \(exam.title)"), symbol: "graduationcap.fill", tone: .exam), when: exam.when,
                title: focus.topics.isEmpty ? exam.title : TodayCopy.topics(focus.topics), reason: reason,
                rings: Rings(now: exam.readiness, after: after, footnote: footnote), actions: [action], showsWhy: true)

        case .examEve(let id):
            let exam = snapshot.exams.first { $0.id == id }
            let title = snapshot.eveTitle ?? exam?.title ?? String(localized: "Your exam")
            let several = snapshot.eveExams.count > 1
            let chip = Chip(text: title, symbol: "moon.stars.fill", tone: .eve)
            guard snapshot.eveHasWork else {
                return TodayHeroContent(
                    cap: .asleep, sky: .regionLit(id), twinkles: false, chip: chip, when: exam?.when,
                    title: String(localized: "Nothing left to review tonight"), reason: TodayCopy.eveRest(title: title, several: several, time: nil))
            }
            return TodayHeroContent(
                cap: .watchingTheSky, sky: .regionLit(id), chip: chip, when: exam?.when,
                title: String(localized: "Tonight: weak spots only"),
                reason: TodayCopy.eveReason(minutes: snapshot.eveMinutes, topics: snapshot.eveTopics),
                actions: [.tonight(examID: id, minutes: snapshot.eveMinutes)])

        case .examEveDone(let id):
            let exam = snapshot.exams.first { $0.id == id }
            let title = snapshot.eveTitle ?? exam?.title ?? String(localized: "Your exam")
            let several = snapshot.eveExams.count > 1
            let time = several ? nil : exam.map { $0.date.formatted(.dateTime.hour().minute()) }
            return TodayHeroContent(
                cap: .asleep, sky: .regionLit(id), twinkles: false,
                chip: Chip(text: title, symbol: "moon.stars.fill", tone: .eve), when: exam?.when,
                title: String(localized: "That's enough for tonight"), reason: TodayCopy.eveRest(title: title, several: several, time: time),
                actions: snapshot.lastLookIdeas > 0 ? [.lastLook(examID: id, ideas: snapshot.lastLookIdeas)] : [])

        case .done:
            let extra = summary.sessionReady
                ? Action.extra(.daily, minutes: 5, title: .fiveMoreMinutes)
                : Action.extra(.practice, minutes: 5, title: .fiveMoreMinutes)
            let line = snapshot.doneExam.map {
                RingLine(value: $0.readiness, title: TodayCopy.doneRing(title: $0.title, value: $0.readiness),
                         detail: TodayCopy.doneDelta($0.deltaToday, daysLeft: $0.daysLeft), change: $0.deltaToday)
            }
            return TodayHeroContent(
                cap: .pleased, sky: .live,
                chip: Chip(text: String(localized: "Done for today"), symbol: "checkmark", tone: .done),
                when: TodayCopy.doneLine(minutes: summary.minutesDone, answers: snapshot.answersToday),
                title: String(localized: "Bright tonight"), titleSymbol: "sparkles",
                reason: snapshot.quiet ? String(localized: "Back tomorrow.") : String(localized: "Back tomorrow. Your streak is safe."),
                ringLine: line, actions: [extra])

        case .caughtUp:
            let action: Action = snapshot.practice.map { .practice($0) } ?? .extra(.practice, minutes: 5, title: .practiceFiveMinutes, prominent: true)
            return TodayHeroContent(
                cap: .relaxed, sky: .live, title: String(localized: "All lit"), titleSymbol: "sparkles",
                reason: TodayCopy.allLit(topic: snapshot.practice?.name), actions: [action])
        }
    }
}

// MARK: - Pieces

private extension TodayHeroContent.Action {
    static let sample = TodayHeroContent.Action(kind: .sample, title: "Try a sample page", systemImage: "wand.and.sparkles",
                                                prominent: true)

    static func scan(prominent: Bool) -> TodayHeroContent.Action {
        TodayHeroContent.Action(kind: .scan, title: "Scan a page", systemImage: "camera", prominent: prominent)
    }

    /// The day's big button: a session that sizes itself, named by what it is ("Study · 15 min"), on plan and catch-up days alike.
    static func study(_ kind: SessionKind, minutes: Int) -> TodayHeroContent.Action {
        TodayHeroContent.Action(kind: .session(kind, minutes: nil, examID: nil), title: "Study · \(minutes) min",
                                systemImage: "sparkles", prominent: true, spoken: "Study for \(minutes) minutes")
    }

    /// A quiet extra of a fixed length (or, with nothing else to do, the day's button).
    static func extra(_ kind: SessionKind, minutes: Int, title: LocalizedStringResource, prominent: Bool = false) -> TodayHeroContent.Action {
        TodayHeroContent.Action(kind: .session(kind, minutes: minutes, examID: nil), title: title,
                                systemImage: prominent ? "sparkles" : "plus.circle", prominent: prominent)
    }

    /// "Practice Limiting reagents · 5 min": the topic remembered least.
    static func practice(_ topic: TodayPractice) -> TodayHeroContent.Action {
        TodayHeroContent.Action(kind: .practice(topicID: topic.topicID, courseID: topic.courseID, minutes: 5),
                                title: SkyCopy.practice(topic.name, minutes: 5), systemImage: "sparkles", prominent: true,
                                shortTitle: .practiceFiveMinutes)
    }

    /// The last look: a quiet button, on a night that has already had its one big one.
    static func lastLook(examID: UUID, ideas: Int) -> TodayHeroContent.Action {
        TodayHeroContent.Action(kind: .lastLook(examID: examID), title: "Your last look", systemImage: "moon.stars", prominent: false,
                                spoken: LastLookCopy.spoken(ideas: ideas))
    }

    /// Tonight's session, with its own minutes.
    static func tonight(examID: UUID, minutes: Int) -> TodayHeroContent.Action {
        TodayHeroContent.Action(kind: .session(.examEve, minutes: nil, examID: examID), title: "Tonight · \(minutes) min",
                                systemImage: "moon.stars.fill", prominent: true, spoken: "Tonight, \(minutes) minutes")
    }
}

private extension LocalizedStringResource {
    /// The extras are always five minutes: plain words, not counts to pluralise.
    static let fiveMoreMinutes: LocalizedStringResource = "5 more minutes"
    static let practiceFiveMinutes: LocalizedStringResource = "Practice · 5 min"
}
