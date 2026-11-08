import Foundation

/// What Cap says on each of his cards, as plain values, so every word is tested without a view. Counts and minutes, never a percentage
/// (readiness is the only learning percentage), and "questions", not "cards". A pair of terms is named as a pair ("Metaphase vs
/// telophase"), what is due is "to review", and no line asks a question its button already answers.
enum NoticeContent {
    /// A card for Today. `firstName`, `now` and `calendar` are the person's and the clock's.
    static func card(_ notice: Notice, firstName: String, now: Date, calendar: Calendar) -> CapNotice {
        switch notice.evidence {
        case .mixUp(let note):
            var card = card(for: note)
            card.cost = costLine(notice.cost)
            return card
        case .lookAlike(let pair):
            return CapNotice(id: notice.id, kind: .lookAlike, title: pairTitle(pair.termA, pair.termB),
                             detail: lookAlikeDetail(pair, now: now, calendar: calendar),
                             action: .init(title: String(localized: "See the difference"), systemImage: "rectangle.split.2x1",
                                           run: .showLookAlike(pair)),
                             link: nil, cost: costLine(notice.cost))
        case .fading(let rescue):
            return CapNotice(id: notice.id, kind: .fading, title: String(localized: "\(rescue.dimCount) more to review before exam day"),
                             detail: fadingDetail(rescue, now: now, calendar: calendar),
                             action: .init(title: String(localized: "Fix my week"), systemImage: "calendar.badge.plus", run: .fixMyWeek(rescue)),
                             link: .exam(rescue.examID), cost: costLine(notice.cost))
        case .welcomeBack(let best):
            let name = firstName.trimmingCharacters(in: .whitespaces)
            return CapNotice(id: notice.id, kind: .welcomeBack,
                             title: name.isEmpty ? String(localized: "Welcome back") : String(localized: "Welcome back, \(name)"),
                             detail: welcomeBackDetail(best: best),
                             action: .init(title: String(localized: "Start 5 min"), systemImage: "play",
                                           run: .session(kind: .daily, minutes: welcomeBackMinutes, courseID: nil, topicID: nil, examID: nil)),
                             link: nil, cost: costLine(notice.cost))
        case .mockOffer(let offer):
            return CapNotice(id: notice.id, kind: .mockOffer, title: String(localized: "A mock exam for your \(offer.examTitle)"),
                             detail: MockCopy.cardLine(questions: offer.questions, minutes: offer.minutes, realQuestions: offer.realQuestions),
                             action: .init(title: String(localized: "Take it"), systemImage: "doc.text", run: .takeMock(examID: offer.examID)),
                             link: .exam(offer.examID), cost: costLine(notice.cost))
        case .gap(let gap):
            // The topics, and no question: "Fill the gap" says what Cap offers.
            return CapNotice(id: notice.id, kind: .gap, title: ExamGapCopy.title(count: gap.topics.count, examTitle: gap.examTitle),
                             detail: "\(ExamGapCopy.list(gap.topics.map(\.name))).",
                             action: .init(title: String(localized: "Fill the gap"), systemImage: "text.badge.plus", run: .fillGap(examID: gap.examID)),
                             link: .exam(gap.examID), cost: costLine(notice.cost))
        case .lectureDate(let heard):
            return CapNotice(id: notice.id, kind: .lectureDate, title: String(localized: "Cap heard an exam date"),
                             detail: String(localized: "“\(heard.quote)” From \(heard.lectureTitle)."),
                             action: .init(title: String(localized: "See it"), systemImage: "waveform",
                                           run: .openHeardDate(sourceID: heard.sourceID, noticeID: notice.id)),
                             cost: costLine(notice.cost), decline: .heardDate(sourceID: heard.sourceID, mentionID: heard.mentionID))
        case .tooEasy(let offer):
            return CapNotice(id: notice.id, kind: .tooEasy, title: LadderCopy.noticeTitle(topic: offer.topicName),
                             detail: LadderCopy.noticeLine(next: offer.next),
                             action: .init(title: LadderCopy.noticeAction, systemImage: "arrow.up.right", run: .raiseQuestion(itemID: offer.itemID)),
                             cost: costLine(notice.cost))
        case .busyAsk:
            return CapNotice(id: notice.id, kind: .busyDay, title: String(localized: "Cap can plan around your long days"),
                             detail: String(localized: "He'd look at your calendar for long busy stretches, only their times, on this iPhone. Nothing leaves it."),
                             action: .init(title: String(localized: "Check my calendar"), systemImage: "calendar", run: .askCalendar),
                             cost: costLine(notice.cost))
        case .busyDay(let move):
            return CapNotice(id: notice.id, kind: .busyDay, title: busyTitle(move, calendar: calendar), detail: busyDetail(move, now: now, calendar: calendar),
                             action: .init(title: String(localized: "Move them"), systemImage: "calendar.badge.clock", run: .moveBusyDay(move)),
                             cost: costLine(notice.cost))
        case .teachBack(let offer):
            return CapNotice(id: notice.id, kind: .teachBack, title: teachTitle(offer.topicName), detail: TeachCopy.noticeLine,
                             action: .init(title: TeachCopy.noticeAction, systemImage: "person.wave.2", run: .teach(topicID: offer.topicID)),
                             cost: costLine(notice.cost))
        }
    }

