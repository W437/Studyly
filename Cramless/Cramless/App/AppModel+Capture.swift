import AVFoundation
import Foundation
import SwiftData

// Capture: sources from page images, PDFs, typed text and the sample page; deck imports; lectures; files opened
// from other apps. Every mutation stamps with `touch` and ends in `save()`.
//
// Nothing here calls AI. Capture delivers a source whose pages have lines (anchor ids `p<page>.l<n>`, boxes for
// scanned pages), or a lecture with timed segments and flags; generation (the AI lane) starts from there.
extension AppModel {
    // MARK: - Sources from material

    /// Reads a capture request into a new source and returns it once every page is read (status `.read`; `.failed`
    /// when no page had readable text: offer a better read for `pagesWantingBetterRead`, or another photo).
    /// `progress` reports each page. Cancelling the task stops between pages; then call `discardSource(_:)`.
    func createSource(from request: CaptureRequest, title: String? = nil,
                      progress: @escaping @MainActor (CaptureProgress) -> Void = { _ in }) async throws -> Source {
        let course = course(request.courseID)
        switch request.input {
        case .images(let paths):
            return try await createSource(fromImages: paths, course: course, title: title, progress: progress)
        case .pdf(let url):
            return try await createSource(fromPDF: url, course: course, title: title, progress: progress)
        case .text(let textTitle, let body):
            return try createSource(fromText: body, title: title ?? textTitle, course: course)
        case .sample:
            return createSampleSource(course: course)
        }
    }

    /// Page images (staged by the scanner or from Photos) become a source: the images move into
    /// `sources/<id>/page-<n>.jpg`, then each page is read on this iPhone.
    func createSource(fromImages paths: [String], course: Course?, title: String? = nil, kind: SourceKind = .scan,
                      progress: @escaping @MainActor (CaptureProgress) -> Void = { _ in }) async throws -> Source {
        guard !paths.isEmpty else { throw CaptureError.noPages }
        progress(.preparing)
        let source = Source(course: course, kind: kind, title: title ?? Self.scanTitle(now), status: .captured, now: now)
        let adopted = try PageImageStore.adopt(paths, sourceID: source.id)
        context.insert(source)
        course?.sources.append(source)
        for (index, path) in adopted.enumerated() {
            let page = SourcePage(source: source, pageIndex: index, label: "\(index + 1)", text: "", lines: [],
                                  imageFileName: path)
            context.insert(page)
            source.pages.append(page)
        }
        touch(source)
        save()
        try await readPages(of: source, keepTitle: title != nil, progress: progress)
        return source
    }

    /// Reads the pages of `source` that have an image and haven't been read (resumable after a cancel or a
    /// crash), then marks the source read.
    func readPages(of source: Source, keepTitle: Bool = true,
                   progress: @escaping @MainActor (CaptureProgress) -> Void = { _ in }) async throws {
        let pages = source.sortedPages.filter { $0.read == nil && $0.imageFileName != nil }
        progress(CaptureProgress(stage: .reading, completed: 0, total: pages.count))
        for (done, page) in pages.enumerated() {
            try Task.checkCancellation()
            guard let image = page.imageFileName else { continue }
            let index = page.pageIndex
            let read = try await TextRecognizer.readingEnglishToo { try await TextRecognizer.read(imageAt: image, pageIndex: index, preferredLanguages: $0) }
            guard page.modelContext != nil, source.modelContext != nil else { return }
            page.apply(read)
            progress(CaptureProgress(stage: .reading, completed: done + 1, total: pages.count))
        }
        progress(CaptureProgress(stage: .saving, completed: pages.count, total: pages.count))
        if !keepTitle, let first = source.sortedPages.first, let heading = PageLayout.titleLine(in: first.lines) {
            source.title = heading
        }
        source.status = source.pages.contains { !$0.lines.isEmpty } ? .read : .failed
        touch(source)
        save()
    }

