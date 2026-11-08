import Foundation

/// What Today says and offers on each kind of day, as plain values, so every state is tested without a view: Cap and the sky in
/// the band (`TodaySkyHero`), and the day card under it (`TodayDayCard`): a chip naming the exam and its day (a tap opens it) with
/// its readiness beside it, a title, at most one short line, the day's one button and "Why these?".
///
/// The line is there only where it says something the title and the button don't.
///
/// | Day | Chip · ring | Title | Line | Button |
/// |---|---|---|---|---|
/// | Plan (a session for one exam) | "Chem 110 Quiz · Tue" · "41% ready" | up to two topics; the courses, soonest first, when the exam has less than half the session | none ("6 of 15 minutes done." part way) | "Study · 15 min" |
/// | Catch-up | the same | the same | "Catching up: about 4 days at 15 minutes a day." | "Study · 15 min" |
/// | No exam the session serves | none ("Add exam" with no exam at all) | its topics or courses | none | "Study · 15 min" |
/// | Night before | moon, "Chem 110 Quiz · Tomorrow at 10:00" | "Tonight: weak spots only" | "Limiting reagents and Stoichiometry, then sleep." | "Tonight · 4 min" |
/// | Night before, nothing weak or done | the same | "Nothing left to review tonight" / "That's enough for today" | "Sleep is part of studying." | none, or "Your last look" (quiet) |
/// | Done | the exam today counted toward · its readiness | "Done for today" | "Back tomorrow. Your streak is safe." | "5 more minutes" (quiet) |
/// | All lit | none ("Add exam" with no exam at all) | "All lit" | "Nothing to review right now." | "Practice Limiting reagents · 5 min" |
/// | No questions yet | none | "Let's make your first set" / "Add your first material" | one short line | "Try a sample page", "Scan a page" |
struct TodayHeroContent: Equatable, Sendable {
    /// How the band's sky is drawn.
    enum Sky: Equatable, Sendable {
        /// The person's own sky.
        case live
        /// The night before an exam: the exam's region lit, everything else dimmed.
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
            /// The last look on the night before an exam.
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

    /// The chip at the top of the card: the exam the day is for and its day. A tap opens the exam (or, with no exam at all, adds one).
    struct Chip: Equatable, Sendable {
        enum Tone: Equatable, Sendable { case exam, eve, add }
        enum Link: Equatable, Sendable {
            case exam(UUID)
            case addExam
        }
        var text: String
        /// What VoiceOver says, when it differs from the text ("Chem 110 Quiz, Tuesday").
        var spoken: String? = nil
        var symbol: String
        var tone: Tone
        var link: Link?
    }

    var cap: CapMoment
    var sky: Sky
    /// The sky twinkles. Off once there is nothing more to do tonight.
    var twinkles = true
    var chip: Chip?
    /// The chip's exam's readiness, drawn as one ring beside the chip ("41% ready"). The only number on the card.
    var readiness: Double?
    var title: String
    var titleSymbol: String?
    /// At most one short line under the title, only where it says something the title and the button don't.
    var line: String?
    /// Zero, one or two: the day's button, and a quiet extra.
    var actions: [Action] = []
    /// "Why these?" explains the session.
    var showsWhy = false

    // MARK: Making it

