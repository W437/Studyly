import Foundation

/// Teach Cap's words, in one place. Pure, so the tests read what a person reads. "Questions", never "cards", and no percentage: readiness is the only one.
enum TeachCopy {
    static let title: LocalizedStringResource = "Teach Cap"
    static let later: LocalizedStringResource = "Later"
    static let sayIt: LocalizedStringResource = "Say it"
    static let typeIt: LocalizedStringResource = "Type it"
    static let done: LocalizedStringResource = "Done"
    static let covered: LocalizedStringResource = "What you covered"
    static let typeHere: LocalizedStringResource = "Type it to Cap"
    static let listening: LocalizedStringResource = "Cap is listening"
    static let notes: LocalizedStringResource = "Cap's notes"
    static let notesEmpty: LocalizedStringResource = "Cap writes down each idea as he hears it."
    static let tickWhat: LocalizedStringResource = "Tick what you said."
    static let doubleChecking: LocalizedStringResource = "Double-checking…"
    static let oneMore: LocalizedStringResource = "One more question"
    static let answerOneMore: LocalizedStringResource = "Answer one more"
    static let addMissing: LocalizedStringResource = "Add the missing idea as a question"
    static let hadIt: LocalizedStringResource = "I had it"
    static let notYet: LocalizedStringResource = "Not yet"
    static let tooFew: LocalizedStringResource = "Cap needs a few more questions on this topic first."
    static let heardNothing: LocalizedStringResource = "Cap didn't hear anything. Try again, or type it."
    static let privacy: LocalizedStringResource = "Your voice isn't recorded, and nothing you say is kept. If Cloud AI is on, your words go to it to be checked."
    static let micOff: LocalizedStringResource = "Microphone access is off, so you can type it to Cap."
    static let micBusy: LocalizedStringResource = "Cap can't use the microphone right now, so you can type it to him."
    static let noSpeech: LocalizedStringResource = "This iPhone doesn't have the speech model, so you can type it to Cap."

    /// What Cap asks.
    static func ask(_ topic: String) -> LocalizedStringResource { "Explain \(SessionCopy.lowerFirst(topic)) to me like I missed the class." }

    /// The card on Today.
    static func noticeTitle(_ topic: String) -> String { String(localized: "You know \(SessionCopy.lowerFirst(topic)). Can you teach it?") }
    static let noticeLine = String(localized: "Explaining it in your own words shows what's really stuck.")
    static let noticeAction = String(localized: "Teach Cap")

    /// "4 of 6 ideas".
    static func ideasCount(_ covered: Int, of total: Int) -> LocalizedStringResource { "\(covered) of \(total) ideas" }

    static let added: LocalizedStringResource = "Question added"

    /// What Cap asks about a term: "Explain S phase in your own words."
    static func explainTerm(_ term: String) -> String { String(localized: "Explain \(SessionCopy.lowerFirst(term)) in your own words.") }

    /// The question a missing idea becomes.
    static func questionFor(idea: String) -> String { String(localized: "Explain in your own words: \(idea).") }

    /// What Cap says at the end of the check.
    static func checkLine(covered: Int, total: Int) -> LocalizedStringResource {
        if covered == total { return "You covered all of it. Cap gets it now." }
        if covered == 0 { return "Cap's still lost, and that's useful: now you know where to look." }
        return "Good start. Here's what Cap still needs."
    }

    static func reason(_ failure: Error) -> LocalizedStringResource {
        switch failure as? SpokenListenerFailure {
        case .microphoneDenied: micOff
        case .noSpeechModel: noSpeech
        default: micBusy
        }
    }
}