    /// A PDF becomes a source: the file is copied in (`sources/<id>/document.pdf`), text-layer pages become lines,
    /// image-only pages are rendered and read. At most 300 pages; a toast says when the rest was left out.
    func createSource(fromPDF url: URL, course: Course?, title: String? = nil,
                      progress: @escaping @MainActor (CaptureProgress) -> Void = { _ in }) async throws -> Source {
        progress(.preparing)
        let source = Source(course: course, kind: .pdf, title: title ?? url.deletingPathExtension().lastPathComponent,
                            status: .captured, now: now)
        let folder = PageImageStore.sourceFolder(source.id)
        do {
            source.fileName = try withFileAccess(url) { try FileStore.copy(from: url, folder: folder, name: "document.pdf") }
        } catch {
            throw CaptureError.pdfUnreadable
        }
        ImportInbox.release(url)
        let result: PDFReader.Result
        do {
            result = try await PDFReader.read(FileStore.url(for: source.fileName ?? ""), imageFolder: folder) { done, total in
                Task { @MainActor in progress(CaptureProgress(stage: .reading, completed: done, total: total)) }
            }
        } catch {
            FileStore.removeFolder(folder)
            throw error
        }
        progress(CaptureProgress(stage: .saving, completed: result.pages.count, total: result.pages.count))
        if title == nil, let documentTitle = result.title { source.title = documentTitle }
        context.insert(source)
        course?.sources.append(source)
        for captured in result.pages {
            let page = SourcePage(source: source, pageIndex: captured.pageIndex, label: captured.label, text: "", lines: [])
            page.apply(captured)
            context.insert(page)
            source.pages.append(page)
        }
        source.status = result.pages.contains { !$0.lines.isEmpty } ? .read : .failed
        touch(source)
        save()
        if result.truncated {
            router.show(Toast(message: "Added the first \(result.pages.count) of \(result.pageCount) pages.",
                              systemImage: "exclamationmark.triangle.fill", tone: .warning, duration: 5))
        }
        return source
    }

    /// Typed or pasted text becomes a source of ~600-word pages, a line per sentence (no boxes).
    func createSource(fromText body: String, title: String? = nil, course: Course?) throws -> Source {
        let pages = TextPaginator.pages(from: body)
        guard !pages.isEmpty else { throw CaptureError.emptyText }
        let fallback = pages.first?.lines.first.map { String($0.text.prefix(60)) } ?? "Notes"
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = Source(course: course, kind: .text, title: (name?.isEmpty == false ? name : nil) ?? fallback,
                            status: .read, now: now)
        context.insert(source)
        course?.sources.append(source)
        for captured in pages {
            let page = SourcePage(source: source, pageIndex: captured.pageIndex, label: captured.label, text: "", lines: [])
            page.apply(captured)
            context.insert(page)
            source.pages.append(page)
        }
        touch(source)
        save()
        return source
    }

    /// The bundled sample page (Biology p. 87) as a source: its recognised lines ship with the app, so it reads the
    /// same on every iPhone, offline.
    @discardableResult
    func createSampleSource(course: Course?) -> Source {
        let source: Source
        if let course {
            source = SamplePage.makeSource(in: course, context: context, now: now)
        } else {
            source = Source(course: nil, kind: .sample, title: SamplePage.title, status: .read, now: now)
            context.insert(source)
            let file = SamplePage.ocr()
            let image = SamplePage.imageURL.flatMap {
                try? FileStore.copy(from: $0, folder: PageImageStore.sourceFolder(source.id), name: PageImageStore.pageFileName(0))
            }
            let lines = file?.lines ?? []
            let page = SourcePage(source: source, pageIndex: 0, label: SamplePage.pageLabel,
                                  text: lines.map(\.text).joined(separator: "\n"), lines: lines, imageFileName: image,
                                  width: file?.width ?? 1200, height: file?.height ?? 1800)
            context.insert(page)
            source.pages.append(page)
        }
        for page in source.pages { page.read = .sample }
        touch(source)
        save()
        return source
    }

