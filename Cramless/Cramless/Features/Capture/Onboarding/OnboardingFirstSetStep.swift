import PhotosUI
import SwiftUI

/// Onboarding's first step after the welcome, "Snap a page. Get questions.": scan a page (a photo of one where the scanner isn't
/// available) or use the sample page, then the same processing as the app's capture flow, then the review in onboarding mode, which
/// asks which class it is for. The sample page is asked nothing: its set files under a course named "Sample", and no exam is made
/// from it. `onDone` gets the course the set went to and whether it was the sample.
///
/// The step lives on onboarding's navigation stack; while the set is being made and reviewed it hides the bar and
/// shows the full-screen processing and review, with their own way back.
///
/// DEBUG: shown through `CRAMLESS_ROUTE=scanner` with `CRAMLESS_FIRSTSET=choose|processing|review` (`ScannerFlowView`; inside
/// onboarding, `CRAMLESS_ROUTE=onboarding:1` opens it on the chooser); `CRAMLESS_CAPTURE_PHASE` holds the processing as in the
/// capture flow. The set is the sample page's; `CRAMLESS_CAPTURE_INPUT=text` makes it from typed notes instead (a real page's path,
/// with the class card).
struct OnboardingFirstSetStep: View {
    let onDone: (OnboardingFirstSet) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var run: CaptureRun?
    @State private var scanning = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var preparing = false
    @State private var problem: String?
    @State private var readingWithCloud = false
    @State private var cloudNote: String?
    @State private var debugStarted = false
    #if DEBUG
    @Environment(\.firstSetDebugStage) private var debugStage
    #endif

