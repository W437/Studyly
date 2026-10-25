import SwiftUI

/// The capture flow cover: the processing screen, then the draft review in place, or an honest screen about what
/// went wrong (a page it couldn't read, a page of math, no text, no questions) with a way forward.
///
/// DEBUG hooks (with `CRAMLESS_ROUTE=captureFlow`, which runs the sample page):
/// - `CRAMLESS_CAPTURE_PHASE=reading|ideas|writing|checking|done` holds the processing screen once it reaches that
///   step; `review` (or `CRAMLESS_ROUTE=review`) goes straight to the review once the set is ready;
///   `error:unreadable|notext|math|empty|pdf` shows that problem screen.
/// - `CRAMLESS_CAPTURE_INPUT=photo` runs the flow on the sample page as a photo, with real text recognition;
///   `text` runs it on pasted notes.
struct CaptureFlowView: View {
    let request: CaptureRequest

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var run: CaptureRun?
    @State private var debugFailure: CaptureRun.Failure?
    @State private var readingWithCloud = false
    @State private var cloudNote: String?

    var body: some View {
        ZStack {
            if let failure = debugFailure ?? currentFailure {
                CaptureProblemView(failure: failure, input: run?.request.input ?? request.input,
                                   preview: run?.preview ?? CapturePagePreview(input: request.input),
                                   readingWithCloud: readingWithCloud, cloudNote: cloudNote,
                                   tryAnother: tryAnother, readWithCloud: { Task { await readWithCloud() } },
                                   useAnyway: useAnyway, makeCards: makeCards, close: close)
                    .transition(.opacity)
            } else if case .review(let id) = run?.phase {
                DraftReviewView(sourceID: id, isOnboarding: request.isOnboarding, onFinish: finished, onRewrite: rewrite)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            } else if let run {
                CaptureProcessingView(run: run, onClose: close)
                    .transition(.opacity)
            } else {
                CLColor.background.ignoresSafeArea()
            }
        }
        .animation(CLMotion.settle, value: phaseKey)
        .captureDebugCanvas()
        .task { start() }
    }

    private var currentFailure: CaptureRun.Failure? {
        if case .failed(let failure) = run?.phase { return failure }
        return nil
    }

    private var phaseKey: String {
        if debugFailure != nil || currentFailure != nil { return "failed" }
        if case .review(let id) = run?.phase { return "review-\(id)" }
        return "run-\(run.map { ObjectIdentifier($0).hashValue } ?? 0)"
    }

    // MARK: Running

    private func start(regenerating: UUID? = nil, skipMathGate: Bool = false) {
        guard run == nil || regenerating != nil else { return }
        var input = request
        #if DEBUG
        if regenerating == nil, let staged = debugInput() { input.input = staged }
        let hook = TestHarness.value("CRAMLESS_CAPTURE_PHASE") ?? (TestHarness.value("CRAMLESS_ROUTE") == "review" ? "review" : nil)
        if regenerating == nil, let hook, hook.hasPrefix("error") {
            debugFailure = Self.debugFailure(hook)
            return
        }
        #endif
        let next = CaptureRun(app: app, request: input, regenerating: regenerating, skipMathGate: skipMathGate,
                              reduceMotion: reduceMotion)
        #if DEBUG
        switch hook {
        case "reading": next.holdAt = .reading
        case "ideas": next.holdAt = .ideas
        case "writing": next.holdAt = .writing
        case "checking": next.holdAt = .checking
        case "done": next.holdAt = .done
        case "review": next.fastForward = regenerating == nil
        default: break
        }
        #endif
        cloudNote = nil
        run = next
        next.start()
    }

    /// Cloud AI was allowed from the review: the same page, written again.
    private func rewrite() {
        guard let id = run?.sourceID else { return }
        start(regenerating: id)
    }

    private func useAnyway() {
        guard let id = run?.sourceID else { return }
        CLHaptics.tap()
        start(regenerating: id, skipMathGate: true)
    }

    /// Reads the pages the iPhone couldn't (handwriting, math) with Cloud AI from their photos, then writes the set.
    /// Offered only while page photos may be sent; the router reads that switch again before anything goes.
    private func readWithCloud() async {
        guard let id = run?.sourceID else { return }
        CLHaptics.tap()
        readingWithCloud = true
        cloudNote = nil
        let result = await app.readPagesWithCloud(sourceID: id)
        readingWithCloud = false
        switch result {
        case .read: start(regenerating: id, skipMathGate: true)
        case .notAllowed(let suggestion): if let suggestion { app.router.present(suggestion.sheet) }
        case .failed(let message): cloudNote = message
        case .nothingFound: cloudNote = "Cloud AI couldn't find text on this page either."
        }
    }