    /// Puts a better read of a page in place: a cloud transcription of its photo (lines without boxes, ids like
    /// `p0.c3`), or text the person typed in. The page and its source become readable.
    func replaceLines(of page: SourcePage, with lines: [TextLine], engine: PageRead.Engine = .cloud) {
        page.lines = lines
        page.text = lines.map(\.text).joined(separator: "\n")
        page.read = PageRead(engine: engine)
        if let source = page.source {
            if source.status == .failed || source.status == .captured, !lines.isEmpty { source.status = .read }
            touch(source)
        }
        save()
    }

    /// Throws away a source the person didn't keep (a capture flow cancelled half way): deleted outright when it
    /// never reached the server, soft-deleted when it did, with its files either way.
    func discardSource(_ source: Source) {
        let folder = PageImageStore.sourceFolder(source.id)
        if source.syncedAt == nil {
            context.delete(source)
        } else {
            source.deletedAt = now
            touch(source)
        }
        FileStore.removeFolder(folder)
        save()
    }

    static func scanTitle(_ date: Date) -> String {
        "Scan, \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    // MARK: - Imports

    /// Reads a deck file (`.apkg`, `.colpkg`, `.csv`, `.tsv`, `.txt`) for its preview, off the main thread.
    func previewImport(of url: URL) async throws -> ImportPreview {
        try await Task.detached(priority: .userInitiated) { try DeckImporter.preview(fileAt: url) }.value
    }

    /// Pasted text (a Quizlet export, or CSV with a header) for its preview.
    func previewImport(text: String, format: DeckFormat? = nil, title: String = "") throws -> ImportPreview {
        try DeckImporter.preview(text: text, format: format, title: title)
    }

    /// Adds a previewed deck to a course: one source for the deck (the original file kept on device when there is
    /// one), and one item per card, active (Anki cards suspended there stay suspended) with Anki's scheduling.
    /// Cards already in the course (same front and back) are skipped. Topics come from decks or a topic column.
    @discardableResult
    func commitImport(_ preview: ImportPreview, to course: Course, title: String? = nil, file: URL? = nil) -> ImportOutcome {
        let label = preview.format.displayName
        let base = (title ?? preview.title).trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceTitle = base.localizedCaseInsensitiveContains(label) ? base : "\(base.isEmpty ? "Imported cards" : base) (\(label))"
        let source = Source(course: course, kind: preview.format.sourceKind, title: sourceTitle, status: .ready, now: now)
        context.insert(source)
        course.sources.append(source)
        if let file {
            let ext = file.pathExtension.isEmpty ? "txt" : file.pathExtension.lowercased()
            source.fileName = try? withFileAccess(file) {
                try FileStore.copy(from: file, folder: PageImageStore.sourceFolder(source.id), name: "deck.\(ext)")
            }
            ImportInbox.release(file)
        }
        func key(_ prompt: String, _ answer: String) -> String {
            "\(prompt.lowercased().trimmingCharacters(in: .whitespaces))\u{1f}\(answer.lowercased().trimmingCharacters(in: .whitespaces))"
        }
        var existing = Set(course.liveItems.map { key($0.cloze?.text ?? $0.prompt, $0.answer) })
        var topicIDs: [String: UUID] = [:]
        var added = 0
        var duplicates = 0
        for card in preview.cards {
            guard existing.insert(key(card.cloze?.text ?? card.front, card.back)).inserted else {
                duplicates += 1
                continue
            }
            var topicID: UUID?
            if let name = card.topic?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                topicID = topicIDs[name.lowercased()] ?? ItemFactory.topic(named: name, in: course, now: now)?.id
                topicIDs[name.lowercased()] = topicID
            }
            let generated = GeneratedItem(id: UUID().uuidString, kind: card.kind, topic: card.topic ?? "", prompt: card.front,
                                          answer: card.back, explanation: card.explanation, cloze: card.cloze)
            let item = ItemFactory.makeItem(from: generated, course: course, topicID: topicID, source: source, page: nil,
                                            origin: preview.format.origin, status: card.suspended ? .suspended : .active,
                                            now: now)
            if let memory = card.memory { item.memory = memory }
            context.insert(item)
            course.items.append(item)
            added += 1
        }
        touch(source)
        touch(course)
        save()
        return ImportOutcome(sourceID: source.id, added: added, duplicates: duplicates)
    }

