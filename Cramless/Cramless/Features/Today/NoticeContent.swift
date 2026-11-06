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
                             detail: MockCopy.cardLine(questions: offer.questions, minutes: offer.minutes),
                             action: .init(title: String(localized: "Take it"), systemImage: "doc.text", run: .takeMock(examID: offer.examID)),
                             link: .exam(offer.examID), cost: costLine(notice.cost))
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

    /// "No AI", "Under 1¢", "1 draft", "Free".
    static func costLine(_ cost: Notice.Cost) -> String {
        switch cost {
        case .none: String(localized: "No AI")
        case .cloud: String(localized: "Under 1¢")
        case .drafts(let n): String(localized: "\(n) drafts")
        case .free: String(localized: "Free")
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

    /// What's on the slot right after "Fix my week": "Plan updated" and what changed, with Undo.
    static func confirmation(boosts: [PlanBoost], now: Date, calendar: Calendar) -> CapNotice? {
        guard let first = boosts.first else { return nil }
        let dates = boosts.compactMap { calendar.dayNumber(forKey: $0.dayKey) }.map { calendar.startOfDay(dayNumber: $0) }
        let days = dayWords(dates, now: now, calendar: calendar)
        let what = first.origin ?? first.examTitle
        return CapNotice(id: "confirm-\(first.noticeID)", kind: .fading, title: String(localized: "Plan updated"),
                         detail: String(localized: "\(first.minutes) more minutes \(days) for \(what)."),
                         action: .init(title: String(localized: "Undo"), systemImage: "arrow.uturn.backward",
                                       run: .undoFixMyWeek(noticeID: first.noticeID)),
                         isConfirmation: true)
    }

    /// "today and tomorrow", "today and Friday", "on Friday and Tuesday".
    static func dayWords(_ dates: [Date], now: Date, calendar: Calendar) -> String {
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
        return startsNamed ? String(localized: "on \(list)") : list
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
        case .welcomeBack, .mockOffer:
            return nil
        }
    }

    // MARK: Settings

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