    /// An open mix-up as a card, named by its pair ("Anaphase vs telophase"; a topic-shaped one, or one the rules couldn't name, by its
    /// own line). The line says how it has gone, with no question over "Fix it".
    static func card(for note: ConfusionNote) -> CapNotice {
        let parts = note.name.components(separatedBy: " vs ")
        // The pair as it was named, which knows a name's capitals.
        let title = parts.count == 2 ? note.name.prefix(1).uppercased() + note.name.dropFirst()
            : note.rightRun >= 1 ? SessionCopy.mixUpComingAlong(note.name, questions: note.questions) : SessionCopy.mixUpLine(note.name, questions: note.questions)
        return CapNotice(id: NoticeEngine.mixUpID(note.id), kind: .mixUp, title: title, detail: missLine(note),
                         action: .init(title: fixTitle(questions: note.questions), systemImage: "wand.and.stars",
                                       run: .fixMixUp(confusionID: note.id)),
                         link: .confusion(note.id))
    }

    /// How a mix-up has gone: "Missed 3 of the last 4 times.", "You got the last one right.", "Spotted before any mix-up."
    static func missLine(_ note: ConfusionNote) -> String {
        if note.rightRun >= 1, note.missCount > 0 { return String(localized: "You got the last one right.") }
        if note.recentAnswers >= 3, note.recentMisses >= 2 {
            return String(localized: "Missed \(note.recentMisses) of the last \(note.recentAnswers) times.")
        }
        if note.missCount > 1 { return String(localized: "Missed \(note.missCount) times lately.") }
        // An adopted look-alike: nothing has been missed yet.
        if note.missCount == 0 { return String(localized: "Spotted before any mix-up.") }
        return String(localized: "Missed it lately.")
    }

    /// The fix's button, with how long it takes: "Fix it · 2 min" (one question: "Fix it · 1 min").
    static func fixTitle(questions: Int) -> String {
        questions == 1 ? String(localized: "Fix it · 1 min") : String(localized: "Fix it · 2 min")
    }

    /// Two look-alike terms, named as a pair: "Metaphase vs telophase" ("DNA vs mRNA" keeps its capitals).
    static func pairTitle(_ a: String, _ b: String) -> String {
        "\(a.prefix(1).uppercased() + a.dropFirst()) vs \(SessionCopy.lowerFirst(b))"
    }

    /// Teach Cap's card: "You know cell cycle well", over "Teach Cap".
    static func teachTitle(_ topic: String) -> String { String(localized: "You know \(SessionCopy.lowerFirst(topic)) well") }

    /// The session "welcome back" offers.
    static let welcomeBackMinutes = 5

    /// A best streak is worth naming from this many days (the first milestone).
    private static let namedStreak = 3