    // MARK: - Lectures

    /// The record screen's session: the microphone and on-device transcription, or (DEBUG) the scripted demo
    /// when `CRAMLESS_UITEST=1` or `CRAMLESS_FAKE_LECTURE=1`.
    func makeLectureSession(courseID: UUID?, title: String? = nil) -> LectureSession {
        #if DEBUG
        if config.isHarness || TestHarness.value("CRAMLESS_FAKE_LECTURE") == "1" {
            let prefill = Int(TestHarness.value("CRAMLESS_LECTURE_PREFILL") ?? "") ?? 0
            let offset = Double(TestHarness.value("CRAMLESS_LECTURE_ELAPSED") ?? "") ?? 0
            return LectureSession(app: self, courseID: courseID, title: title, ports: .demo(prefill: prefill, startOffset: offset))
        }
        #endif
        return LectureSession(app: self, courseID: courseID, title: title,
                              ports: .system(vocabulary: lectureVocabulary(courseID: courseID)))
    }

    /// The course's own words for the speech engine: topic names, flashcard fronts, short answers and key-idea
    /// terms, most specific first (longer words, then multi-word terms), without repeats, at most 100.
    func lectureVocabulary(courseID: UUID?) -> [String] {
        guard let course = course(courseID) else { return [] }
        var candidates: [String] = course.liveTopics.map(\.name)
        for item in course.liveItems where item.status == .active || item.status == .draft {
            if item.kind == .flashcard { candidates.append(item.prompt) }
            if item.answer.split(separator: " ").count <= 3 { candidates.append(item.answer) }
            for idea in item.keyIdeas { candidates += idea.terms }
            if let cloze = item.cloze { candidates += cloze.answers }
        }
        var seen: Set<String> = []
        let cleaned = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { term in
                let words = term.split(separator: " ")
                return (1...3).contains(words.count) && term.count >= 4 && term.count <= 40
            }
            .filter { seen.insert($0.lowercased()).inserted }
        return Array(cleaned.sorted { a, b in
            let la = a.split(separator: " ").map(\.count).max() ?? 0, lb = b.split(separator: " ").map(\.count).max() ?? 0
            return la != lb ? la > lb : a < b
        }.prefix(LectureVocabulary.limit))
    }

