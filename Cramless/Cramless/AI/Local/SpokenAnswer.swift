import Foundation

/// What a person said out loud, read as a command or an answer. Pure: it takes the recogniser's words and what the question expects, so
/// every phrase is tested without a microphone. Study out loud reads with it (`OutLoudController`).
///
/// A command has to be the whole of what was said, so an answer that happens to hold the word "stop" stays an answer. So does a letter
/// ("a cell wall" is not option A). Recognisers punctuate and spell as they like, which `clean` and the tables below allow for: measured on
/// this Mac's models (`scripts/speech_live/run.sh answers`) "C" came out "See", "Capital C" or "C."; "B" as "It's me"; "option" as "Auction";
/// "the first one" as "The 1st one". Letters alone are the shakiest, so an option's own words and its place count too. English for now:
/// the words of other languages come with the app's translation.
enum SpokenAnswer {
    enum Command: String, Equatable, Sendable {
        case repeatQuestion, skip, stop
    }

    /// What the moment is listening for.
    enum Expecting: Equatable, Sendable {
        /// Free words: an answer in the person's own words, a fill-in, a flashcard's first try.
        case words
        /// One of these options, in the order they were read.
        case choice(options: [String])
        /// How a flashcard or a self-marked answer went: "got it", "again".
        case rating
    }

    enum Reading: Equatable, Sendable {
        case command(Command)
        case dontKnow
        /// The option at this place in the order they were read.
        case choice(Int)
        case rating(Rating)
        /// The person's words as the recogniser gave them.
        case words(String)
        /// Nothing was said, or nothing that this moment can use.
        case nothing
    }

    static func read(_ heard: String, expecting: Expecting) -> Reading {
        let trimmed = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = clean(trimmed)
        guard !plain.isEmpty else { return .nothing }
        let bare = withoutPoliteness(plain)
        if expecting == .rating, let rating = rating(in: bare) { return .rating(rating) }
        if let command = command(in: bare) { return .command(command) }
        // On its own, "again" means the question, unless a rating is what's asked for (above).
        if bare == "again" { return .command(.repeatQuestion) }
        if isDontKnow(trimmed, bare: bare) { return .dontKnow }
        switch expecting {
        case .words:
            return .words(trimmed)
        case .choice(let options):
            if let place = place(in: plain, of: options) { return .choice(place) }
            return .words(trimmed)
        case .rating:
            return .nothing
        }
    }

    /// The words of an answer without what people say around one ("I think it's anaphase" is "anaphase"), for a fill-in's exact check.
    static func bareAnswer(_ heard: String) -> String {
        let peeled = peeled(clean(heard))
        return peeled.isEmpty ? heard.trimmingCharacters(in: .whitespacesAndNewlines) : peeled
    }

