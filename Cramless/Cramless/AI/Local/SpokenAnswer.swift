import Foundation

/// What a person said out loud, read as a command or an answer. Pure: it takes the recogniser's words and what the question expects, so
/// every phrase is tested without a microphone. Study out loud reads with it (`OutLoudController`).
///
/// A command has to be the whole of what was said, so an answer that happens to hold the word "stop" stays an answer. So does a letter
/// ("a cell wall" is not option A). Recognisers punctuate and spell as they like, which `clean` and the tables below allow for: measured on
/// this Mac's models (`scripts/speech_live/run.sh answers`) "C" came out "See", "Capital C" or "C."; "B" as "It's me"; "option" as "Auction";
/// "the first one" as "The 1st one". Letters alone are the shakiest, so an option's own words and its place count too. Commands and ratings are English for now; letters, places
/// and what people say around an answer are read in the app's main study languages too ("la b", "die zweite", "2番", "Bです", "creo que es …").
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
        let cleaned = clean(heard)
        let peeled = peeled(cleaned)
        let core = cjkCore(peeled)
        if !core.isEmpty, core != peeled { return core }
        return peeled.isEmpty ? heard.trimmingCharacters(in: .whitespacesAndNewlines) : peeled
    }

    /// What to check a fill-in against: the words said, or the right word when a sentence holds it ("creo que es inflación", "it's mitosis because the cell divides"). A sentence that
    /// names something else too ("mitosis or meiosis", "the nucleus of the cell" for "cell") stays as it was said, for the exact check to refuse.
    /// `question`: its words may be said back.
    static func blankAnswer(_ heard: String, accepted: [String], question: String = "") -> String {
        let bare = bareAnswer(heard)
        for candidate in [heard, bare] where LocalGrader.exactMatch(candidate, accepted: accepted) != .wrong { return candidate }
        return saidInside(heard, accepted: accepted, question: question) ?? bare
    }

    /// The accepted answer a sentence says, when it says nothing else that could be one.
    private static func saidInside(_ heard: String, accepted: [String], question: String) -> String? {
        var tokens = Lexicon.tokens(heard)
        // A correction: what counts comes after it. An explanation: what counts comes before it.
        for marker in corrections {
            let words = marker.split(separator: " ").map(String.init)
            guard words.count <= tokens.count else { continue }
            if let at = (0...(tokens.count - words.count)).last(where: { start in tokens[start..<(start + words.count)].map(\.word) == words }) {
                tokens = Array(tokens[(at + words.count)...])
                break
            }
        }
        if let cut = tokens.firstIndex(where: { explanationWords.contains($0.word) }) { tokens = Array(tokens[..<cut]) }
        let asked = Set(Lexicon.contentStems(question))
        for answer in accepted {
            for found in Lexicon.find(Lexicon.tokens(answer), in: tokens) {
                guard let first = found.tokenIndices.first, let last = found.tokenIndices.last else { continue }
                let before = first > 0 ? tokens[first - 1].word : ""
                let after = last + 1 < tokens.count ? tokens[last + 1].word : ""
                guard !Lexicon.isNegated(at: first, in: tokens), !otherNegations.contains(before), !orWords.contains(before), !orWords.contains(after) else { continue }
                let used = Set(found.tokenIndices)
                let others = tokens.indices.filter { index in
                    let token = tokens[index]
                    return !used.contains(index) && token.isContent && !sentenceWords.contains(token.word) && !token.isNumber && !asked.contains(token.stem)
                        && !Lexicon.isNegated(at: index, in: tokens) && !(index > 0 && otherNegations.contains(tokens[index - 1].word))
                }
                if others.isEmpty { return answer }
            }
        }
        return nil
    }

    private static let corrections = ["no wait", "wait", "actually", "i mean", "sorry", "perdon", "digo", "quiero decir", "mejor dicho", "nein", "ich meine", "moment"]
    private static let explanationWords: Set<String> = ["because", "since", "porque", "weil", "denn", "ya", "なぜなら"]
    private static let orWords: Set<String> = ["or", "o", "u", "oder", "ou", "か"]
    private static let otherNegations: Set<String> = ["nicht", "kein", "keine", "keinen", "pas", "nao", "non"]
    /// What people say around an answer, in the app's main study languages: never an answer of its own.
    private static let sentenceWords: Set<String> = [
        "think", "guess", "believe", "say", "sure", "pretty", "maybe", "probably", "perhaps", "answer", "word", "blank", "missing", "goes", "know", "mean", "one",
        "creo", "que", "es", "son", "la", "el", "los", "las", "lo", "un", "una", "unos", "unas", "de", "del", "y", "pienso", "seria", "diria", "digo", "quizas", "tal", "vez", "seguro",
        "respuesta", "palabra", "falta", "pues", "bueno", "parece", "supongo", "yo",
        "ich", "glaube", "denke", "meine", "ist", "das", "der", "die", "den", "dem", "des", "ein", "eine", "einen", "wohl", "vielleicht", "wahrscheinlich", "antwort", "wort", "sicher", "also",
        "je", "pense", "crois", "c'est", "le", "les", "une", "reponse", "mot",
        "です", "だ", "と", "思い", "ます", "思う", "答え", "は", "たぶん", "多分", "かな", "が", "でしょう",
    ]

    /// Lower case, no accents, no punctuation but apostrophes inside a word, one space between words.
    static func clean(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
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
        "b": 1, "be": 1, "bee": 1, "me": 1, "beh": 1,
        "c": 2, "see": 2, "sea": 2, "si": 2, "ce": 2, "ze": 2, "zeh": 2,
        "d": 3, "dee": 3, "de": 3, "deh": 3,
    ]

    private static let placeWords: [String: Int] = [
        "first": 0, "one": 0, "1": 0, "1st": 0,
        "second": 1, "two": 1, "2": 1, "2nd": 1, "to": 1, "too": 1,
        "third": 2, "three": 2, "3": 2, "3rd": 2,
        "fourth": 3, "forth": 3, "four": 3, "4": 3, "4th": 3, "for": 3,
        "primera": 0, "primero": 0, "primer": 0, "uno": 0, "erste": 0, "erster": 0, "erstes": 0, "eins": 0, "premiere": 0, "premier": 0, "prima": 0, "primo": 0, "primeira": 0, "primeiro": 0,
        "segunda": 1, "segundo": 1, "dos": 1, "zweite": 1, "zweiter": 1, "zweites": 1, "zwei": 1, "deuxieme": 1, "seconde": 1, "seconda": 1, "secondo": 1, "deux": 1,
        "tercera": 2, "tercero": 2, "tres": 2, "dritte": 2, "dritter": 2, "drittes": 2, "drei": 2, "troisieme": 2, "terza": 2, "terzo": 2, "terceira": 2, "terceiro": 2, "trois": 2,
        "cuarta": 3, "cuarto": 3, "cuatro": 3, "vierte": 3, "vierter": 3, "viertes": 3, "vier": 3, "quatrieme": 3, "quarta": 3, "quarto": 3, "quatre": 3,
        "첫 번째": 0, "두 번째": 1, "세 번째": 2, "네 번째": 3,
    ]

    private static let lastWords: Set<String> = ["last", "ultima", "ultimo", "letzte", "letzter", "letztes", "derniere", "dernier"]

    private static let openers = [
        "um", "uh", "er", "hmm", "okay", "ok", "so", "well", "yeah", "maybe", "probably", "definitely", "i think", "i guess", "i believe",
        "i'd say", "id say", "i'd go with", "i'll go with", "i will go with", "i'll say", "i say", "i choose", "i pick", "i'll pick", "my answer is",
        "the answer is", "answer is", "the answer", "answer", "it's", "its", "it is", "that's", "thats", "that would be", "it must be", "must be",
        "it should be", "should be", "option", "auction", "letter", "choice", "number", "capital", "the",
        // Spanish
        "pues", "bueno", "a ver", "creo que es", "creo que", "pienso que es", "pienso que", "diria que es", "diria que", "diria", "seria", "la respuesta es", "respuesta", "es", "opcion", "letra", "numero",
        "quizas", "tal vez", "yo digo", "digo", "la", "el",
        // German
        "ich glaube es ist", "ich glaube", "ich denke es ist", "ich denke", "ich meine", "ich nehme", "ich wahle", "nimm", "die antwort ist", "antwort", "es ist", "das ist", "buchstabe", "nummer",
        "vielleicht", "wahrscheinlich", "also", "die", "der", "das",
        // French, Italian and Portuguese
        "je pense que c'est", "je pense que", "je dirais", "c'est", "reponse", "lettre", "le", "penso che sia", "credo che sia", "risposta", "lettera", "acho que e", "acho que", "resposta", "opcao",
    ]

    private static let closers = ["i think", "i guess", "maybe", "please", "is the answer", "is correct", "is right", "final answer", "is it", "one",
                                  "opcion", "respuesta", "creo", "por favor", "antwort", "option", "glaube ich", "denke ich", "bitte", "reponse", "resposta", "risposta"]

    // Japanese, Chinese and Korean have no spaces to peel at: "2番", "Bです", "答えはB", "第二个".
    private static let cjkOpeners = ["答えは", "答えが", "答え", "たぶん", "多分", "選択肢は", "選択肢", "番号", "答案是", "答案", "我选", "应该是", "应该选", "可能是", "选", "選", "第"]
    private static let cjkClosers = ["だと思います", "だと思う", "と思います", "と思う", "にします", "を選びます", "を選ぶ", "でしょう", "です", "かな", "番目", "番", "つ目", "個目", "个选项", "选项", "選項", "个", "個",
                                     "입니다", "이요", "번째", "번", "째", "요", "だ"]
    private static let cjkPlaces: [String: Int] = ["1": 0, "2": 1, "3": 2, "4": 3, "一": 0, "二": 1, "三": 2, "四": 3, "最後": -1, "最后": -1]

    /// The answer inside what's said around it, in the languages written without spaces. The same text when it isn't one.
    private static func cjkCore(_ plain: String) -> String {
        guard plain.contains(where: { $0.unicodeScalars.contains { $0.value >= 0x3040 } }) else { return plain }
        var text = plain.replacingOccurrences(of: " ", with: "")
        var changed = true
        while changed {
            changed = false
            for opener in cjkOpeners where text.hasPrefix(opener) && text.count > opener.count {
                text.removeFirst(opener.count)
                changed = true
            }
            for closer in cjkClosers where text.hasSuffix(closer) && text.count > closer.count {
                text.removeLast(closer.count)
                changed = true
            }
        }
        return text
    }

    private static func cjkPlace(_ plain: String, of options: [String]) -> Int? {
        let core = cjkCore(plain)
        if let letter = letterWords[core], core.count == 1, options.indices.contains(letter) { return letter }
        guard let place = cjkPlaces[core] else { return nil }
        if place < 0 { return options.count - 1 }
        return options.indices.contains(place) ? place : nil
    }

    /// `plain` with what people say around an answer taken off both ends.
    private static func peeled(_ plain: String) -> String { peelings(of: plain).last ?? plain }

    /// `plain` as each layer comes off: an option's own words can start with what's taken for an opener ("Its soil gaps", "El banco central").
    private static func peelings(of plain: String) -> [String] {
        var text = " \(plain) "
        var out: [String] = [plain]
        var changed = true
        while changed {
            changed = false
            for opener in openers where text.hasPrefix(" \(opener) ") && text.count > opener.count + 3 {
                text = String(text.dropFirst(opener.count + 1))
                out.append(text.trimmingCharacters(in: .whitespaces))
                changed = true
            }
            for closer in closers where text.hasSuffix(" \(closer) ") && text.count > closer.count + 3 {
                text = String(text.dropLast(closer.count + 1))
                out.append(text.trimmingCharacters(in: .whitespaces))
                changed = true
            }
        }
        return out
    }

    /// Which option was meant: a letter, a place ("the second one", "the last one"), or the option's own words, when they point to one
    /// option and no other.
    private static func place(in plain: String, of options: [String]) -> Int? {
        guard !options.isEmpty else { return nil }
        let peeled = peeled(plain)
        let cleanedOptions = options.map(clean)
        // An option's own words come first: an option can be "A" or "one", and then its place is how it is said too.
        if let exact = peelings(of: plain).lazy.compactMap({ cleanedOptions.firstIndex(of: $0) }).first {
            // An option named "A" that isn't the first: "A" could be either. Asked again, not guessed.
            if let letter = letterWords[peeled], peeled.count == 1, letter != exact, options.indices.contains(letter) { return nil }
            return exact
        }
        if let exact = cleanedOptions.firstIndex(of: cjkCore(plain)) { return exact }
        if let letter = letterWords[peeled], options.indices.contains(letter) { return letter }
        if let place = placeWords[peeled] ?? placeWords[plain], options.indices.contains(place) { return place }
        if lastWords.contains(peeled) { return options.count - 1 }
        if let place = cjkPlace(plain, of: options) { return place }
        // "It's B I'm pretty sure", "B because of the spindle": a letter in front, only when the rest isn't one of the options.
        let words = peeled.split(separator: " ").map(String.init)
        // "a segunda", "o segundo": an article, not the letter.
        if words.count == 2, ["a", "o"].contains(words[0]), let place = placeWords[words[1]], options.indices.contains(place) { return place }
        if words.count > 1, let first = words.first, first.count == 1, let letter = letterWords[first], options.indices.contains(letter),
           !cleanedOptions.contains(where: { $0.hasPrefix(peeled) }) {
            return letter
        }
        return optionSaid(peeled, among: cleanedOptions)
    }

    /// The one option these words are about: said whole inside them, or the part of it said is long enough to mean it.
    private static func optionSaid(_ said: String, among options: [String]) -> Int? {
        guard said.count >= 3 else { return nil }
        // The start of two options ("Government of the") means neither. The start of one, in words enough to mean it, means that one.
        let starts = options.indices.filter { options[$0].hasPrefix(said + " ") }
        if starts.count > 1 { return nil }
        if let only = starts.first, said.contains(" ") { return only }
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
