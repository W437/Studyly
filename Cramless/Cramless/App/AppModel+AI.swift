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

    /// What `ai.generateSet` needs for a source.
    func generationInput(for source: Source, maxItems: Int = 16, formats: [ItemKind] = ItemKind.allCases) -> GenerationInput {
        GenerationInput(course: source.course?.name ?? "", sourceTitle: source.title, level: settings.level?.rawValue,
                        pages: source.sortedPages.map(pageText), formats: formats, maxItems: maxItems)
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
    /// `preferring` first.
    func tutorMaterial(courseID: UUID?, preferring sourceID: UUID? = nil) -> [TutorMaterial] {
        let sources: [Source] = course(courseID).map { $0.liveSources } ?? courses.flatMap(\.liveSources)
        let ordered = sources.sorted { a, b in
            if a.id == sourceID { return true }
            if b.id == sourceID { return false }
            return a.createdAt < b.createdAt
        }
        return ordered.map { source in
            TutorMaterial(sourceID: source.id, title: source.title, kind: source.kind,
                          pages: source.sortedPages.map(pageText), segments: source.kind == .lecture ? source.segments : [])
        }
    }

    /// What `ai.lectureNotes` needs for a recorded lecture.
    func lectureInput(for source: Source, maxItems: Int = 8) -> LectureInput {
        LectureInput(course: source.course?.name ?? "", title: source.title, segments: source.segments,
                     flags: source.flags, maxItems: maxItems)
    }
}
