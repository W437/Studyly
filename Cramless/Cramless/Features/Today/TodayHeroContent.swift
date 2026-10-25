import Foundation

/// What Today's sky hero says and offers on each kind of day, as plain values, so every state is tested without a
/// view. `TodaySkyHero` draws it: the sky and Cap on top, and below them a headline when there is one, the day's one
/// button (and sometimes a quiet second), and a caption.
///
/// | State | Button |
/// |---|---|
/// | Session | "Relight · 15 min" |
/// | Catch-up | "Catch up · 15 min" |
/// | Exam eve | "Tonight · 10 min", with the exam's region lit |
/// | Done | "Bright tonight", and "5 more minutes" if you want them |
/// | Caught up | "All lit", and a short practice |
/// | No questions yet | outline stars, unlit |
struct TodayHeroContent: Equatable, Sendable {
    /// How the sky behind the date and title is drawn.
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
            case sample
            case scan
        }

        var kind: Kind
        var title: LocalizedStringResource
        var systemImage: String
        /// The day's one big button (tangerine), or a quiet extra.
        var prominent: Bool

        /// The session this action starts, if it starts one.
        var request: SessionRequest? {
            guard case .session(let kind, let minutes, let examID) = self.kind else { return nil }
            return SessionRequest(kind: kind, examID: examID, minutes: minutes)
        }
    }

    var cap: CapMoment
    var sky: Sky
    /// The sky twinkles. Off once there is nothing more to do tonight.
    var twinkles = true
    var headline: LocalizedStringResource?
    var headlineSymbol: String?
    /// Zero, one or two: the day's button, and a quiet extra.
    var actions: [Action] = []
    var caption: LocalizedStringResource

    // MARK: Making it

    /// The hero for `snapshot`.
    static func make(_ snapshot: TodaySnapshot) -> TodayHeroContent {
        make(hero: snapshot.hero, summary: snapshot.summary, answersToday: snapshot.answersToday,
             exam: { id in snapshot.exams.first { $0.id == id } }, eveHasWork: snapshot.eveHasWork)
    }

    static func make(hero: TodayHero, summary: TodaySummary, answersToday: Int, exam: (UUID) -> TodayExam?,
                     eveHasWork: Bool) -> TodayHeroContent {
        switch hero {
        case .empty:
            return TodayHeroContent(
                cap: .watchingTheSky, sky: .outline, headline: "Let's make your first set", headlineSymbol: nil,
                actions: [.sample, .scan(prominent: false)],
                caption: "Scan a page from class and Capling turns it into questions. Every one becomes a star.")

        case .noMaterial:
            return TodayHeroContent(
                cap: .watchingTheSky, sky: .outline, headline: "Add your first material", headlineSymbol: nil,
                actions: [.sample, .scan(prominent: false)],
                caption: "Scan a page, add a PDF or record a lecture, and today's session builds itself.")

        case .session:
            return TodayHeroContent(
                cap: .watchingTheSky, sky: .live, actions: [.primary(.daily, shownMinutes: summary.plannedMinutes)],
                caption: .verbatim(sessionLine(summary)))

        case .catchUp:
            return TodayHeroContent(
                cap: .watchingTheSky, sky: .live, actions: [.primary(.catchUp, shownMinutes: summary.plannedMinutes)],
                caption: .verbatim(catchUpLine(summary)))

        case .examEve(let id):
            let title = exam(id)?.title ?? String(localized: "Your exam")
            guard eveHasWork else {
                return TodayHeroContent(
                    cap: .asleep, sky: .regionLit(id), twinkles: false, headline: "Nothing left to review tonight",
                    headlineSymbol: "moon.stars.fill",
                    caption: .verbatim(String(localized: "\(title) is tomorrow. Sleep is part of studying.")))
            }
            return TodayHeroContent(
                cap: .watchingTheSky, sky: .regionLit(id), actions: [.tonight(examID: id)],
                caption: .verbatim(String(localized: "\(title) is tomorrow. 10 minutes on your weak spots, then sleep. That's the whole plan tonight.")))

        case .examEveDone(let id):
            let found = exam(id)
            let title = found?.title ?? String(localized: "Your exam")
            let caption = found.map { String(localized: "\(title) is tomorrow at \($0.date.formatted(.dateTime.hour().minute())). Sleep is part of studying.") }
                ?? String(localized: "\(title) is tomorrow. Sleep is part of studying.")
            return TodayHeroContent(
                cap: .asleep, sky: .regionLit(id), twinkles: false, headline: "That's enough for tonight",
                headlineSymbol: "moon.stars.fill", caption: .verbatim(caption))

        case .done:
            let extra = summary.sessionReady
                ? Action.extra(.daily, minutes: 5, title: .fiveMoreMinutes)
                : Action.extra(.practice, minutes: 5, title: .fiveMoreMinutes)
            return TodayHeroContent(
                cap: .pleased, sky: .live, headline: "Bright tonight", headlineSymbol: "sparkles", actions: [extra],
                caption: .verbatim(doneLine(minutes: summary.minutesDone, answers: answersToday)))

        case .caughtUp:
            return TodayHeroContent(
                cap: .relaxed, sky: .live, headline: "All lit", headlineSymbol: "sparkles",
                actions: [.extra(.practice, minutes: 5, title: .practiceFiveMinutes)],
                caption: "Nothing due right now. A short practice keeps it fresh.")
        }
    }

    // MARK: Words

    /// "18 reviews · 6 new · 2 weak spots", or, part way through the day's goal, "6 of 15 minutes done · …".
    static func sessionLine(_ summary: TodaySummary) -> String {
        let mix = SessionCopy.sessionMix(reviews: summary.reviews, new: summary.newItems, weak: summary.weakSpots)
        guard summary.minutesDone > 0 else { return mix }
        return "\(String(localized: "\(summary.minutesDone) of \(summary.minutesGoal) minutes done")) · \(mix)"
    }

    /// Honest about the backlog, kind about the pace.
    static func catchUpLine(_ summary: TodaySummary) -> String {
        let days = max(1, summary.catchUpDaysToClear)
        let piled = String(localized: "\(summary.dueTotal) reviews piled up.")
        let pace = String(localized: "At \(summary.minutesGoal) minutes a day they're cleared in \(days) days, starting with what you're closest to forgetting.")
        return "\(piled) \(pace)"
    }

    /// "15 minutes, 24 answers. Back tomorrow. Your streak is safe."
    static func doneLine(minutes: Int, answers: Int) -> String {
        String(localized: "\(minutes) minutes, \(answers) answers. Back tomorrow. Your streak is safe.")
    }
}