    /// Lower case, no accents, no punctuation but apostrophes inside a word, one space between words.
    static func clean(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "\u{2019}", with: "'")
        var out = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                out.unicodeScalars.append(scalar)
            } else {
                out.append(" ")
            }
        }
        return out.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Commands

    private static let commands: [String: Command] = {
        var table: [String: Command] = [:]
        for phrase in ["repeat", "repeat that", "repeat it", "repeat the question", "repeat question", "say that again", "say it again",
                       "say again", "one more time", "what was the question", "what was that", "what", "pardon", "come again",
                       "read it again", "read that again", "ask again", "ask me again", "i didn't hear", "i didn't hear that",
                       "i didn't catch that", "didn't catch that"] {
            table[phrase] = .repeatQuestion
        }
        for phrase in ["skip", "skip it", "skip that", "skip this", "skip this one", "skip that one", "skip question", "skip the question",
                       "next", "next one", "next question", "pass", "move on"] {
            table[phrase] = .skip
        }
        for phrase in ["stop", "stop now", "stop studying", "stop session", "stop the session", "end", "end session", "end the session",
                       "finish", "i'm done", "im done", "done", "done for now", "i'm finished", "quit", "that's enough", "thats enough", "enough"] {
            table[phrase] = .stop
        }
        return table
    }()

    private static func command(in bare: String) -> Command? { commands[bare] }

    /// "Please repeat that", "okay skip", "can you say that again": the polite part goes.
    private static func withoutPoliteness(_ plain: String) -> String {
        var words = plain.split(separator: " ").map(String.init)
        let openers: [[String]] = [["um"], ["uh"], ["er"], ["hmm"], ["okay"], ["ok"], ["sorry"], ["please"], ["hey", "cap"], ["cap"],
                                   ["can", "you"], ["could", "you"], ["would", "you"]]
        var changed = true
        while changed {
            changed = false
            for opener in openers where words.count > opener.count && Array(words.prefix(opener.count)) == opener {
                words.removeFirst(opener.count)
                changed = true
            }
        }
        if words.count > 1, words.last == "please" { words.removeLast() }
        return words.joined(separator: " ")
    }

    // MARK: I don't know

    private static func isDontKnow(_ heard: String, bare: String) -> Bool {
        SelfCheck.isDontKnow(heard) || ["not sure", "i'm not sure", "im not sure", "no clue", "i've got nothing"].contains(bare)
    }

    // MARK: Ratings

    private static let ratingPhrases: [(Rating, [String])] = [
        // Checked first: "I got it wrong" holds "got it".
        (.again, ["got it wrong", "got that wrong", "didn't get it", "didnt get it", "didn't get that", "didn't have it", "didnt have it",
                  "missed it", "missed that", "not yet", "forgot it", "i forgot"]),
        (.hard, ["that was hard", "kind of", "sort of", "pretty hard"]),
        (.easy, ["that was easy", "too easy", "super easy"]),
        (.good, ["got it", "got that", "god it", "knew it", "knew that", "had it", "i did", "that's right", "thats right"]),
    ]

    /// Short words count only when they are all that was said.
    private static let ratingWords: [String: Rating] = [
        "again": .again, "no": .again, "nope": .again, "wrong": .again, "nah": .again,
        "hard": .hard, "almost": .hard, "partly": .hard, "close": .hard,
        "easy": .easy,
        "yes": .good, "yeah": .good, "yep": .good, "yup": .good, "right": .good, "correct": .good, "good": .good,
    ]

    private static func rating(in bare: String) -> Rating? {
        if let rating = ratingWords[bare] { return rating }
        let padded = " \(bare) "
        for (rating, phrases) in ratingPhrases {
            if phrases.contains(where: { padded.contains(" \($0) ") }) { return rating }
        }
        return nil
    }

    // MARK: Options

    private static let letterWords: [String: Int] = [
        "a": 0, "ay": 0, "eh": 0, "hey": 0, "k": 0,
        "b": 1, "be": 1, "bee": 1, "me": 1,
        "c": 2, "see": 2, "sea": 2, "si": 2,
        "d": 3, "dee": 3, "de": 3,
    ]

    private static let placeWords: [String: Int] = [
        "first": 0, "one": 0, "1": 0, "1st": 0,
        "second": 1, "two": 1, "2": 1, "2nd": 1, "to": 1, "too": 1,
        "third": 2, "three": 2, "3": 2, "3rd": 2,
        "fourth": 3, "forth": 3, "four": 3, "4": 3, "4th": 3, "for": 3,
    ]

    private static let openers = [
        "um", "uh", "er", "hmm", "okay", "ok", "so", "well", "yeah", "maybe", "probably", "definitely", "i think", "i guess", "i believe",
        "i'd say", "id say", "i'd go with", "i'll go with", "i will go with", "i'll say", "i say", "i choose", "i pick", "i'll pick", "my answer is",
        "the answer is", "answer is", "the answer", "answer", "it's", "its", "it is", "that's", "thats", "that would be", "it must be", "must be",
        "it should be", "should be", "option", "auction", "letter", "choice", "number", "capital", "the",
    ]

    private static let closers = ["i think", "i guess", "maybe", "please", "is the answer", "is correct", "is right", "final answer", "is it", "one"]

    /// `plain` with what people say around an answer taken off both ends.
    private static func peeled(_ plain: String) -> String {
        var text = " \(plain) "
        var changed = true
        while changed {
            changed = false
            for opener in openers where text.hasPrefix(" \(opener) ") && text.count > opener.count + 3 {
                text = String(text.dropFirst(opener.count + 1))
                changed = true
            }
            for closer in closers where text.hasSuffix(" \(closer) ") && text.count > closer.count + 3 {
                text = String(text.dropLast(closer.count + 1))
                changed = true
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Which option was meant: a letter, a place ("the second one", "the last one"), or the option's own words, when they point to one
    /// option and no other.
    private static func place(in plain: String, of options: [String]) -> Int? {
        guard !options.isEmpty else { return nil }
        let peeled = peeled(plain)
        let cleanedOptions = options.map(clean)
        // An option's own words come first: an option can be "A" or "one", and then its place is how it is said too.
        if let exact = cleanedOptions.firstIndex(of: plain) ?? cleanedOptions.firstIndex(of: peeled) { return exact }
        if let letter = letterWords[peeled], options.indices.contains(letter) { return letter }
        if let place = placeWords[peeled] ?? placeWords[plain], options.indices.contains(place) { return place }
        if peeled == "last" { return options.count - 1 }
        // "It's B I'm pretty sure", "B because of the spindle": a letter in front, only when the rest isn't one of the options.
        let words = peeled.split(separator: " ").map(String.init)
        if words.count > 1, let first = words.first, first.count == 1, let letter = letterWords[first], options.indices.contains(letter),
           !cleanedOptions.contains(where: { $0.hasPrefix(peeled) }) {
            return letter
        }
        return optionSaid(peeled, among: cleanedOptions)
    }

    /// The one option these words are about: said whole inside them, or the part of it said is long enough to mean it.
    private static func optionSaid(_ said: String, among options: [String]) -> Int? {
        guard said.count >= 3 else { return nil }
        let padded = " \(said) "
        let whole = options.indices.filter { !options[$0].isEmpty && padded.contains(" \(options[$0]) ") }
        if whole.count == 1 { return whole[0] }
        if whole.count > 1 { return whole.max { options[$0].count < options[$1].count } }
        var scored: [(index: Int, match: Double)] = []
        for index in options.indices {
            let overlap: Double = Lexicon.overlap(of: said, with: options[index])
            let cover: Double = Lexicon.overlap(of: options[index], with: said)
            if overlap >= 0.6, cover >= 0.5 { scored.append((index, overlap + cover)) }
        }
        scored.sort { $0.match > $1.match }
        guard let best = scored.first else { return nil }
        if scored.count > 1, best.match - scored[1].match < 0.25 { return nil }
        return best.index
    }
}