    var body: some View {
        ZStack {
            if let run {
                switch run.phase {
                case .running:
                    CaptureProcessingView(run: run, title: "Making your first set", onClose: startOver)
                        .transition(.opacity)
                case .review(let id):
                    DraftReviewView(sourceID: id, isOnboarding: true, onFinish: finished,
                                    onRewrite: { rewrite(id) }, onStartOver: { withAnimation(CLMotion.settle) { self.run = nil } },
                                    fixedCourseName: isSample ? Self.sampleCourseName : nil)
                        .transition(.move(edge: .bottom))
                    .zIndex(1)
                case .failed(let failure):
                    CaptureProblemView(failure: failure, input: run.request.input, preview: run.preview,
                                       readingWithCloud: readingWithCloud, cloudNote: cloudNote,
                                       tryAnother: startOver, readWithCloud: { Task { await readWithCloud() } },
                                       useAnyway: { if let id = run.sourceID { begin(run.request.input, regenerating: id, skipMath: true) } },
                                       makeCards: startOver, close: startOver)
                        .transition(.opacity)
                }
            } else {
                chooser
                    .transition(.opacity)
            }
        }
        .animation(CLMotion.settle, value: phaseKey)
        .navigationBarBackButtonHidden(run != nil)
        .toolbar(run != nil ? .hidden : .automatic, for: .navigationBar)
        .fullScreenCover(isPresented: $scanning) {
            DocumentScannerView { outcome in
                scanning = false
                switch outcome {
                case .pages(let paths): begin(.images(paths))
                case .cancelled: break
                case .failed(let message): problem = message
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await stage(items) }
        }
        .onAppear {
            OnboardingCaptureBridge.onDone = { onDone(OnboardingFirstSet(courseID: $0, isSample: false)) }
            #if DEBUG
            guard !debugStarted, let debugStage, debugStage != "choose" else { return }
            debugStarted = true
            // `CRAMLESS_CAPTURE_INPUT=text`: typed notes stand in for a real page (the review then asks which class it is for).
            begin(TestHarness.value("CRAMLESS_CAPTURE_INPUT") == "text"
                  ? .text(title: "Cell division notes", body: DebugCapture.notes) : .sample)
            #endif
        }
        .onDisappear { OnboardingCaptureBridge.onDone = nil }
    }

    /// The sample page's set goes to a course of this name (its subject would be a made-up class).
    static var sampleCourseName: String { String(localized: "Sample") }

    /// The set being made is the bundled sample page.
    private var isSample: Bool {
        if case .sample = run?.request.input { return true }
        return false
    }

    private var phaseKey: String {
        guard let run else { return "choose" }
        switch run.phase {
        case .running: return "run-\(ObjectIdentifier(run).hashValue)"
        case .review: return "review"
        case .failed: return "failed"
        }
    }

    // MARK: Choosing a page

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Snap a page. Get questions.")
                    .clFont(.brandTitle(30))
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Your notes, a textbook or a handout. It takes about 20 seconds.")
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                if ScannerSupport.canScan {
                    Button {
                        CLHaptics.tap()
                        scanning = true
                    } label: {
                        heroCard(symbol: "camera.fill", title: "Scan a page",
                                 subtitle: "Point your camera at the page")
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 24)
                } else {
                    PhotosPicker(selection: $picked, maxSelectionCount: 5, selectionBehavior: .ordered, matching: .images) {
                        heroCard(symbol: "photo.on.rectangle.angled", title: "Choose a photo of a page",
                                 subtitle: "From your photo library. The camera scanner isn't available here.")
                    }
                    .buttonStyle(.pressable)
                    .disabled(preparing)
                    .padding(.top, 24)
                }

                CLList {
                    Button {
                        CLHaptics.tap()
                        begin(.sample)
                    } label: {
                        CaptureOptionRow(systemImage: "book.pages", tint: .sky, title: "Use our sample page",
                                         subtitle: "A biology page about mitosis")
                    }
                    .buttonStyle(.pressable)
                    if ScannerSupport.canScan {
                        PhotosPicker(selection: $picked, maxSelectionCount: 5, selectionBehavior: .ordered, matching: .images) {
                            CaptureOptionRow(systemImage: "photo.on.rectangle.angled", tint: .tangerine,
                                             title: "Choose photos instead", subtitle: "Pages you've already snapped")
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .disabled(preparing)
                .padding(.top, 16)

                if preparing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Getting your photo ready…").clFont(.footnote).foregroundStyle(CLColor.ink2)
                    }
                    .padding(.top, 14)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.roseInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
                Label("Your page stays on this iPhone unless you turn on Cloud AI or sign in.", systemImage: "lock")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
                    .opacity(app.ai.hasCloudConsent ? 0 : 1)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .clScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heroCard(symbol: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CLColor.onFill)
                    .frame(width: 50, height: 50)
                    .background(CLColor.tangerine, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CLColor.ink)
                    .accessibilityHidden(true)
            }
            Text(title)
                .clFont(.title3)
                .foregroundStyle(CLColor.ink)
                .padding(.top, 16)
            Text(subtitle)
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .clNightCard(padding: 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Running

    private func begin(_ input: CaptureRequest.Input, regenerating: UUID? = nil, skipMath: Bool = false) {
        problem = nil
        cloudNote = nil
        let next = CaptureRun(app: app, request: CaptureRequest(input: input, courseID: nil, isOnboarding: true),
                              regenerating: regenerating, skipMathGate: skipMath, reduceMotion: reduceMotion)
        #if DEBUG
        if regenerating == nil {
            if debugStage == "review" { next.fastForward = true }
            switch TestHarness.value("CRAMLESS_CAPTURE_PHASE") {
            case "reading": next.holdAt = .reading
            case "ideas": next.holdAt = .ideas
            case "writing": next.holdAt = .writing
            case "checking": next.holdAt = .checking
            case "done": next.holdAt = .done
            default: break
            }
        }
        #endif
        withAnimation(CLMotion.settle) { run = next }
        next.start()
    }

    private func rewrite(_ sourceID: UUID) {
        guard let input = run?.request.input else { return }
        begin(input, regenerating: sourceID)
    }

    /// Back to choosing a page: what was made for this one is thrown away.
    private func startOver() {
        CLHaptics.tap()
        run?.discard()
        withAnimation(CLMotion.settle) { run = nil }
    }

    private func finished(_ courseID: UUID?) {
        onDone(OnboardingFirstSet(courseID: courseID, isSample: isSample))
    }

    private func readWithCloud() async {
        guard let id = run?.sourceID, let input = run?.request.input else { return }
        readingWithCloud = true
        cloudNote = nil
        let result = await app.readPagesWithCloud(sourceID: id)
        readingWithCloud = false
        switch result {
        case .read: begin(input, regenerating: id, skipMath: true)
        case .notAllowed(let suggestion): if let suggestion { app.router.present(suggestion.sheet) }
        case .failed(let message): cloudNote = message
        case .nothingFound: cloudNote = "Cloud AI couldn't find text on this page either."
        }
    }

    private func stage(_ items: [PhotosPickerItem]) async {
        preparing = true
        problem = nil
        defer { preparing = false }
        var images: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
        }
        picked = []
        guard !images.isEmpty else {
            problem = "Couldn't open that photo. Try another."
            return
        }
        do {
            let paths = try await Task.detached(priority: .userInitiated) { try PageImageStore.stage(imageData: images) }.value
            begin(.images(paths))
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "Couldn't open that photo. Try another."
        }
    }
}