    // MARK: Leaving

    private func finished(_ courseID: UUID?) {
        if request.isOnboarding {
            OnboardingCaptureBridge.onDone?(courseID)
        }
        app.router.dismissCover()
    }

    private func close() {
        CLHaptics.tap()
        run?.discard()
        if run == nil, case .images(let paths) = request.input { PageImageStore.discard(paths) }
        app.router.dismissCover()
    }

    /// Another go at the same kind of material: the scanner again, the file picker, or the paste sheet.
    private func tryAnother() {
        CLHaptics.tap()
        run?.discard()
        switch request.input {
        case .images, .sample:
            app.router.present(.scanner(courseID: request.courseID, isOnboarding: request.isOnboarding))
        case .pdf:
            reopen(.capture(courseID: request.courseID))
        case .text:
            reopen(.paste(courseID: request.courseID))
        }
    }

    private func makeCards() {
        CLHaptics.tap()
        run?.discard()
        reopen(.newItem(courseID: request.courseID ?? app.defaultCourseID()))
    }

    /// Closes the cover, then raises a sheet from the tabs once the cover is gone.
    private func reopen(_ sheet: AppSheet) {
        let router = app.router
        router.dismissCover()
        Task { @MainActor in
            try? await nap(500)
            router.present(sheet)
        }
    }

    #if DEBUG
    private func debugInput() -> CaptureRequest.Input? {
        switch TestHarness.value("CRAMLESS_CAPTURE_INPUT") {
        case "photo":
            guard let url = SamplePage.imageURL, let data = try? Data(contentsOf: url),
                  let paths = try? PageImageStore.stage(imageData: [data]) else { return nil }
            return .images(paths)
        case "text":
            return .text(title: "Cell division notes", body: DebugCapture.notes)
        default:
            return nil
        }
    }

    static func debugFailure(_ hook: String) -> CaptureRun.Failure {
        switch hook.split(separator: ":").last.map(String.init) {
        case "notext": .noText
        case "math": .mathLike
        case "empty": .noQuestions("The offline rules couldn't find questions on this page.")
        case "pdf": .message(CaptureError.pdfLocked.errorDescription ?? "")
        default: .unreadable
        }
    }
    #endif
}

/// Hands a capture flow's result back to onboarding when the flow ran as a cover (`CaptureRequest.isOnboarding`).
/// `OnboardingFirstSetStep` sets it while it's on screen.
@MainActor
enum OnboardingCaptureBridge {
    static var onDone: ((UUID?) -> Void)?
}

#if DEBUG
enum DebugCapture {
    static let notes = """
    Cell division. Cells divide by mitosis so an organism can grow, replace damaged cells and heal. Mitosis makes two \
    daughter cells that are genetically identical to the parent cell. It has four phases: prophase, metaphase, \
    anaphase and telophase. In prophase the chromosomes condense and the nuclear envelope breaks down. In metaphase \
    the chromosomes line up at the equator of the cell. In anaphase the sister chromatids are pulled to opposite \
    poles. In telophase new nuclear envelopes form around each set of chromosomes. After mitosis, cytokinesis \
    divides the cytoplasm into two cells.
    """
}
#endif

// MARK: - Problems

