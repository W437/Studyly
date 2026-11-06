import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// "Snap the syllabus": the camera (or photos, or a PDF), the page read on this iPhone, Cap's reading of it, and a proposal to check. "Looks right" fills the
/// editor's draft and nothing more: Add or Save stores it. The photo is never kept (a syllabus isn't study material), and only its words go to Cloud AI. A local
/// cover of the editor's sheet, since the router's would close the sheet. Hooks: see `ExamEditorView`.
struct SyllabusFlowView: View {
    let base: ExamDraft
    let courseName: String
    let topics: [(id: UUID, name: String)]
    /// DEBUG: the state to hold (`CRAMLESS_SYLLABUS`).
    var hold: String? = nil
    var onApply: (SyllabusProposal) -> Void
    var onClose: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var stage: Stage = .start
    @State private var pages: [PageText] = []
    @State private var proposal: SyllabusProposal?
    @State private var suggestion: AISuggestion?
    @State private var picked: [PhotosPickerItem] = []
    @State private var importingPDF = false
    @State private var editingFormat = false
    @State private var asksConsent = false
    @State private var hint: LocalizedStringResource?

    private enum Stage: Equatable {
        case start, camera, pick, reading, proposal, failed
    }

    var body: some View {
        ZStack {
            CLColor.background.ignoresSafeArea()
            switch stage {
            case .start: Color.clear
            case .camera:
                DocumentScannerView { outcome in finish(outcome) }.ignoresSafeArea()
            case .pick: pick
            case .reading: reading
            case .proposal: proposalPage
            case .failed: failed
            }
        }
        .captureDebugCanvas()
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { Task { await read(pdf: url) } }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await stageAndRead(items) }
        }
        .sheet(isPresented: $asksConsent, onDismiss: rereadIfAllowed) {
            ConsentSheet(reason: .cloudAI(feature: AIJob.syllabus.feature), onClose: { asksConsent = false })
                .environment(app)
        }
        .task { start() }
    }

    private func start() {
        guard stage == .start else { return }
        #if DEBUG
        if let hold {
            switch hold {
            case "pick": stage = .pick
            case "reading": stage = .reading
            case let kind where kind.hasPrefix("error:"):
                showHeldError(String(kind.dropFirst("error:".count)))
            default:
                Task { await readSample(offlineOnly: hold == "offline") }
            }
            return
        }
        #endif
        stage = ScannerSupport.canScan ? .camera : .pick
    }

    // MARK: Getting the page

    private var pick: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CapView(pose: .scan, size: 96)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                Text(SyllabusCopy.snap)
                    .clFont(.title)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                Text(SyllabusCopy.pitch)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                if let hint {
                    Label { Text(hint) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.roseInk)
                        .padding(.top, 12)
                }
                CLList {
                    if ScannerSupport.canScan {
                        Button {
                            CLHaptics.tap()
                            stage = .camera
                        } label: {
                            CaptureOptionRow(systemImage: "camera", tint: .tangerine, title: String(localized: "Scan the page"), subtitle: String(localized: "Up to 6 pages"))
                        }
                        .buttonStyle(.pressable)
                    }
                    PhotosPicker(selection: $picked, maxSelectionCount: RelayLimits.syllabusPages, selectionBehavior: .ordered, matching: .images) {
                        CaptureOptionRow(systemImage: "photo.on.rectangle.angled", tint: .sky, title: String(localized: "Choose photos"), subtitle: String(localized: "In page order, up to 6"))
                    }
                    .buttonStyle(.pressable)
                    Button {
                        CLHaptics.tap()
                        importingPDF = true
                    } label: {
                        CaptureOptionRow(systemImage: "doc.richtext", tint: .mint, title: String(localized: "Use a PDF"), subtitle: String(localized: "The first 6 pages"))
                    }
                    .buttonStyle(.pressable)
                    #if DEBUG
                    Button {
                        Task { await readSample(offlineOnly: false) }
                    } label: {
                        CaptureOptionRow(systemImage: "book.pages", tint: .neutral, title: "Use a sample syllabus", subtitle: "Debug builds only")
                    }
                    .buttonStyle(.pressable)
                    #endif
                }
                .padding(.top, 22)
                Label("The photo stays on this iPhone. Only the words go to Cap.", systemImage: "lock")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .top) { closeBar }
    }

    private var closeBar: some View {
        HStack {
            CaptureGlassButton(systemImage: "xmark", label: "Close") { onClose() }
                .padding(.leading, 12)
            Spacer()
        }
        .frame(minHeight: 50)
    }

    private func finish(_ outcome: DocumentScannerView.Outcome) {
        switch outcome {
        case .pages(let paths):
            CLHaptics.success()
            Task { await read(paths: paths) }
        case .cancelled:
            stage = .pick
        case .failed(let message):
            hint = .init(stringLiteral: message)
            stage = .pick
        }
    }

    /// The picked photos, upright and at most 2000 px, staged like a scan's.
    private func stageAndRead(_ items: [PhotosPickerItem]) async {
        stage = .reading
        var images: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
        }
        picked = []
        guard !images.isEmpty,
              let paths = try? await Task.detached(priority: .userInitiated, operation: { try PageImageStore.stage(imageData: images) }).value else {
            show(problem: SyllabusCopy.unreadable)
            return
        }
        await read(paths: paths)
    }

    // MARK: Reading it

    private func read(paths: [String]) async {
        stage = .reading
        var read: [PageText] = []
        for (index, path) in paths.prefix(RelayLimits.syllabusPages).enumerated() {
            if let page = try? await TextRecognizer.read(imageAt: path, pageIndex: index) {
                read.append(PageText(index: index, label: "\(index + 1)", lines: page.lines))
            }
        }
        // A syllabus isn't study material: its photos are gone once read.
        PageImageStore.discard(paths)
        await understand(read)
    }

    private func read(pdf url: URL) async {
        stage = .reading
        do {
            let kept = try ImportInbox.keep(url)
            let folder = "\(PageImageStore.stagingFolder)/\(UUID().uuidString)"
            let result = try await PDFReader.read(kept, imageFolder: folder, maxPages: RelayLimits.syllabusPages)
            ImportInbox.clear()
            try? FileManager.default.removeItem(at: FileStore.url(for: folder))
            await understand(result.pages.enumerated().map { PageText(index: $0.offset, label: "\($0.offset + 1)", lines: $0.element.lines) })
        } catch {
            show(problem: SyllabusCopy.unreadable)
        }
    }

    private func understand(_ read: [PageText], offlineOnly: Bool = false) async {
        pages = read
        guard read.contains(where: { !$0.lines.isEmpty }) else {
            show(problem: SyllabusCopy.unreadable)
            return
        }
        let input = SyllabusInput(course: courseName, examTitle: base.title, topics: topics, pages: read, base: base)
        let outcome = await app.ai.readSyllabus(input, offlineOnly: offlineOnly)
        suggestion = outcome.suggestion
        guard let found = outcome.proposal else {
            show(problem: SyllabusCopy.noTopics)
            return
        }
        CLHaptics.land()
        proposal = found
        withAnimation(CLMotion.settle) { stage = .proposal }
    }

    private func show(problem: LocalizedStringResource) {
        hint = problem
        CLHaptics.warning()
        withAnimation(CLMotion.settle) { stage = .failed }
    }

    /// Cloud AI was just allowed from the proposal's note: the same pages, read again.
    private func rereadIfAllowed() {
        guard app.ai.hasCloudConsent, proposal?.origin == .rules, !pages.isEmpty else { return }
        Task {
            stage = .reading
            await understand(pages)
        }
    }

    private var reading: some View {
        VStack(spacing: 10) {
            CapView(.working, size: 130)
            Text(SyllabusCopy.reading)
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.center)
            Text(SyllabusCopy.readingDetail)
                .clFont(.callout)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
            ProgressView().padding(.top, 6)
        }
        .padding(.horizontal, CLSpace.gutter + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var failed: some View {
        VStack(spacing: 12) {
            CapView(pose: .think, size: 110)
            if let hint {
                Text(hint)
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Try again") {
                CLHaptics.tap()
                hint = nil
                stage = ScannerSupport.canScan ? .camera : .pick
            }
            .buttonStyle(.cl(.primary, size: .medium, fullWidth: false))
            .padding(.top, 6)
            Button(SyllabusCopy.pickTopics, action: onClose)
                .buttonStyle(.cl(.ghost, size: .medium, fullWidth: false))
        }
        .padding(.horizontal, CLSpace.gutter + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: The proposal

    private var proposalPage: some View {
        ScrollView {
            if let proposal {
                VStack(alignment: .leading, spacing: 14) {
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))) {
                        CapFace(size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SyllabusCopy.found)
                                .clFont(.title2)
                                .foregroundStyle(CLColor.ink)
                                .accessibilityAddTraits(.isHeader)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(SyllabusCopy.fromPhoto)
                                .clFont(.subheadline)
                                .foregroundStyle(CLColor.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if proposal.origin == .rules { offlineNote }
                    dateCard(proposal)
                    topicsCard(proposal)
                    formatCard(proposal)
                    if let others = SyllabusCopy.alsoOnIt(proposal.others, calendar: app.calendar) {
                        Text(verbatim: others)
                            .clFont(.footnote)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .frame(maxWidth: CLMetrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        #if DEBUG
        // `CRAMLESS_SYLLABUS_END=1`: the page's end in a screenshot ("Also on this syllabus").
        .defaultScrollAnchor(TestHarness.value("CRAMLESS_SYLLABUS_END") == "1" ? .bottom : .top)
        #endif
        .safeAreaBar(edge: .top) { closeBar }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Rectangle().fill(CLColor.hairline).frame(height: 0.5)
                Button(SyllabusCopy.looksRight) {
                    guard let proposal else { return }
                    CLHaptics.commit()
                    onApply(proposal)
                }
                .buttonStyle(.cl(.primary))
                .padding(.horizontal, CLSpace.gutter)
                .padding(.vertical, 10)
            }
            .background(CLColor.background.ignoresSafeArea(edges: .bottom))
        }
    }

    private func dateCard(_ proposal: SyllabusProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CLEyebrow(text: "When")
            let picker = DatePicker(selection: Binding(get: { self.proposal?.date ?? base.date }, set: { self.proposal?.date = $0; self.proposal?.hasTime = true }),
                                    displayedComponents: [.date, .hourAndMinute]) {
                Text(verbatim: proposal.title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
            }
            .tint(CLColor.tangerine)
            // The largest text gives the picker the row: beside it the name squeezes to a letter a line.
            if typeSize.isAccessibilitySize {
                Text(verbatim: proposal.title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                picker.labelsHidden()
            } else {
                picker
            }
            if let quote = proposal.dateQuote {
                Text(verbatim: "“\(quote)”")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label { Text(SyllabusCopy.noDate) } icon: { Image(systemName: "calendar.badge.exclamationmark") }
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .clCard(padding: 16)
    }

    private func topicsCard(_ proposal: SyllabusProposal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CLEyebrow(text: "What's on it")
            if proposal.topics.isEmpty {
                Label { Text(SyllabusCopy.noTopics) } icon: { Image(systemName: "questionmark.circle") }
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            ForEach(proposal.topics) { topic in
                Button {
                    CLHaptics.select()
                    if let i = self.proposal?.topics.firstIndex(where: { $0.id == topic.id }) { self.proposal?.topics[i].included.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: topic.included ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(topic.included ? CLColor.tangerineInk : CLColor.ink4)
                        ReflowStack(verticalAlignment: .center, spacing: 8) {
                            Text(verbatim: topic.name)
                                .clFont(.body)
                                .foregroundStyle(topic.included ? CLColor.ink : CLColor.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                            if topic.isNew { CLPill(text: SyllabusCopy.noNotes, tone: .tangerine) }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: CLMetrics.minHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(topic.included ? [.isSelected] : [])
            }
        }
        .clCard(padding: 16)
    }

    private func formatCard(_ proposal: SyllabusProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CLEyebrow(text: "Format")
                Spacer()
                Button(SyllabusCopy.edit) {
                    CLHaptics.select()
                    withAnimation(CLMotion.settle) { editingFormat.toggle() }
                }
                .buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
                .frame(minHeight: CLMetrics.minHitTarget)
            }
            if editingFormat, self.proposal != nil {
                Toggle("Multiple choice", isOn: formatBinding(\.multipleChoice)).tint(CLColor.tangerine).clFont(.body)
                Toggle("Short answer", isOn: formatBinding(\.shortAnswer)).tint(CLColor.tangerine).clFont(.body)
                Toggle("Essay", isOn: formatBinding(\.essay)).tint(CLColor.tangerine).clFont(.body)
                LabeledContent("Questions on it") {
                    TextField("Not sure", value: optionalBinding(\.questionCount), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                .clFont(.body)
                LabeledContent("Minutes") {
                    TextField("Not sure", value: optionalBinding(\.minutes), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                .clFont(.body)
            } else {
                Text(verbatim: LibraryFormat.formatLine(proposal.format))
                    .clFont(.bodyEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let quote = proposal.formatQuote {
                Text(verbatim: "“\(quote)”")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label { Text(SyllabusCopy.mockMatch) } icon: { Image(systemName: "timer") }
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .clCard(padding: 16)
    }

    private func formatBinding(_ path: WritableKeyPath<ExamFormat, Bool>) -> Binding<Bool> {
        Binding(get: { proposal?.format[keyPath: path] ?? false }, set: { proposal?.format[keyPath: path] = $0 })
    }

    private func optionalBinding(_ path: WritableKeyPath<ExamFormat, Int?>) -> Binding<Int?> {
        Binding(get: { proposal?.format[keyPath: path] ?? nil }, set: { proposal?.format[keyPath: path] = $0 })
    }

    private var offlineNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(SyllabusCopy.offline) } icon: { Image(systemName: "iphone") }
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if case .allowCloud? = suggestion {
                Button(SyllabusCopy.turnOnCloud) {
                    CLHaptics.tap()
                    asksConsent = true
                }
                .buttonStyle(.cl(.soft, size: .small, fullWidth: false))
                .frame(minHeight: CLMetrics.minHitTarget)
            }
        }
    }

    // MARK: Harness

    #if DEBUG
    private func readSample(offlineOnly: Bool) async {
        stage = .reading
        await understand(SyllabusSample.pages, offlineOnly: offlineOnly)
    }

    private func showHeldError(_ kind: String) {
        switch kind {
        case "nothing":
            hint = SyllabusCopy.noTopics
            stage = .failed
        case "nodate", "notopics":
            let exams = (try? RelayFixtures.load(SyllabusResponse.self, "syllabus").exams) ?? []
            var held = SyllabusProposal.make(exams: exams, examTitle: base.title, topicIDs: [:], base: base, pageText: SyllabusSample.text, origin: .cloud,
                                             now: app.now, calendar: app.calendar)
            if kind == "nodate" {
                held?.date = nil
                held?.dateQuote = nil
            } else {
                held?.topics = []
            }
            proposal = held
            stage = .proposal
        default:
            hint = SyllabusCopy.unreadable
            stage = .failed
        }
    }
    #endif
}

#if DEBUG
/// The sample a harness reads: the same page as `requests/syllabus.json`.
enum SyllabusSample {
    static let lines = [
        "BIO 101: Cell Biology", "Fall 2026 syllabus", "Grading: midterm 30%, final exam 40%, labs 30%", "Midterm exam", "Friday, November 20, 10:00 AM",
        "Covers:", "Week 4: Phases of mitosis", "Week 5: Cytokinesis", "Week 6: Meiosis", "Week 7: Genetics basics",
        "40 questions: 30 multiple choice and 10 short answers, 90 minutes.", "One page of notes allowed.", "Final exam: December 14",
        "The final covers everything from the term.",
    ]
    static var text: String { lines.joined(separator: "\n") }
    static var pages: [PageText] {
        [PageText(index: 0, label: "1", lines: lines.enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element) })]
    }
}
#endif