    /// "Lecture 7": one past the course's lectures.
    func nextLectureTitle(courseID: UUID?) -> String {
        let count: Int
        if let course = course(courseID) {
            count = course.liveSources.filter { $0.kind == .lecture }.count
        } else {
            let lecture = SourceKind.lecture.rawValue
            count = fetch(FetchDescriptor<Source>(predicate: #Predicate { $0.kindRaw == lecture && $0.deletedAt == nil && $0.course == nil })).count
        }
        return "Lecture \(count + 1)"
    }

    /// The lecture source, made when recording starts (status `.captured`) so a crash keeps what was recorded.
    @discardableResult
    func startLecture(id: UUID = UUID(), courseID: UUID?, title: String) -> Source {
        let course = course(courseID)
        let source = Source(id: id, course: course, kind: .lecture, title: title, status: .captured, now: now)
        source.fileName = LectureFiles.recording(id)
        context.insert(source)
        course?.sources.append(source)
        touch(source)
        save()
        return source
    }

    /// The transcript and flags so far (every half minute, and on pause), so a crash keeps them.
    func checkpointLecture(_ id: UUID, duration: Double, segments: [TranscriptSegment], flags: [ExamFlag]) {
        guard let source = source(id) else { return }
        source.duration = duration
        source.segments = segments
        source.flags = flags
        touch(source)
        save()
    }

    /// Saves a finished lecture: its audio (`lecture.m4a`), length, transcript and flags. With no transcript yet
    /// it stays `.captured` (the transcript is pending); with one it is `.read`, ready for notes.
    func finishLecture(_ id: UUID, audioFile: String?, duration: Double, segments: [TranscriptSegment], flags: [ExamFlag]) {
        guard let source = source(id) else { return }
        source.fileName = audioFile
        source.duration = duration
        source.segments = segments
        source.flags = flags
        source.status = segments.isEmpty ? .captured : .read
        touch(source)
        save()
    }

    /// Throws a lecture away (Discard on the record screen).
    func discardLecture(_ id: UUID) {
        guard let source = source(id) else { return }
        discardSource(source)
    }

    /// A lecture whose transcript is pending: there is audio but no transcript yet.
    /// What the player plays for this lecture. Nil when its audio isn't on this iPhone (a lecture from another device: audio isn't synced).
    /// The harness plays its seeded lectures, which have no audio, through a silent demo.
    func lectureTrack(for source: Source) -> LecturePlayer.Track? {
        guard source.kind == .lecture else { return nil }
        let segments = source.segments.sorted { $0.start < $1.start }
        let duration = max(source.duration, segments.last?.end ?? 0)
        guard duration > 0 else { return nil }
        #if DEBUG
        if config.isHarness {
            return LecturePlayer.Track(sourceID: source.id, title: source.title, fileName: nil, duration: duration, segments: segments)
        }
        #endif
        guard let name = source.fileName, FileManager.default.fileExists(atPath: FileStore.url(for: name).path) else { return nil }
        return LecturePlayer.Track(sourceID: source.id, title: source.title, fileName: name, duration: duration, segments: segments)
    }

    func isTranscriptPending(_ source: Source) -> Bool {
        source.kind == .lecture && source.segments.isEmpty && source.fileName != nil
            && !LectureJobs.recording.contains(source.id)
    }

    /// Makes a pending transcript from the lecture's recording on this iPhone, installing the language's model
    /// first when it's missing. With `replacing`, a partial transcript (live transcription broke off) is replaced
    /// by one of the whole recording; the person's own flags are kept and phrase flags found again. Returns whether
    /// a transcript was made (false when no model can be had here: the transcript stays pending, and a cloud
    /// transcription is the AI lane's call).
    @discardableResult
    func transcribeLecture(_ id: UUID, replacing: Bool = false, preferredLanguages: [String] = Locale.preferredLanguages) async -> Bool {
        guard let source = source(id), source.kind == .lecture, let file = source.fileName,
              !LectureJobs.recording.contains(id), source.segments.isEmpty || replacing,
              LectureJobs.transcribing.insert(id).inserted else { return false }
        defer { LectureJobs.transcribing.remove(id) }
        guard case .available(let resolved) = await TranscriptionGate.resolve(preferredLanguages: preferredLanguages) else { return false }
        let vocabulary = lectureVocabulary(courseID: source.course?.id)
        let choice = await TranscriptionGate.preferringVocabulary(resolved, vocabulary: vocabulary)
        do {
            if !choice.isInstalled { try await LectureSpeechModels.install(choice) }
            let segments = try await LectureFileTranscriber.transcribe(FileStore.url(for: file), choice: choice,
                                                                       vocabulary: vocabulary)
            guard !segments.isEmpty, source.modelContext != nil, source.segments.isEmpty || replacing else { return false }
            let tapped = source.flags.filter { $0.reason == .tapped }
            source.segments = segments
            source.flags = (tapped + ExamFlagDetector.phraseFlags(in: segments, existing: tapped)).sorted { $0.time < $1.time }
            source.status = .read
            touch(source)
            save()
            return true
        } catch {
            return false
        }
    }

    /// Lectures the app was closed in the middle of (a crash, a force-quit): the audio stream is remuxed into
    /// `lecture.m4a`, its length read back, and what was transcribed before the close is kept. Call once at launch. Returns
    /// what it kept, for the toast that says so (`announceRecoveredLectures`).
    @discardableResult
    func recoverInterruptedLectures() async -> [RecoveredLecture] {
        let lecture = SourceKind.lecture.rawValue
        let captured = SourceStatus.captured.rawValue
        let candidates = fetch(FetchDescriptor<Source>(predicate: #Predicate {
            $0.kindRaw == lecture && $0.statusRaw == captured && $0.deletedAt == nil
        }))
        var recovered: [RecoveredLecture] = []
        for source in candidates where source.fileName?.hasSuffix(LectureFiles.recordingName) == true
            && !LectureJobs.recording.contains(source.id) {
            let id = source.id
            let file = await LectureFiles.finalize(id)
            guard source.modelContext != nil else { continue }
            source.fileName = file
            if let file, let duration = try? await AVURLAsset(url: FileStore.url(for: file)).load(.duration).seconds,
               duration.isFinite, duration > 0 {
                source.duration = duration
            }
            source.status = source.segments.isEmpty ? .captured : .read
            touch(source)
            save()
            if file != nil { recovered.append(RecoveredLecture(id: id, duration: source.duration)) }
        }
        return recovered
    }

    /// Says that lectures cut off by a crash were kept ("Cap kept your lecture up to 41:20.", with Open), once, at launch. Nothing
    /// for a recording under `RecoveredLecture.worthTelling` (a stray tap on record), or while onboarding shows.
    func announceRecoveredLectures(_ lectures: [RecoveredLecture]) {
        guard settings.onboardingCompleted, let toast = RecoveredLecture.toast(for: lectures) else { return }
        if let action = toast.action {
            router.toast(toast.message, systemImage: "checkmark.circle.fill", tone: .success, actionTitle: "Open", action: action)
        } else {
            router.show(Toast(message: toast.message, systemImage: "checkmark.circle.fill", tone: .success, duration: 5))
        }
    }

    // MARK: - Files from other apps

    /// A file opened from another app ("Open in Capling", the share sheet). A PDF opens the capture flow; an Anki
    /// deck or a CSV opens the import sheet (its file waits in `pendingImportFile`); a text file is a deck when its
    /// lines read as cards, and notes to read otherwise; images become a scan. Anything else gets a toast.
    func importFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        do {
            switch ext {
            case "pdf":
                let kept = try ImportInbox.keep(url)
                router.present(.captureFlow(CaptureRequest(input: .pdf(kept), courseID: nil)))
            case "apkg", "colpkg", "csv", "tsv":
                try ImportInbox.keep(url)
                router.present(.importDeck(courseID: nil))
            case "txt", "text", "md":
                let text = try withFileAccess(url) { try DeckImporter.readText(url) }
                if DeckImporter.looksLikeDeck(text) {
                    try ImportInbox.keep(url)
                    router.present(.importDeck(courseID: nil))
                } else {
                    let title = url.deletingPathExtension().lastPathComponent
                    router.present(.captureFlow(CaptureRequest(input: .text(title: title, body: text), courseID: nil)))
                }
            case "jpg", "jpeg", "png", "heic", "heif":
                let data = try withFileAccess(url) { try Data(contentsOf: url) }
                let staged = try PageImageStore.stage(imageData: [data])
                router.present(.captureFlow(CaptureRequest(input: .images(staged), courseID: nil)))
            default:
                throw CaptureError.unsupportedFile(ext)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? CaptureError.unsupportedFile(ext).errorDescription ?? ""
            router.show(Toast(message: .verbatim(message), systemImage: "exclamationmark.triangle.fill", tone: .warning, duration: 5))
        }
    }

    /// The deck file waiting for the import sheet (from "Open in Capling"), if any.
    var pendingImportFile: URL? { ImportInbox.pending }

    /// Call when the import sheet commits or closes.
    func clearPendingImport() { ImportInbox.clear() }
}

/// Lecture work in flight, so a recovery or a transcription never touches a lecture that is busy.
@MainActor
enum LectureJobs {
    /// Sources being recorded right now.
    static var recording: Set<UUID> = []
    /// Sources whose pending transcript is being made.
    static var transcribing: Set<UUID> = []
}
