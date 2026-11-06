import Foundation
import SwiftData

// Study out loud, from the store's side: which questions can be said, what the speech engine is primed with, and what opens it.
extension AppModel {
    /// Active questions that can't be asked by voice although their kind can: more options than can be held in the head, more than one blank.
    /// Only read when an out-loud session is built, so blobs aren't decoded for anything else.
    func unspeakableItemIDs() -> Set<UUID> {
        let active = ItemStatus.active.rawValue
        let mcq = ItemKind.mcq.rawValue, cloze = ItemKind.cloze.rawValue
        let items = fetch(FetchDescriptor<StudyItem>(predicate: #Predicate {
            $0.deletedAt == nil && $0.statusRaw == active && ($0.kindRaw == mcq || $0.kindRaw == cloze)
        }))
        return Set(items.filter {
            !OutLoudPolicy.canAsk(kind: $0.kind, options: $0.choices.count, blanks: $0.cloze?.answers.count ?? 0)
        }.map(\.id))
    }

    /// The session Study out loud runs: the day's own, or `base` (a course, an exam eve).
    func outLoudRequest(_ base: SessionRequest? = nil) -> SessionRequest {
        var request = base ?? SessionRequest(kind: .daily)
        request.id = UUID()
        request.spokenOnly = true
        return request
    }

    /// There is something to ask out loud in `built`: a question of a kind that can be said. (A question left out by its options or blanks is
    /// the rare case; the intro says so if nothing is left.)
    func canStudyOutLoud(_ built: BuiltSession) -> Bool {
        built.entries.contains { OutLoudPolicy.kinds.contains($0.kind) }
    }

    /// The microphone and the speech engine for Teach Cap, primed with the course's words.
    func teachPorts(courseID: UUID?) -> TeachPorts {
        let own = Locale.preferredLanguages.first.map { Locale(identifier: $0).language.languageCode?.identifier } ?? nil
        let written = courseLanguage(of: course(courseID), excluding: nil)
        return .system(vocabulary: lectureVocabulary(courseID: courseID), language: written == own ? nil : written)
    }

    /// The microphone and the speech engine for this session: primed with the words of its courses, in the language they are written in when that
    /// isn't the person's own.
    func outLoudPorts(for built: BuiltSession) -> OutLoudPorts {
        #if DEBUG
        if config.isHarness { return OutLoudDebug.ports() }
        #endif
        let counts = Dictionary(built.entries.compactMap(\.courseID).map { ($0, 1) }, uniquingKeysWith: +)
        let ordered = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.uuidString < $1.key.uuidString }.map(\.key)
        var vocabulary: [String] = []
        for id in ordered { vocabulary += lectureVocabulary(courseID: id) }
        let own = Locale.preferredLanguages.first.map { Locale(identifier: $0).language.languageCode?.identifier } ?? nil
        let written = ordered.first.flatMap { courseLanguage(of: course($0), excluding: nil) }
        return .system(vocabulary: Array(vocabulary.prefix(LectureVocabulary.limit)), language: written == own ? nil : written)
    }
}
