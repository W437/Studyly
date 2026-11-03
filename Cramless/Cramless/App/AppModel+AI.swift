import Foundation

// AI consent changes, and the inputs `app.ai` takes, built from the store. The router itself never reads a model
// object or writes settings: screens hand it values from here and apply its drafts through their own lanes'
// AppModel extensions (`ItemFactory` makes the items).
extension AppModel {

    // MARK: Consent

    /// The person allowed Cloud AI at the current terms (`AIConsent.currentVersion`).
    var hasCloudConsent: Bool { AIConsent.isGranted(settings) }

    /// Allow pressed in the consent sheet. `sendPhotos` sets the separate photos switch when the sheet showed it.
    func allowCloudAI(sendPhotos: Bool? = nil) {
        var s = settings
        s.cloudConsentVersion = AIConsent.currentVersion
        if let sendPhotos { s.sendPhotos = sendPhotos }
        settings = s
        ai.clearSuggestion()
        // The account the relay needs is made now, in the background, so the first cloud job finds it ready.
        if settings.ageBand != .under13 { account.prepare() }
    }

    /// Settings ▸ AI and privacy ▸ Cloud AI off: nothing more is sent, and photos go off with it.
    func withdrawCloudAI() {
        var s = settings
        s.cloudConsentVersion = 0
        s.sendPhotos = false
        settings = s
    }

    /// The photos switch. It only counts while Cloud AI is allowed; turning it on before that asks for consent in
    /// the sheet instead (the caller presents `.consent(.photos)`).
    func setSendPhotos(_ on: Bool) {
        settings.sendPhotos = on
    }

    // MARK: Inputs from the store

    /// A page as the AI jobs read it.
    func pageText(_ page: SourcePage) -> PageText {
        PageText(index: page.pageIndex, label: page.label, lines: page.lines,
                 imageURL: page.imageFileName.map { FileStore.url(for: $0) })
    }

    /// What `ai.generateSet` needs for a source. A set has about one question for every 150 words of the source, at least 8,
    /// and at most 24 on the free plan (40 paid): `AIFreeLimits.questionCount`. A caller that wants another size passes it.
    /// A page with nothing on it (the references a PDF's cleaning took out, a blank scan) is not sent: it would only use up a
    /// page of the scan.
    func generationInput(for source: Source, maxItems: Int? = nil, formats: [ItemKind] = ItemKind.allCases) -> GenerationInput {
        let pages = source.sortedPages.filter { !$0.lines.isEmpty || $0.imageFileName != nil }.map(pageText)
        return GenerationInput(course: source.course?.name ?? "", sourceTitle: source.title, level: settings.level?.rawValue,
                               pages: pages, formats: formats,
                               maxItems: maxItems ?? GenerationPlan.questionCount(for: pages, plan: ai.plan),
                               courseLanguage: courseLanguage(of: source.course, excluding: source.id))
    }

    /// The language the student's other sources in a course are written in, when most of those the recogniser is sure of agree
    /// (`LocalGenerator.commonLanguage`). A page whose own words don't say what language it is in (an equation sheet) falls back to
    /// it, and then to the device's, instead of to a rare language guessed from the symbols. Looks at the first pages of the eight
    /// newest sources (a deck's cards are too short to tell), so it stays cheap.
    func courseLanguage(of course: Course?, excluding sourceID: UUID?) -> String? {
        guard let course else { return nil }
        let others = course.liveSources.filter { $0.id != sourceID && !$0.kind.isDeck }.sorted { $0.createdAt > $1.createdAt }.prefix(8)
        let texts = others.map { source -> String in
            if source.kind == .lecture { return String(source.segments.prefix(60).map(\.text).joined(separator: " ").prefix(3000)) }
            return String(source.sortedPages.prefix(2).flatMap { $0.lines.map(\.text) }.joined(separator: " ").prefix(3000))
        }
        return LocalGenerator.commonLanguage(of: texts)
    }

