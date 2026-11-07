import Foundation

/// Cloud AI consent. `settings.cloudConsentVersion` holds the version the person accepted (0: never); a request
/// goes to the relay only while it is at least `currentVersion`. Sending page photos is a separate switch
/// (`settings.sendPhotos`) that only counts together with this consent.
enum AIConsent {
    /// Version 3: what Cloud AI sees goes to OpenAI's models through Capling's relay, and `Words` below says all of it: the words of what
    /// is added (pages, PDFs, syllabi, lecture transcripts, a sentence an exam date was heard in), typed and spoken answers (the words),
    /// mix-ups, reported questions, a last look's shakiest questions, and questions to Cap. With each question to Cap go the notes of the
    /// course it answers from (every course, when none is chosen): the text of pages and lectures, the cards of imported decks and the
    /// names of the sources, all of it when it is short (4,000 words on the tutor's route, 6,000 on the assistant's, `TutorSelection`),
    /// otherwise the sources the question names and the passages that fit it, and, when Cap is asked to look through the notes, the
    /// passages the lookup finds in any course (`search_notes`). Page photos only with the second switch; nothing is used for training.
    /// Ask Cap's tools also see the names of courses, topics and exams, the exam dates and how ready the person is, which topics are
    /// fading and how many questions are due, and, when asked to research something, the topic is searched on trusted study sites on the
    /// web. (Version 3 has not shipped, so its words could still be made to say all of this; once it has, a change to what is sent is
    /// version 4.) **Bump it when a request starts to carry a new kind of data or reaches a new processor** (for example switching on
    /// Private Cloud Compute), so everyone is asked again under the new terms.
    static let currentVersion = 3

    /// Who processes cloud requests, named in the consent sheet. Change it with the relay's wiring (`deps.ts`).
    static let processor = "OpenAI"

    static func isGranted(_ settings: AppSettings) -> Bool {
        settings.cloudConsentVersion >= currentVersion
    }

    /// Page photos may be sent: consent plus the photos switch.
    static func photosGranted(_ settings: AppSettings) -> Bool {
        isGranted(settings) && settings.sendPhotos
    }

    /// What's sent with Cloud AI on, in the words the consent sheet and Settings ▸ AI and privacy both show, so the two can't drift apart.
    /// `docs/privacy-wording.md` holds the same facts route by route; a change here changes that page too.
    enum Words {
        static let addedTitle: LocalizedStringResource = "What you add"
        static let added: LocalizedStringResource = "The words of your pages, PDFs, syllabi and lecture transcripts, with the names of the course and the source, so Cloud AI can write and check questions and notes. If you ask Cap to add an exam it heard in a lecture, the sentence with the date. Never a lecture's audio. Page photos only go with their own switch."

        static let askedTitle: LocalizedStringResource = "What you ask Cap"
        static let asked: LocalizedStringResource = "Your questions to Cap, and with each one the notes of the course Cap is answering from (every course, if you chose All courses): the text of your pages and lectures, the cards of decks you imported and the names of what you added. All of it when it's short, otherwise the parts that fit your question. When you ask Cap to look through your notes, the passages it finds in any of your courses go too. If you snap a problem, only its words go, never the photo. So Cap can make things for the right course, it also sees the names of your courses, topics and exams, your exam dates, how ready you are, which topics are fading and how many questions are due. If you ask it to research something online, that topic is searched on trusted study sites."

        static let answeredTitle: LocalizedStringResource = "What you answer"
        static let answered: LocalizedStringResource = "Answers you type or say when they're graded, and what you tell Cap in Teach Cap (the words, never your voice). The questions you mix up or that look alike, with your answers, when you ask Cap about them. A question you say looks wrong, with the lines it came from and anything you wrote. In the two days before an exam, your shakiest questions and their lines go by themselves when you open Capling, so Cap can put them in plain words for your last look."
    }
}