    /// The button says the 5 minutes; the line says what is still true.
    static func welcomeBackDetail(best: Int) -> String {
        best >= namedStreak ? String(localized: "Your best streak, \(best) days, is still yours.") : String(localized: "Your stars waited for you.")
    }

    /// "Uses Cloud AI" when the button does. Nothing otherwise: no cost word, and never a price.
    static func costLine(_ cost: Notice.Cost) -> String? {
        switch cost {
        case .cloud, .drafts: String(localized: "Uses Cloud AI")
        case .none, .free: nil
        }
    }

    // MARK: Look-alikes

    /// "They look alike, and both are on Wednesday's Bio 101 Midterm." (its weekday only inside a week).
    static func lookAlikeDetail(_ pair: LookAlikePair, now: Date, calendar: Calendar) -> String {
        if pair.daysLeft <= 6 {
            let day = weekday(pair.examDate, calendar: calendar)
            return String(localized: "They look alike, and both are on \(day)'s \(pair.examTitle).")
        }
        return String(localized: "They look alike, and both are on your \(pair.examTitle).")
    }

    // MARK: Fading

    /// "From Lecture 3, for your Bio 101 Midterm. 6 more minutes today and tomorrow covers them."
    static func fadingDetail(_ rescue: FadeRescue, now: Date, calendar: Calendar) -> String {
        let lead: String
        switch rescue.origin {
        case .source(let name): lead = String(localized: "From \(name), for your \(rescue.examTitle).")
        case .topic(let name): lead = String(localized: "Mostly \(name), for your \(rescue.examTitle).")
        case nil: lead = String(localized: "For your \(rescue.examTitle).")
        }
        let days = dayWords(rescue.days.map(\.date), now: now, calendar: calendar)
        let plan = rescue.kept >= rescue.dimCount
            ? String(localized: "\(rescue.minutesPerDay) more minutes \(days) covers them.")
            : String(localized: "\(rescue.minutesPerDay) more minutes \(days) covers \(rescue.kept) of them.")
        return "\(lead) \(plan)"
    }

    // MARK: Busy days

    /// "Monday looks busy", "Tomorrow looks busy".
    static func busyTitle(_ move: BusyMove, calendar: Calendar) -> String {
        move.busy.offset == 1 ? String(localized: "Tomorrow looks busy")
            : String(localized: "\(weekday(move.busy.date, calendar: calendar)) looks busy")
    }

    /// "About 6 hours in your calendar. Cap can move 10 minutes to Sunday and Tuesday."
    static func busyDetail(_ move: BusyMove, now: Date, calendar: Calendar) -> String {
        let days = dayWords(move.to.map(\.date), now: now, calendar: calendar, withOn: false)
        return "\(String(localized: "About \(move.hours) hours in your calendar.")) \(String(localized: "Cap can move \(move.minutes) minutes to \(days)."))"
    }

    /// What's on the slot right after "Fix my week" or a busy day's move: "Plan updated" and what changed, with Undo.
    static func confirmation(boosts: [PlanBoost], now: Date, calendar: Calendar) -> CapNotice? {
        guard let first = boosts.first else { return nil }
        if let off = boosts.first(where: { $0.minutes < 0 }) {
            let today = calendar.dayNumber(for: now)
            func date(_ boost: PlanBoost) -> Date? { calendar.dayNumber(forKey: boost.dayKey).map { calendar.startOfDay(dayNumber: $0) } }
            let from = date(off).map { day -> String in
                calendar.dayNumber(for: day) == today + 1 ? String(localized: "tomorrow") : weekday(day, calendar: calendar)
            } ?? ""
            let to = dayWords(boosts.filter { $0.minutes > 0 }.compactMap(date), now: now, calendar: calendar, withOn: false)
            return CapNotice(id: "confirm-\(first.noticeID)", kind: .busyDay, title: String(localized: "Plan updated"),
                             detail: String(localized: "\(-off.minutes) minutes moved from \(from) to \(to)."),
                             action: .init(title: String(localized: "Undo"), systemImage: "arrow.uturn.backward",
                                           run: .undoFixMyWeek(noticeID: first.noticeID)),
                             isConfirmation: true)
        }
        let dates = boosts.compactMap { calendar.dayNumber(forKey: $0.dayKey) }.map { calendar.startOfDay(dayNumber: $0) }
        let days = dayWords(dates, now: now, calendar: calendar)
        let what = first.origin ?? first.examTitle
        return CapNotice(id: "confirm-\(first.noticeID)", kind: .fading, title: String(localized: "Plan updated"),
                         detail: String(localized: "\(first.minutes) more minutes \(days) for \(what)."),
                         action: .init(title: String(localized: "Undo"), systemImage: "arrow.uturn.backward",
                                       run: .undoFixMyWeek(noticeID: first.noticeID)),
                         isConfirmation: true)
    }

