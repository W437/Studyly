import ImageIO
import SwiftUI

/// One run of the capture flow: reads the material into a source on this iPhone, generates a set with `app.ai`,
/// turns it into drafts, and paces what the processing screen shows.
///
/// The pacing never invents progress. A step is shown only once the work behind it has happened (or while it is
/// happening), and each is held for a minimum time so the eye can follow it: the brackets lock on and a scan sweeps
/// the page while it's read, the key ideas pop in as topics (each marking the line it came from), the questions are
/// counted, the check reports how many match the page, and the first questions land with their page chips. That is
/// the onboarding demo's choreography (`SnapScene`), played on the real page with the real results.
@MainActor
@Observable
final class CaptureRun {
    enum Step: Int, Comparable, CaseIterable, Sendable {
        case reading, ideas, writing, checking, done

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .reading: GenerationPhase.reading.title
            case .ideas: GenerationPhase.findingKeyIdeas.title
            case .writing: GenerationPhase.writingQuestions.title
            case .checking, .done: GenerationPhase.checking.title
            }
        }
    }

    enum Failure: Equatable, Sendable {
        /// No page had text the iPhone was sure of (handwriting, a script it doesn't read): nothing was kept.
        case unreadable
        /// No text at all: a photo or a diagram.
        case noText
        /// Mostly math or chemistry notation, which on-device recognition garbles at full confidence.
        case mathLike
        /// The generator found nothing to ask; its honest note.
        case noQuestions(String?)
        /// Capture failed (a damaged PDF, nothing pasted): a sentence to show.
        case message(String)
    }

    enum Phase: Equatable, Sendable {
        case running
        case review(UUID)
        case failed(Failure)
    }

    struct Card: Identifiable, Equatable, Sendable {
        var id: String
        var prompt: String
        var label: String
    }

    // MARK: What the screen shows (paced)

    private(set) var phase: Phase = .running
    private(set) var step: Step = .reading {
        didSet { if step != oldValue { stepLog.append(step) } }
    }
    /// Every step shown, in order (tests read it).
    @ObservationIgnored private(set) var stepLog: [Step] = [.reading]
    private(set) var locked = false
    private(set) var sweeping = false
    private(set) var sweep: CGFloat = 0
    /// Topic chips shown under "Finding the key ideas".
    private(set) var topics: [String] = []
    /// Line ids highlighted on the page, in the order they were marked.
    private(set) var marked: [String] = []
    private(set) var shownWritten = 0
    /// "14 of 15 match the page", once the check is done.
    private(set) var checkLine: String?
    /// "Part 2 of 2" while a long reading goes to Cloud AI in parts, else nil.
    private(set) var partLine: String?
    /// What this reading takes of the free scans, when it is more than one or more than are left (the pages are known by now).
    private(set) var allowanceLine: LocalizedStringResource?
    /// With no questions to show: what would write some (Cloud AI, when consent is what is missing). The problem screen
    /// offers it.
    private(set) var noQuestionsSuggestion: AISuggestion?
    /// The first questions, landing with their page chips.
    private(set) var cards: [Card] = []
    /// The reading step's live line while a reading of several pages runs: "Page 2 of 5", "5 pages read". Nil otherwise.
    private(set) var readingDetail: String?
    /// Who is writing the questions: what the router expects when the run starts, then what the generator reports.
    private(set) var origin: ItemOrigin = .rules
    private(set) var preview: CapturePagePreview?
    private(set) var pageCount: Int
    /// The run's own announcement for VoiceOver, changed at each step.
    private(set) var announcement = ""

    // MARK: Work (real)

    let request: CaptureRequest
    private(set) var sourceID: UUID?
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let regenerating: UUID?
    @ObservationIgnored private let skipMathGate: Bool
    @ObservationIgnored private let reduceMotion: Bool
    @ObservationIgnored private var captured = false
    @ObservationIgnored private var latest: GenerationProgress?
    @ObservationIgnored private var outcome: GenerationOutcome?
    @ObservationIgnored private var draftsReady = false
    /// A set written again came out weaker than the questions in review (Cloud AI didn't answer): they stay, and the review says so.
    @ObservationIgnored private var keptEarlier = false
    @ObservationIgnored private var failure: Failure?
    @ObservationIgnored private var abandoned = false
    /// The work has returned (finished, failed or thrown away).
    @ObservationIgnored private var workDone = false
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var display: Task<Void, Never>?
    /// DEBUG: where the display stops (a frame to screenshot), or `.done` with `fastForward` to go straight to review.
    @ObservationIgnored var holdAt: Step?
    @ObservationIgnored var fastForward = false
    /// Multiplies every pause of the display (tests run at 0).
    @ObservationIgnored var pace: Double = 1

    /// `regenerating`: write the set again for a source that is already read (after Cloud AI was allowed, or a
    /// better read of the page); its drafts are replaced.
    init(app: AppModel, request: CaptureRequest, regenerating: UUID? = nil, skipMathGate: Bool = false,
         reduceMotion: Bool = false) {
        self.app = app
        self.request = request
        self.regenerating = regenerating
        self.skipMathGate = skipMathGate
        self.reduceMotion = reduceMotion
        self.sourceID = regenerating
        switch request.input {
        case .images(let paths): pageCount = paths.count
        case .sample, .text: pageCount = 1
        case .pdf: pageCount = 0
        }
        // Cloud AI writes this set if the router would send it there now (it says so from the start, rather than changing its mind
        // once the first progress arrives); the generator's own report replaces the guess.
        if AIRouting.route(app.ai.routeContext(.generate)).usesCloud { origin = .cloud }
        preview = CapturePagePreview(input: request.input)
        if let regenerating, let source = app.source(regenerating) {
            preview = CapturePagePreview(source: source) ?? preview
            pageCount = source.pages.count
        }
    }

    /// Who writes the questions, said once under the title: "With Cloud AI", "On your iPhone".
    var subtitle: String {
        origin == .cloud ? String(localized: "With Cloud AI") : String(localized: "On your iPhone")
    }

    /// "14 questions", counted as they are written; nil before the first.
    var writtenDetail: String? {
        shownWritten > 0 ? CLFormat.count(shownWritten, "question") : nil
    }

    func start() {
        guard worker == nil else { return }
        worker = Task { await work() }
        display = Task { await play() }
    }

    /// The person left before the end: the source, its drafts and anything made for them are thrown away. Reading
    /// that's under way finishes its current page first, then its result is thrown away too.
    func discard() {
        abandoned = true
        display?.cancel()
        // Reading still under way: `work()` throws its result away when it returns.
        guard captured || workDone, let id = sourceID, let app else { return }
        worker?.cancel()
        app.discardDrafts(sourceID: id, keepSource: keepsSource)
        sourceID = nil
    }

    /// The source was in the library before this run (questions added for the rest of it), so throwing the run away throws away
    /// its drafts only.
    private var keepsSource: Bool { request.restOf != nil }

    // MARK: The work

    private func work() async {
        defer { workDone = true }
        guard let app else { return }
        do {
            let source: Source
            if let regenerating, let existing = app.source(regenerating) {
                source = existing
            } else {
                source = try await app.createSource(from: request) { [weak self] progress in self?.read(progress) }
            }
            sourceID = source.id
            if abandoned {
                app.discardDrafts(sourceID: source.id, keepSource: keepsSource)
                return
            }
            // The read page replaces the preview: its lines (with boxes on a photo), its printed number, and the photo
            // where it now lives (staged photos move into the source's folder).
            if let fresh = CapturePagePreview(source: source) { preview = fresh }
            pageCount = source.pages.count
            if source.status == .failed {
                let readable = source.pages.compactMap(\.read)
                failure = readable.allSatisfy({ $0.issue == .noText }) && !readable.isEmpty ? .noText : .unreadable
                return
            }
            // A photo that is mostly notation stops here; a PDF whose text layer lost its formulas does not (its words are
            // right, and the review says the formulas may be missing).
            if !skipMathGate, source.pages.contains(where: { $0.wantsBetterRead && $0.read?.issue == .mathLike }) {
                failure = .mathLike
                return
            }
            captured = true
            let input: GenerationInput
            if let plan = request.rest {
                // Only the part decided when the person asked, as pages of just those lines. It is not worked out again here: the
                // source may be waiting on this very set's drafts (a rewrite with Cloud AI), which keeps it out of the coverage count.
                guard let rest = app.generationInput(for: plan, of: source) else {
                    failure = .noQuestions(String(localized: "Your questions already cover everything in this one."))
                    return
                }
                input = rest
                pageCount = rest.pages.count
            } else {
                input = app.generationInput(for: source)
            }
            allowanceLine = app.ai.readingAllowance(pageWords: input.pages.map { GenerationPlan.wordCount(of: $0) })
            for await update in app.ai.generateSet(input) {
                if abandoned || Task.isCancelled { break }
                switch update {
                case .progress(let progress):
                    latest = progress
                    origin = progress.origin
                    partLine = progress.parts > 1 ? "Part \(progress.part) of \(progress.parts)" : nil
                case .finished(let finished):
                    outcome = finished
                    origin = finished.origin
                }
            }
            guard !abandoned, !Task.isCancelled, let outcome else { return }
            // Written again, but by a lower tier than the set in review (Cloud AI couldn't be reached and this iPhone's model or the rules
            // wrote this): the questions already there are kept, not deleted for a weaker set, even when this one has none to show.
            if regenerating != nil, app.keepsEarlierDrafts(over: outcome, source: source) {
                app.noteEarlierDraftsKept(over: outcome, source: source)
                keptEarlier = true
                draftsReady = true
                return
            }
            guard !outcome.items.isEmpty else {
                noQuestionsSuggestion = outcome.suggestion
                failure = .noQuestions(outcome.note)
                return
            }
            app.makeDrafts(from: outcome, source: source, course: regenerating == nil ? app.course(request.courseID) : nil, topicID: request.topicID)
            // The pages of a rest are used up once its drafts exist, whatever the person then keeps: the next tap moves on. Only the
            // pages that were read: a part that failed, or never started (the free scans ran out), leaves its pages for the next tap.
            if let plan = request.rest { app.noteRestRun(plan, readPages: outcome.pagesRead) }
            draftsReady = true
        } catch is CancellationError {
        } catch {
            failure = .message((error as? LocalizedError)?.errorDescription ?? "Something went wrong reading this. Try again.")
        }
    }

    private func read(_ progress: CaptureProgress) {
        guard progress.total > 1 else { return }
        switch progress.stage {
        case .preparing: break
        case .reading: readingDetail = String(localized: "Page \(min(progress.total, progress.completed + 1)) of \(progress.total)")
        case .saving: readingDetail = String(localized: "\(progress.total) pages read")
        }
        pageCount = max(pageCount, progress.total)
    }

    // MARK: The display

    private func play() async {
        do {
            if fastForward {
                try await waitFor { self.draftsReady || self.failure != nil }
                return jumpToReview()
            }
            // Reading: the brackets lock on, then a scan sweeps the page until it has been read.
            say(.reading)
            try await beat(reduceMotion ? 120 : 450)
            withAnimation(CLMotion.calm) { locked = true }
            try await beat(reduceMotion ? 200 : 650)
            repeat {
                if reduceMotion { try await beat(300) } else { try await sweepOnce() }
                if failure != nil { return showFailure() }
            } while !(captured && latest != nil) && !draftsReady
            if holdAt == .reading { return }

            // Finding the key ideas: each topic pops in and marks the line it came from.
            say(.ideas)
            withAnimation(CLMotion.settle) { step = .ideas }
            try await waitFor { self.topicsKnown || self.failure != nil }
            if failure != nil { return showFailure() }
            for topic in topicNames.prefix(6) {
                withAnimation(CLMotion.pop) { topics.append(topic) }
                if let line = line(for: topic) { withAnimation(CLMotion.calm) { marked.append(line) } }
                try await beat(reduceMotion ? 60 : 260)
            }
            try await beat(reduceMotion ? 100 : 300)
            if holdAt == .ideas { return }

            // Writing questions: counted as they were written.
            say(.writing)
            withAnimation(CLMotion.settle) { step = .writing }
            try await waitFor { (self.latest?.written ?? 0) > 0 || self.outcome != nil || self.failure != nil }
            if failure != nil { return showFailure() }
            let written = max(latest?.written ?? 0, outcome.map { $0.items.count + $0.dropped.count } ?? 0)
            if written > 0 {
                let pause = reduceMotion ? 0 : max(30, min(80, 1100 / written))
                for n in 1...written {
                    shownWritten = n
                    if pause > 0 { try await beat(pause) }
                }
            }
            try await beat(reduceMotion ? 100 : 250)
            if holdAt == .writing { return }

            // Checking each one against the page, so nothing made up gets through.
            say(.checking)
            withAnimation(CLMotion.settle) { step = .checking }
            let entered = ContinuousClock.now
            try await waitFor { self.draftsReady || self.failure != nil }
            if failure != nil { return showFailure() }
            if keptEarlier { return showKeptEarlier() }
            let wait = (reduceMotion ? Duration.milliseconds(400) : .milliseconds(900)) * pace - entered.duration(to: .now)
            if wait > .zero { try await Task.sleep(for: wait) }
            if let outcome {
                let total = max(outcome.items.count + outcome.dropped.count, shownWritten)
                withAnimation(CLMotion.fade) { checkLine = "\(outcome.items.count) of \(total) match the page" }
            }
            if holdAt == .checking { return }
            try await land()
            if holdAt == .done { return }
            try await beat(600)
            guard let sourceID else { return }
            withAnimation(CLMotion.settle) { phase = .review(sourceID) }
        } catch {
            // Cancelled: the person left.
        }
    }

    /// The set is ready: the first questions land with their page chips, one after another, each marking the line it
    /// came from. Each lands in its own moment (one change per beat), so no entrance is lost to a shared transaction.
    private func land() async throws {
        guard failure == nil else { return showFailure() }
        guard let outcome else { return }
        withAnimation(CLMotion.settle) { step = .done }
        CLHaptics.success()
        announcement = String(localized: "Your questions are ready: \(CLFormat.count(outcome.items.count, "question")).")
        for card in firstCards(outcome) {
            withAnimation(CLMotion.pop) { cards.append(card.card) }
            if let anchor = card.anchor { withAnimation(CLMotion.calm) { marked.append(anchor) } }
            try await beat(reduceMotion ? 1 : 170)
        }
    }

    /// The set written again was weaker than the one in review, which stays: no cards land (the review's note says why).
    private func showKeptEarlier() {
        guard let sourceID else { return }
        announcement = "Your earlier questions are kept."
        withAnimation(CLMotion.settle) {
            step = .done
            phase = .review(sourceID)
        }
    }

    /// DEBUG fast-forward: the finished frame at once, then the review.
    private func jumpToReview() {
        guard failure == nil else { return showFailure() }
        if keptEarlier, let sourceID {
            step = .done
            phase = .review(sourceID)
            return
        }
        guard let outcome, let sourceID else { return }
        step = .done
        for card in firstCards(outcome) {
            cards.append(card.card)
            if let anchor = card.anchor { marked.append(anchor) }
        }
        phase = .review(sourceID)
    }

    /// The first three questions as cards, with the line each came from (when it can be marked on the page).
    private func firstCards(_ outcome: GenerationOutcome) -> [(card: Card, anchor: String?)] {
        let label = preview.map { "p. \($0.label)" } ?? "Source"
        var used = Set(marked)
        return outcome.items.prefix(3).map { item in
            let anchor = item.anchors.first { !used.contains($0) && (preview?.canMark($0) ?? false) }
            if let anchor { used.insert(anchor) }
            return (Card(id: item.id, prompt: item.prompt, label: label), anchor)
        }
    }

    private func showFailure() {
        guard let failure else { return }
        withAnimation(CLMotion.settle) { phase = .failed(failure) }
    }

    private func sweepOnce() async throws {
        withoutAnimation { sweep = 0 }
        withAnimation(CLMotion.fade) { sweeping = true }
        withAnimation(CLMotion.fill) { sweep = 1 }
        try await beat(1150)
        withAnimation(CLMotion.fade) { sweeping = false }
        try await beat(260)
    }

    private func beat(_ milliseconds: Int) async throws {
        // At least a moment, so a loop waiting on the work always lets the work run.
        try await nap(max(1, Int(Double(milliseconds) * pace)))
    }

    private func say(_ step: Step) {
        announcement = step.title
    }

    private func waitFor(_ condition: @escaping () -> Bool) async throws {
        while !condition() { try await nap(60) }
    }

    // MARK: Topics and lines

    private var topicsKnown: Bool {
        !(latest?.topics.isEmpty ?? true) || outcome != nil || (latest?.phase ?? .reading) > .writingQuestions
    }

    private var topicNames: [String] {
        if let outcome, !outcome.topics.isEmpty { return outcome.topics.map(\.name) }
        if let topics = latest?.topics, !topics.isEmpty { return topics }
        var names: [String] = []
        for item in outcome?.items ?? [] where !item.topic.isEmpty && !names.contains(item.topic) { names.append(item.topic) }
        return names
    }

    /// The line a topic came from: its first question's first line when the questions are known, else the first
    /// unmarked line with the topic's most telling word.
    private func line(for topic: String) -> String? {
        guard let preview else { return nil }
        if let outcome, let item = outcome.items.first(where: { $0.topic == topic }),
           let anchor = item.anchors.first(where: { !marked.contains($0) && preview.canMark($0) }) {
            return anchor
        }
        let stop: Set<String> = ["what", "when", "where", "which", "with", "from", "that", "this", "their", "about", "matters", "why"]
        let words = topic.lowercased().split { !$0.isLetter }.map(String.init)
            .filter { $0.count >= 4 && !stop.contains($0) }
            .sorted { $0.count > $1.count }
        for word in words {
            if let line = preview.lines.first(where: { !marked.contains($0.id) && preview.canMark($0.id) && $0.text.lowercased().contains(word) }) {
                return line.id
            }
        }
        return nil
    }
}

