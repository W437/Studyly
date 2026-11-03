import Foundation

/// Cloud AI consent. `settings.cloudConsentVersion` holds the version the person accepted (0: never); a request
/// goes to the relay only while it is at least `currentVersion`. Sending page photos is a separate switch
/// (`settings.sendPhotos`) that only counts together with this consent.
enum AIConsent {
    /// Version 3: page text, typed answers and tutor questions go to OpenAI's models through Capling's relay, and with each question
    /// to Cap the notes of the course it answers from (every course, when none is chosen): the text of pages and lectures, the
    /// cards of imported decks and the names of the sources, all of it when it is short (about 6,000 words), otherwise the sources
    /// the question names and the passages that fit it (`TutorSelection`), and, when Cap is asked to look through the notes, the
    /// passages the lookup finds in any course (`search_notes`); page photos only
    /// with the second switch; nothing is used for training; and
    /// Ask Cap's tools: Cap now also sees the names of your courses, topics and exams, the exam dates and how ready you are, which
    /// topics are fading and how many cards are due, so it can make things for the right course, and, when you ask it to research
    /// something, the topic is searched on trusted study sites on the web. (Version 3 has not shipped, so its words could still be
    /// made to say all of this; once it has, a change to what is sent is version 4.) **Bump it when a request
    /// starts to carry a new kind of data or reaches a new processor** (for example switching on Private Cloud Compute), so
    /// everyone is asked again under the new terms.
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
}