// MARK: - Pieces

private extension TodayHeroContent.Action {
    static let sample = TodayHeroContent.Action(kind: .sample, title: "Try a sample page", systemImage: "wand.and.sparkles",
                                                prominent: true)

    static func scan(prominent: Bool) -> TodayHeroContent.Action {
        TodayHeroContent.Action(kind: .scan, title: "Scan a page", systemImage: "camera", prominent: prominent)
    }

    /// The day's big button: a session that sizes itself, named by what it will do ("Relight · 15 min").
    static func primary(_ kind: SessionKind, shownMinutes: Int) -> TodayHeroContent.Action {
        let title: LocalizedStringResource = kind == .catchUp ? .catchUp(shownMinutes) : .relight(shownMinutes)
        return TodayHeroContent.Action(kind: .session(kind, minutes: nil, examID: nil), title: title,
                                       systemImage: "sparkles", prominent: true)
    }

    /// A quiet extra of a fixed length.
    static func extra(_ kind: SessionKind, minutes: Int, title: LocalizedStringResource) -> TodayHeroContent.Action {
        TodayHeroContent.Action(kind: .session(kind, minutes: minutes, examID: nil), title: title,
                                systemImage: "plus.circle", prominent: false)
    }

    static func tonight(examID: UUID) -> TodayHeroContent.Action {
        TodayHeroContent.Action(kind: .session(.examEve, minutes: nil, examID: examID), title: .tonight,
                                systemImage: "moon.stars.fill", prominent: true)
    }
}

private extension LocalizedStringResource {
    static func relight(_ minutes: Int) -> LocalizedStringResource { "Relight · \(minutes) min" }
    static func catchUp(_ minutes: Int) -> LocalizedStringResource { "Catch up · \(minutes) min" }
    /// Tonight's session is always ten minutes, and the extras five: plain words, not counts to pluralise.
    static let tonight: LocalizedStringResource = "Tonight · 10 min"
    static let fiveMoreMinutes: LocalizedStringResource = "5 more minutes"
    static let practiceFiveMinutes: LocalizedStringResource = "Practice 5 minutes"
}
