import Foundation

/// What Cap says on each of his cards, as plain values, so every word is tested without a view. Counts and minutes, never a percentage
/// (readiness is the only learning percentage), and "questions", not "cards".
enum NoticeContent {
    /// A card for Today. `firstName`, `now` and `calendar` are the person's and the clock's.
    static func card(_ notice: Notice, firstName: String, now: Date, calendar: Calendar) -> CapNotice {
        switch notice.evidence {
        case .mixUp(let note):
            var card = card(for: note)
            card.cost = costLine(notice.cost)
            return card
        case .lookAlike(let pair):
            return CapNotice(id: notice.id, kind: .lookAlike, title: lookAlikeTitle(pair.termA, pair.termB),
                             detail: lookAlikeDetail(pair, now: now, calendar: calendar),
                             action: .init(title: String(localized: "Show me"), systemImage: "rectangle.split.2x1",
                                           run: .showLookAlike(pair)),
                             link: nil, cost: costLine(notice.cost))
        case .fading(let rescue):
            return CapNotice(id: notice.id, kind: .fading, title: String(localized: "\(rescue.dimCount) questions will be dim by exam day"),
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
            return CapNotice(id: notice.id, kind: .gap, title: ExamGapCopy.title(count: gap.topics.count, examTitle: gap.examTitle),
                             detail: ExamGapCopy.detail(gap.topics.map(\.name)),
                             action: .init(title: String(localized: "Fill the gap"), systemImage: "text.badge.plus", run: .fillGap(examID: gap.examID)),
                             link: .exam(gap.examID), cost: costLine(notice.cost))
        case .lectureDate(let heard):
            return CapNotice(id: notice.id, kind: .lectureDate, title: String(localized: "Cap heard an exam date"),
                             detail: String(localized: "“\(heard.quote)” From \(heard.lectureTitle)."),
                             action: .init(title: String(localized: "See it"), systemImage: "waveform",
                                           run: .openHeardDate(sourceID: heard.sourceID, noticeID: notice.id)),
                             cost: costLine(notice.cost))
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
            return CapNotice(id: notice.id, kind: .teachBack, title: TeachCopy.noticeTitle(offer.topicName), detail: TeachCopy.noticeLine,
                             action: .init(title: TeachCopy.noticeAction, systemImage: "person.wave.2", run: .teach(topicID: offer.topicID)),
                             cost: costLine(notice.cost))
        }
    }

    /// An open mix-up as a card. One that was spotted before any mistake (an adopted look-alike) says so, until the first miss.
    static func card(for note: ConfusionNote) -> CapNotice {
        let parts = note.name.components(separatedBy: " vs ")
        let title = note.missCount == 0 && parts.count == 2 ? lookAlikeTitle(parts[0], parts[1]) : SessionCopy.mixUpLine(note.name)
        // The fix's length holds together on one line ("2-minute" never breaks at its hyphen).
        return CapNotice(id: NoticeEngine.mixUpID(note.id), kind: .mixUp, title: title,
                         detail: SessionCopy.missLine(note).replacingOccurrences(of: "2-minute", with: "2\u{2011}minute"),
                         action: .init(title: String(localized: "Fix it · 2 min"), systemImage: "wand.and.stars",
                                       run: .fixMixUp(confusionID: note.id)),
                         link: .confusion(note.id))
    }

    /// The session "welcome back" offers.
    static let welcomeBackMinutes = 5

    /// A best streak is worth naming from this many days (the first milestone).
    private static let namedStreak = 3

    static func welcomeBackDetail(best: Int) -> String {
        best >= namedStreak
            ? String(localized: "Your best streak, \(best) days, is still yours. 5 minutes today lights your flame again.")
            : String(localized: "Your stars waited for you. 5 minutes today is a good start.")
    }

    /// "No AI" or "Uses Cloud AI". Nothing when the card's own button costs nothing and what follows may or may not use AI: no cost word, and never a price.
    static func costLine(_ cost: Notice.Cost) -> String? {
        switch cost {
        case .none: String(localized: "No AI")
        case .cloud, .drafts: String(localized: "Uses Cloud AI")
        case .free: nil
        }
    }

    // MARK: Look-alikes

    /// "Metaphase and telophase look alike".
    static func lookAlikeTitle(_ a: String, _ b: String) -> String {
        let first = a.prefix(1).uppercased() + a.dropFirst()
        return String(localized: "\(first) and \(SessionCopy.lowerFirst(b)) look alike")
    }

    /// "Both are on Wednesday's Bio 101 Midterm. Learn the one difference now?" (its weekday only inside a week).
    static func lookAlikeDetail(_ pair: LookAlikePair, now: Date, calendar: Calendar) -> String {
        if pair.daysLeft <= 6 {
            let day = weekday(pair.examDate, calendar: calendar)
            return String(localized: "Both are on \(day)'s \(pair.examTitle). Learn the one difference now?")
        }
        return String(localized: "Both are on your \(pair.examTitle). Learn the one difference now?")
    }

    // MARK: Fading

    /// "From Lecture 3, for your Bio 101 Midterm. 6 more minutes today and tomorrow keeps them."
    static func fadingDetail(_ rescue: FadeRescue, now: Date, calendar: Calendar) -> String {
        let lead: String
        switch rescue.origin {
        case .source(let name): lead = String(localized: "From \(name), for your \(rescue.examTitle).")
        case .topic(let name): lead = String(localized: "Mostly \(name), for your \(rescue.examTitle).")
        case nil: lead = String(localized: "For your \(rescue.examTitle).")
        }
        let days = dayWords(rescue.days.map(\.date), now: now, calendar: calendar)
        let plan = rescue.kept >= rescue.dimCount
            ? String(localized: "\(rescue.minutesPerDay) more minutes \(days) keeps them.")
            : String(localized: "\(rescue.minutesPerDay) more minutes \(days) keeps \(rescue.kept) of them.")
        return "\(lead) \(plan)"
    }

    // MARK: Busy days

    /// "Monday looks busy", "Tomorrow looks busy".
    static func busyTitle(_ move: BusyMove, calendar: Calendar) -> String {
        move.busy.offset == 1 ? String(localized: "Tomorrow looks busy")
            : String(localized: "\(weekday(move.busy.date, calendar: calendar)) looks busy")
    }

    /// "About 6 hours in your calendar. Move 10 minutes to Sunday and Tuesday?"
    static func busyDetail(_ move: BusyMove, now: Date, calendar: Calendar) -> String {
        let days = dayWords(move.to.map(\.date), now: now, calendar: calendar, withOn: false)
        return "\(String(localized: "About \(move.hours) hours in your calendar.")) \(String(localized: "Move \(move.minutes) minutes to \(days)?"))"
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
                return String(localized: "Some \(name) questions are fading before your \(rescue.examTitle). A few extra minutes keeps them.")
            case nil:
                return String(localized: "Some questions are fading before your \(rescue.examTitle). A few extra minutes keeps them.")
            }
        case .lookAlike(let pair):
            let first = pair.termA.prefix(1).uppercased() + pair.termA.dropFirst()
            return String(localized: "\(first) and \(SessionCopy.lowerFirst(pair.termB)) look alike, and both are on your \(pair.examTitle). Cap can show you the difference.")
        case .mixUp(let note):
            if note.name == ConfusionCandidate.unnamed { return String(localized: "Still tripping on the same questions? A 2-minute fix is ready.") }
            return String(localized: "Still mixing up \(SessionCopy.mixUpPair(note.name))? A 2-minute fix is ready.")
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
        case .mixUp: "Mix-ups"
        case .lookAlike: "Look-alikes"
        case .fading: "Fading before an exam"
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