    /// "today and tomorrow", "today and Friday", "on Friday and Tuesday" (`withOn: false`: "Friday and Tuesday").
    static func dayWords(_ dates: [Date], now: Date, calendar: Calendar, withOn: Bool = true) -> String {
        let today = calendar.dayNumber(for: now)
        var startsNamed = false
        let words: [String] = dates.enumerated().map { index, date in
            switch calendar.dayNumber(for: date) - today {
            case 0: return String(localized: "today")
            case 1: return String(localized: "tomorrow")
            default:
                if index == 0 { startsNamed = true }
                return weekday(date, calendar: calendar)
            }
        }
        let list = words.formatted(.list(type: .and))
        return startsNamed && withOn ? String(localized: "on \(list)") : list
    }

    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    // MARK: Notifications

    /// A notification's words: no counts, which would be stale by the time it arrives. Nil for a card that is never sent.
    static func pingBody(_ notice: Notice) -> String? {
        switch notice.evidence {
        case .fading(let rescue):
            switch rescue.origin {
            case .source(let name), .topic(let name):
                return String(localized: "Some \(name) questions need a review before your \(rescue.examTitle). A few extra minutes covers them.")
            case nil:
                return String(localized: "Some questions need a review before your \(rescue.examTitle). A few extra minutes covers them.")
            }
        case .lookAlike(let pair):
            return String(localized: "\(pairTitle(pair.termA, pair.termB)): they look alike, and both are on your \(pair.examTitle). Cap can show you the difference.")
        case .mixUp(let note):
            let ready = note.questions == 1 ? String(localized: "Fix it in a minute.") : String(localized: "Fix it in 2 minutes.")
            if note.name == ConfusionCandidate.unnamed {
                let same = note.questions == 1 ? String(localized: "Still tripping on the same question?") : String(localized: "Still tripping on the same questions?")
                return "\(same) \(ready)"
            }
            // The name as it stands: lower-casing it loses a name's capital, and a topic isn't something you mix up.
            guard note.name.contains(" vs ") else { return "\(String(localized: "\(note.name): still tripping you up.")) \(ready)" }
            return "\(String(localized: "\(note.name): still mixing them up?")) \(ready)"
        case .gap(let gap):
            return String(localized: "Some topics on your \(gap.examTitle) have no notes yet. Cap can help you fill them in.")
        case .welcomeBack, .mockOffer, .lectureDate, .tooEasy, .teachBack, .busyAsk, .busyDay:
            return nil
        }
    }

    // MARK: Settings

    /// What a switch needs said under it.
    static func switchNote(_ kind: NoticeKind) -> LocalizedStringResource? {
        kind == .busyDay ? "Looks at when your calendar is busy, on this iPhone, never at what's in it." : nil
    }

    /// A kind's switch in Settings ▸ Study.
    static func switchTitle(_ kind: NoticeKind) -> LocalizedStringResource {
        switch kind {
        case .mixUp: "Often confused"
        case .lookAlike: "Pairs that look alike"
        case .fading: "To review before an exam"
        case .welcomeBack: "Welcome back"
        case .gap: "Gaps in your notes"
        case .lectureDate: "Dates heard in a lecture"
        case .busyDay: "Busy days"
        case .tooEasy: "Questions that got too easy"
        case .teachBack: "Teach Cap"
        case .sameIdea: "The same idea in two courses"
        case .mockOffer: "Mock exams"
        }
    }
}
