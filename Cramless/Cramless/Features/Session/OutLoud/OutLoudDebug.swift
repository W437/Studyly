#if DEBUG
import Foundation

/// The harness's Study out loud, with no microphone and no sound.
///
/// `CRAMLESS_ROUTE=outLoud` opens the intro. `CRAMLESS_OUTLOUD=asking|listening|verdict|summary|blocked|nomodel` starts at once and holds there:
/// Cap reading the first question, the microphone open with words coming, the verdict on the first answer, the summary after every question;
/// `blocked` is the microphone off, `nomodel` no speech model. `CRAMLESS_OUTLOUD_SCRIPT=rpwk` answers question by question (`r` right,
/// `p` partly, `w` wrong, `k` "I don't know", `s` "skip", `e` "repeat", `x` "stop"; after the last letter, `r`), through the same
/// reading and grading as a real voice.
enum OutLoudDebug {
    @MainActor static var hold: String? { TestHarness.value("CRAMLESS_OUTLOUD") }
    @MainActor static var script: String? { TestHarness.value("CRAMLESS_OUTLOUD_SCRIPT") }

    /// Starts by itself: a state to hold, or a script to play.
    @MainActor static var startsAtOnce: Bool { hold != nil || script != nil }

    @MainActor static func ports() -> OutLoudPorts {
        let hold = hold
        let letters = Array(script ?? (hold == "summary" ? "rpwrkrpr" : "r"))
        var index = -1
        var lastQuestion: String?
        var repeated = false
        let fast = hold == "summary"
        return OutLoudPorts(
            makeListener: {
                let failure: SpokenListenerFailure? = hold == "blocked" ? .microphoneDenied : hold == "nomodel" ? .noSpeechModel(language: "English") : nil
                return ScriptedSpokenListener(failure: failure, wordInterval: fast ? .milliseconds(10) : .milliseconds(110)) { turn in
                    if hold == "listening" { return nil }
                    if turn.question?.id != lastQuestion || turn.question == nil {
                        lastQuestion = turn.question?.id
                        index += 1
                        repeated = false
                    }
                    let letter = letters.indices.contains(index) ? letters[index] : "r"
                    // A "repeat" is said once, then the question is answered.
                    if letter == "e" {
                        if repeated { return words(for: "r", turn: turn) }
                        repeated = true
                    }
                    return words(for: letter, turn: turn)
                }
            },
            makeSpeaker: {
                ScriptedSpeaker(secondsPerWord: fast ? 0 : 0.05, holdsOnLine: hold == "asking" ? 1 : hold == "verdict" ? 2 : nil)
            })
    }

    /// What a person says for this letter on this turn.
    @MainActor static func words(for letter: Character, turn: SpokenTurn) -> String {
        if turn.isReply {
            switch letter {
            case "r": return "got it"
            case "p": return "that was hard"
            default: return "again"
            }
        }
        guard let question = turn.question else { return "" }
        switch letter {
        case "s": return "skip"
        case "e": return "say that again"
        case "x": return "stop"
        case "k": return "I don't know"
        case "w":
            if question.kind == .mcq, let right = question.rightPlace {
                return ChoiceOrder.letters[right == 0 ? 1 : 0]
            }
            return "I think it has something to do with the weather"
        case "p":
            if question.kind.isOwnWords, let first = question.ideas.first {
                return first.terms.first ?? first.label
            }
            return "I think it has something to do with the weather"
        default:
            if question.kind == .mcq, let right = question.rightPlace { return "It's \(ChoiceOrder.letters[right])" }
            if question.kind.isOwnWords, !question.ideas.isEmpty { return question.ideas.compactMap(\.terms.first).joined(separator: " and ") }
            return question.rightAnswer
        }
    }
}
#endif
