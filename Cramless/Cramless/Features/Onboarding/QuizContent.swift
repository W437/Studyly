import Foundation

/// The four one-tap questions. Answers land in `AppSettings` as they're picked.
enum QuizQuestion: Int, CaseIterable, Sendable {
    case goal, examDate, minutes, notes

    var title: String {
        switch self {
        case .goal: "What's your goal this term?"
        case .examDate: "When's your next big exam?"
        case .minutes: "How much time can you give it a day?"
        case .notes: "Where do your notes live?"
        }
    }

    var subtitle: String {
        switch self {
        case .goal: "We'll shape your plan around it."
        case .examDate: "Capling plans backwards from that date."
        case .minutes: "Little and often beats cramming. You can change this anytime."
        case .notes: "Pick all that apply. Capling can use every one of them."
        }
    }

    /// Single-choice questions move on by themselves after a pick (the date waits for Continue).
    var isMultiSelect: Bool { self == .notes }
}

/// One answer on a question card.
struct QuizChoice<Value: Hashable>: Identifiable {
    var value: Value
    var symbol: String
    var title: String
    var detail: String?

    var id: Value { value }
}

enum QuizContent {
    static let goals: [QuizChoice<AppSettings.Goal>] = AppSettings.Goal.allCases.map { goal in
        switch goal {
        case .passClass: QuizChoice(value: goal, symbol: "checkmark.seal", title: goal.title,
                                    detail: "Get through the one that worries you")
        case .aceExams: QuizChoice(value: goal, symbol: "star", title: goal.title,
                                   detail: "Top marks on midterms and finals")
        case .keepUp: QuizChoice(value: goal, symbol: "calendar", title: goal.title,
                                 detail: "No more catching up the night before")
        case .learn: QuizChoice(value: goal, symbol: "brain.head.profile", title: goal.title,
                                detail: "Know it after the exam, too")
        }
    }

    static let minuteOptions = [5, 10, 15, 20, 30]

    static let minutes: [QuizChoice<Int>] = minuteOptions.map { m in
        let (symbol, word): (String, String) = switch m {
        case 5: ("cup.and.saucer", "Light")
        case 10: ("timer", "Steady")
        case 15: ("flame", "Serious")
        case 20: ("bolt", "Focused")
        default: ("figure.run", "All in")
        }
        return QuizChoice(value: m, symbol: symbol, title: "\(m) minutes", detail: word)
    }

    static let notes: [QuizChoice<AppSettings.NotesLocation>] = AppSettings.NotesLocation.allCases.map { place in
        switch place {
        case .paper: QuizChoice(value: place, symbol: "book", title: place.title,
                                detail: "Snap pages with the camera")
        case .slides: QuizChoice(value: place, symbol: "doc.richtext", title: place.title,
                                 detail: "From Files, Drive or email")
        case .lectures: QuizChoice(value: place, symbol: "mic", title: place.title,
                                   detail: "Record and transcribe on iPhone")
        case .flashcardApps: QuizChoice(value: place, symbol: "rectangle.stack", title: place.title,
                                        detail: "Import them in one tap")
        }
    }

    /// "Sat, Nov 14 · 23 days away" under the calendar.
    static func examSummary(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dayDistance(from: now, to: date)
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        switch days {
        case ..<1: return "\(day) · today"
        case 1: return "\(day) · tomorrow"
        default: return "\(day) · \(days) days away"
        }
    }

    /// The reminder moment after the minutes question: when, and why.
    static func reminderBody(minutes: Int, time: String) -> String {
        "One reminder a day at \(time), so your \(minutes) minutes don't slip. "
            + "Never during quiet hours, and you can change it anytime in Settings."
    }

    static func timeString(minutes: Int) -> String {
        var parts = DateComponents()
        parts.year = 2001
        parts.month = 1
        parts.day = 1
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        let date = Calendar(identifier: .gregorian).date(from: parts) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }
}

extension AppSettings {
    /// Adds or removes a notes location, keeping the list in the order the question shows it.
    mutating func toggleNotesLocation(_ place: NotesLocation) {
        var set = Set(notesLocations)
        if set.contains(place) { set.remove(place) } else { set.insert(place) }
        notesLocations = NotesLocation.allCases.filter(set.contains)
    }
}