/// What went wrong, in words the person can act on, with the way forward first. A cloud read of the photo is
/// offered only while page photos may be sent; otherwise the screen says what would allow it.
struct CaptureProblemView: View {
    let failure: CaptureRun.Failure
    let input: CaptureRequest.Input
    let preview: CapturePagePreview?
    let readingWithCloud: Bool
    let cloudNote: String?
    let tryAnother: () -> Void
    let readWithCloud: () -> Void
    let useAnyway: () -> Void
    let makeCards: () -> Void
    let close: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                illustration
                    .padding(.top, 26)
                Text(words.title)
                    .clFont(.title2)
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 26)
                Text(words.body)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                if isPageProblem {
                    Label("Flat, in good light, with the whole page in the frame", systemImage: "camera.viewfinder")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                }
                if showsCloudHint {
                    VStack(spacing: 6) {
                        Text("Cloud AI can read handwriting and math from the photo, once page photos are allowed to go to it.")
                            .clFont(.footnote)
                            .foregroundStyle(CLColor.ink2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            CLHaptics.tap()
                            app.router.present(.consent(.photos))
                        } label: {
                            Text("Allow page photos")
                                .clFont(.subheadlineEmphasis)
                                .foregroundStyle(CLColor.skyInk)
                                .frame(minHeight: CLMetrics.minHitTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(CLColor.skySoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.top, 22)
                }
                if let cloudNote {
                    Label(cloudNote, systemImage: "exclamationmark.triangle.fill")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.roseInk)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, CLSpace.gutter + 8)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .clScreenBackground()
        .safeAreaBar(edge: .top) {
            HStack {
                CaptureGlassButton(systemImage: "xmark", label: "Close", action: close)
                    .padding(.leading, 12)
                Spacer()
            }
            .frame(minHeight: 50)
        }
        .safeAreaBar(edge: .bottom) { actions }
    }

    private var isPageProblem: Bool {
        switch failure {
        case .unreadable, .noText, .mathLike: hasPhoto
        default: false
        }
    }

    private var hasPhoto: Bool {
        switch input {
        case .images, .sample, .pdf: preview?.imagePath != nil
        case .text: false
        }
    }

    /// Cloud AI could read this photo, and the person may send it now.
    private var canReadWithCloud: Bool {
        isPageProblem && app.ai.cloudAvailableInThisBuild && AIConsent.photosGranted(app.settings)
    }

    /// Cloud AI could read this photo, but page photos aren't allowed to go yet.
    private var showsCloudHint: Bool {
        isPageProblem && app.ai.cloudAvailableInThisBuild && !AIConsent.photosGranted(app.settings)
            && app.settings.ageBand != .under13
    }

    private var words: (title: String, body: String, symbol: String) {
        switch failure {
        case .unreadable:
            ("We couldn't read this page",
             "Your iPhone wasn't sure of the writing on this photo, so it kept nothing rather than guess. Handwriting and some alphabets are hard for it.",
             "text.magnifyingglass")
        case .noText:
            ("There's no text on this page",
             "It looks like a picture or a diagram without words, and questions need words to come from.",
             "photo")
        case .mathLike:
            ("This page is mostly math",
             "Text recognition on the iPhone often garbles equations, so questions written from this page could be wrong.",
             "function")
        case .noQuestions(let note):
            ("No questions this time",
             note ?? "There wasn't enough on this page to ask about. A page that explains something works best.",
             "questionmark.bubble")
        case .message(let message):
            ("That didn't work", message, "exclamationmark.triangle")
        }
    }

    @ViewBuilder private var illustration: some View {
        if let preview, let path = preview.imagePath, isPageProblem {
            PageImageView(fileName: path, aspect: preview.aspect)
                .frame(width: 118)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: CLColor.night.opacity(0.18), radius: 14, y: 8)
                .rotationEffect(.degrees(-3))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: words.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CLColor.onFill)
                        .frame(width: 46, height: 46)
                        .background(CLColor.sun, in: Circle())
                        .overlay(Circle().strokeBorder(CLColor.background, lineWidth: 4))
                        .offset(x: 18, y: 14)
                }
                .accessibilityHidden(true)
        } else {
            CapView(pose: .study, size: 132)
        }
    }

    private var tryAnotherTitle: String {
        switch input {
        case .images, .sample: "Try another photo"
        case .pdf: "Choose another file"
        case .text: "Edit the text"
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if canReadWithCloud {
                Button(action: readWithCloud) {
                    ZStack {
                        Text("Read it with Cloud AI").opacity(readingWithCloud ? 0 : 1)
                        if readingWithCloud { ProgressView().tint(CLColor.onFill) }
                    }
                }
                .buttonStyle(.cl(.primary))
                .disabled(readingWithCloud)
                Button(tryAnotherTitle, action: tryAnother)
                    .buttonStyle(.cl(.soft))
            } else {
                Button(tryAnotherTitle, action: tryAnother)
                    .buttonStyle(.cl(.primary))
            }
            switch failure {
            case .mathLike:
                Button("Use this page anyway", action: useAnyway)
                    .buttonStyle(.cl(.ghost, size: .medium))
            case .noQuestions:
                Button("Make cards yourself", action: makeCards)
                    .buttonStyle(.cl(.ghost, size: .medium))
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
