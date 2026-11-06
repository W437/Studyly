import Foundation

/// Study out loud's words, in one place. Pure, so the tests read what a person reads.
enum OutLoudCopy {
    static let title: LocalizedStringResource = "Study out loud"
    static let pitch: LocalizedStringResource = "Cap asks, you answer out loud. For the bus, a walk or the gym."
    static let screenOff: LocalizedStringResource = "Works with the screen off"
    static let start: LocalizedStringResource = "Start"
    static let asking: LocalizedStringResource = "Cap is asking"
    static let yourTurn: LocalizedStringResource = "Your turn"
    static let checking: LocalizedStringResource = "Cap is checking"
    static let hint: LocalizedStringResource = "Say “repeat”, “skip” or “I don't know”."
    static let replyHint: LocalizedStringResource = "Say “got it” or “again”."
    static let nothingToAsk: LocalizedStringResource = "Nothing to ask out loud right now."
    /// What stays private, on the intro. Audio is never kept; the words go only as far as this says (`docs/privacy-wording.md`).
    static let privacy: LocalizedStringResource = "Your voice isn't recorded. Your iPhone turns it into words, and they're gone after the answer. An answer in your own words goes to Cloud AI to be graded, if you've turned it on."

    /// "12 questions · about 9 minutes".
    static func size(questions: Int, minutes: Int) -> String {
        [SessionCopy.questions(questions), String(localized: "about \(minutes) minutes")].joined(separator: " · ")
    }

    static func needsModel(_ language: String) -> LocalizedStringResource { "Out loud needs Apple's speech model for \(language)." }

    /// While the model downloads.
    static func downloading(_ fraction: Double?) -> LocalizedStringResource {
        guard let fraction else { return "Getting ready…" }
        return "Getting the speech model… \(Int((fraction * 100).rounded()))%"
    }

    /// What Cap says when no words came.
    static let takeYourTime = String(localized: "Take your time. Say your answer, or say skip.")
    static let waiting = String(localized: "I'll wait here. Press Repeat when you're ready.")
    static let didntCatch = String(localized: "I didn't catch that.")
    static let sayALetter = String(localized: "I didn't catch that. Say the letter, or the answer itself.")
    static let sayHowItWent = String(localized: "Say got it, or again.")
    static let cantHear = String(localized: "I can't hear you right now. Let's try again in a moment.")
}

/// Why a session can't start.
enum OutLoudBlock: Equatable, Sendable {
    case microphoneOff
    case microphoneBusy
    /// The language's speech model can't be had right now.
    case noModel(language: String)
    /// This iPhone has no speech models.
    case noSpeechHere

    init(_ error: Error) {
        switch error as? SpokenListenerFailure {
        case .microphoneDenied: self = .microphoneOff
        case .noSpeechModel(let language?): self = .noModel(language: language)
        case .noSpeechModel(nil): self = .noSpeechHere
        default: self = .microphoneBusy
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .microphoneOff: "Microphone access is off"
        case .microphoneBusy: "Couldn't start the microphone"
        case .noModel(let language): OutLoudCopy.needsModel(language)
        case .noSpeechHere: "This iPhone can't understand speech yet"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .microphoneOff: "Turn it on in Settings, and Cap can hear your answers."
        case .microphoneBusy: "Close other apps using it and try again."
        case .noModel: "It downloads once, then works offline. Try again when you're online."
        case .noSpeechHere: "You can still study the same questions on screen."
        }
    }

    var canRetry: Bool { self == .microphoneBusy || { if case .noModel = self { true } else { false } }() }
    var opensSettings: Bool { self == .microphoneOff }
}

/// Why a session is holding.
enum OutLoudPause: Equatable, Sendable {
    /// The person pressed Pause.
    case person
    /// A call or an alarm has the microphone.
    case interruption
    /// The microphone went away (a route change that didn't recover).
    case lostInput
    /// No answer came twice: Cap waits.
    case noAnswer

    var line: LocalizedStringResource {
        switch self {
        case .person: "Paused"
        case .interruption: "Paused for your call"
        case .lostInput: "The microphone went away"
        case .noAnswer: "Cap is waiting for you"
        }
    }
}