    /// The card for `snapshot`.
    static func make(_ snapshot: TodaySnapshot) -> TodayHeroContent {
        let summary = snapshot.summary
        // With no exam at all, the chip's place offers one.
        let addExam = snapshot.exams.isEmpty ? Chip.addExam : nil
        switch snapshot.hero {
        case .empty:
            return TodayHeroContent(cap: .watchingTheSky, sky: .outline, title: String(localized: "Let's make your first set"),
                                    line: TodayCopy.firstSet, actions: [.sample, .scan(prominent: false)])

        case .noMaterial:
            return TodayHeroContent(cap: .watchingTheSky, sky: .outline, title: String(localized: "Add your first material"),
                                    line: TodayCopy.firstMaterial, actions: [.sample, .scan(prominent: false)])

        case .session, .catchUp:
            let catchUp = snapshot.hero == .catchUp
            let action = Action.study(catchUp ? .catchUp : .daily, minutes: summary.plannedMinutes)
            let line: String? = catchUp
                ? TodayCopy.catchUp(goal: summary.minutesGoal, days: summary.catchUpDaysToClear)
                : summary.minutesDone > 0 ? TodayCopy.partWay(done: summary.minutesDone, goal: summary.minutesGoal) : nil
            guard let focus = snapshot.focus else {
                let title = snapshot.sessionTopics.isEmpty ? String(localized: "Today's questions") : TodayCopy.topics(snapshot.sessionTopics)
                return TodayHeroContent(cap: .watchingTheSky, sky: .live, chip: addExam, title: title, line: line, actions: [action],
                                        showsWhy: true)
            }
            return TodayHeroContent(cap: .watchingTheSky, sky: .live, chip: .exam(focus.exam), readiness: focus.exam.readiness,
                                    title: title(focus, snapshot), line: line, actions: [action], showsWhy: true)

        case .examEve(let id):
            let chip = eveChip(id, snapshot)
            guard snapshot.eveHasWork else {
                return TodayHeroContent(cap: .asleep, sky: .regionLit(id), twinkles: false, chip: chip,
                                        title: String(localized: "Nothing left to review tonight"), line: TodayCopy.sleep)
            }
            return TodayHeroContent(cap: .watchingTheSky, sky: .regionLit(id), chip: chip, title: String(localized: "Tonight: weak spots only"),
                                    line: TodayCopy.eveLine(topics: snapshot.eveTopics),
                                    actions: [.tonight(examID: id, minutes: snapshot.eveMinutes)])

        case .examEveDone(let id):
            return TodayHeroContent(cap: .asleep, sky: .regionLit(id), twinkles: false, chip: eveChip(id, snapshot),
                                    title: String(localized: "That's enough for today"), line: TodayCopy.sleep,
                                    actions: snapshot.lastLookIdeas > 0 ? [.lastLook(examID: id, ideas: snapshot.lastLookIdeas)] : [])

        case .done:
            let extra = summary.sessionReady
                ? Action.extra(.daily, minutes: 5, title: .fiveMoreMinutes)
                : Action.extra(.practice, minutes: 5, title: .fiveMoreMinutes)
            return TodayHeroContent(cap: .pleased, sky: .live, chip: snapshot.doneExam.map(Chip.exam), readiness: snapshot.doneExam?.readiness,
                                    title: String(localized: "Done for today"), titleSymbol: "sparkles",
                                    line: TodayCopy.doneLine(quiet: snapshot.quiet), actions: [extra])

        case .caughtUp:
            let action: Action = snapshot.practice.map { .practice($0) } ?? .extra(.practice, minutes: 5, title: .practiceFiveMinutes, prominent: true)
            return TodayHeroContent(cap: .relaxed, sky: .live, chip: addExam, title: String(localized: "All lit"), titleSymbol: "sparkles",
                                    line: TodayCopy.allLit, actions: [action])
        }
    }

    /// The day's title: the session's topics for its exam, weakest first; or, when that exam has less than half of today's questions,
    /// the courses the session holds, soonest exam first ("Chem 110, Bio 101, and AP Psychology"). Only the words change: the session
    /// is the same.
    static func title(_ focus: TodayFocus, _ snapshot: TodaySnapshot) -> String {
        let total = snapshot.summary.plannedQuestions
        if total > 0, focus.questions * 2 < total, snapshot.sessionCourses.count > 1 {
            return TodayCopy.courses(snapshot.sessionCourses)
        }
        return focus.topics.isEmpty ? focus.exam.title : TodayCopy.topics(focus.topics)
    }

    /// The night before: the exam (or the exams sharing the evening) and tomorrow, with its time when there is one exam.
    private static func eveChip(_ id: UUID, _ snapshot: TodaySnapshot) -> Chip {
        let exam = snapshot.exams.first { $0.id == id }
        let title = snapshot.eveTitle ?? exam?.title ?? String(localized: "Your exam")
        let day = snapshot.eveExams.count > 1 ? String(localized: "Tomorrow") : exam?.day ?? String(localized: "Tomorrow")
        return Chip(text: TodayCopy.chip(title, day: day), symbol: "moon.stars.fill", tone: .eve, link: .exam(id))
    }
}

// MARK: - Pieces

extension TodayHeroContent.Chip {
    /// "Chem 110 Quiz · Tue", opening the exam.
    static func exam(_ exam: TodayExam) -> Self {
        Self(text: TodayCopy.chip(exam.title, day: exam.day), spoken: exam.daySpoken.map { "\(exam.title), \($0)" },
             symbol: "graduationcap.fill", tone: .exam, link: .exam(exam.id))
    }

    /// "Add exam", with no exam at all.
    static let addExam = Self(text: String(localized: "Add exam"), symbol: "plus", tone: .add, link: .addExam)
}

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