/// What the processing screen draws of the material: the first page's photo with its recognised lines, or the text
/// itself on a sheet of paper (pasted text, a PDF's text layer).
struct CapturePagePreview: Equatable, Sendable {
    /// Relative to the file store, or an absolute path (the bundled sample before it's copied in).
    var imagePath: String?
    /// The page's pixel size (its shape); zero when unknown.
    var size: CGSize
    var lines: [TextLine]
    /// What the page calls itself: "87".
    var label: String

    var aspect: CGFloat { size.height > 0 ? size.width / size.height : 2.0 / 3.0 }

    /// Lines can be marked when they're drawn: boxed lines on a photo, any of the first lines on paper.
    func canMark(_ id: String) -> Bool {
        guard let line = lines.first(where: { $0.id == id }) else { return false }
        if imagePath != nil { return line.box != nil }
        return lines.prefix(CapturePagePreview.paperLines).contains { $0.id == line.id }
    }

    static let paperLines = 16

    /// Before anything is read: the picked photo, the sample, or the pasted text.
    init?(input: CaptureRequest.Input) {
        switch input {
        case .images(let paths):
            guard let first = paths.first else { return nil }
            imagePath = first
            size = CapturePagePreview.pixelSize(FileStore.url(for: first)) ?? .zero
            lines = []
            label = "1"
        case .sample:
            let file = SamplePage.ocr()
            imagePath = SamplePage.imageURL?.path
            size = CGSize(width: file?.width ?? 1200, height: file?.height ?? 1800)
            lines = file?.lines ?? []
            label = SamplePage.pageLabel
        case .text(_, let body):
            let pages = TextPaginator.pages(from: body)
            guard let first = pages.first else { return nil }
            imagePath = nil
            size = .zero
            lines = first.lines
            label = first.label
        case .pdf:
            return nil
        }
    }

    /// From a read source's first page.
    init?(source: Source) {
        guard let page = source.sortedPages.first, page.modelContext != nil else { return nil }
        imagePath = page.imageFileName
        size = CGSize(width: page.width, height: page.height)
        lines = page.lines
        label = page.label
        if imagePath != nil, size.width <= 0, let path = imagePath {
            size = CapturePagePreview.pixelSize(FileStore.url(for: path)) ?? .zero
        }
    }

    /// Reads an image's pixel size from its header, without decoding it.
    static func pixelSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}