    /// What the grader needs for an item, with the lines it came from as context.
    func gradeSubject(for item: StudyItem) -> GradeSubject {
        GradeSubject(kind: item.kind, prompt: item.prompt, modelAnswer: item.answer, keyIdeas: item.keyIdeas,
                     choices: item.choices, cloze: item.cloze, diagramLabels: item.diagram?.targets.map(\.label) ?? [],
                     sourceExcerpt: sourceExcerpt(for: item), level: settings.level?.rawValue)
    }

    /// The text of the lines (or lecture segments) an item points at.
    func sourceExcerpt(for item: StudyItem) -> String? {
        guard let ref = item.sourceRef, let source = source(ref.sourceID), !ref.anchorIDs.isEmpty else { return nil }
        let wanted = Set(ref.anchorIDs)
        if source.kind == .lecture {
            let text = source.segments.filter { wanted.contains($0.id) }.map(\.text).joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        let pages = ref.pageIndex.map { index in source.sortedPages.filter { $0.pageIndex == index } } ?? source.sortedPages
        let text = pages.flatMap(\.lines).filter { wanted.contains($0.id) }.map(\.text).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// The material the tutor may answer from: every live source of the course (or of every course), with
    /// `preferring` first. An imported deck is material too, a passage to each of its cards.
    func tutorMaterial(courseID: UUID?, preferring sourceID: UUID? = nil) -> [TutorMaterial] {
        let sources: [Source] = course(courseID).map { $0.liveSources } ?? courses.flatMap(\.liveSources)
        let ordered = sources.sorted { a, b in
            if a.id == sourceID { return true }
            if b.id == sourceID { return false }
            return a.createdAt < b.createdAt
        }
        return ordered.map { source in
            if source.kind.isDeck {
                return TutorMaterial.deck(sourceID: source.id, title: source.title, kind: source.kind, cards: deckCards(of: source))
            }
            return TutorMaterial(sourceID: source.id, title: source.title, kind: source.kind,
                                 pages: source.sortedPages.map(pageText), segments: source.kind == .lecture ? source.segments : [])
        }
    }

    /// The cards of an imported deck as the tutor reads them, in the order the Library lists them. A fill-in card reads as its
    /// sentence with a blank, and its answers on the back.
    func deckCards(of source: Source) -> [TutorCard] {
        questions(from: source).filter { $0.status == .active || $0.status == .suspended }.map { item in
            if item.kind == .cloze, let cloze = item.cloze {
                let blanked = cloze.text.replacingOccurrences(of: #"\{\{[^}]*\}\}"#, with: "____", options: .regularExpression)
                return TutorCard(id: item.id.uuidString, front: blanked, back: cloze.answers.joined(separator: ", "), note: item.explanation)
            }
            return TutorCard(id: item.id.uuidString, front: item.prompt, back: item.answer, note: item.explanation)
        }
    }

    /// The card a citation's quote came from, with its place in the deck (1 for the first); nil when the deck or the card is gone.
    /// `label` is the citation's ("Deck: X · card 7"): when two cards share the quoted text, the card it numbers is the one meant.
    func deckCard(quoting quote: String, in sourceID: UUID, label: String? = nil) -> (source: Source, number: Int, card: TutorCard)? {
        guard let deck = self.source(sourceID), deck.deletedAt == nil, deck.kind.isDeck else { return nil }
        let cards = deckCards(of: deck)
        if let number = label.flatMap(TutorMaterial.cardNumber(inLabel:)), cards.indices.contains(number - 1),
           HighlightMark.locate(quote, in: cards[number - 1].text) != nil {
            return (deck, number, cards[number - 1])
        }
        guard let index = TutorMaterial.cardIndex(quoting: quote, in: cards) else { return nil }
        return (deck, index + 1, cards[index])
    }

    /// What `ai.lectureNotes` needs for a recorded lecture.
    func lectureInput(for source: Source, maxItems: Int = AIFreeLimits.lectureQuestions) -> LectureInput {
        LectureInput(course: source.course?.name ?? "", title: source.title, segments: source.segments,
                     flags: source.flags, maxItems: maxItems)
    }
}
