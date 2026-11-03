import SwiftUI

/// The draft review: the generated questions grouped by topic, each with its format, answer and source chip, all
/// ticked; what the check left out and why; an honest line about who wrote and checked them; a better-AI suggestion
/// when there is one; the course (or, in onboarding, which class it's for); and "Add 14 questions".
///
/// Nothing is added until the person approves. Closing asks whether to keep the drafts for later or throw them away.
///
/// DEBUG hooks (with a route that shows a review, e.g. `CRAMLESS_ROUTE=review`):
/// - `CRAMLESS_REVIEW_EDIT=1` opens the editor on the first question.
/// - `CRAMLESS_REVIEW_UNTICK=<n>` unticks the first n questions.
/// - `CRAMLESS_REVIEW_SCROLL=leftout` scrolls to the "Left out" section.
/// - `CRAMLESS_REVIEW_PEEK=1` opens the first question's source page.
/// - `CRAMLESS_REVIEW_APPROVE=1` presses "Add" after a moment (the toast, then the screen closes).
/// - `CRAMLESS_REVIEW_ALLOW=1` allows Cloud AI after a moment, as the consent sheet would (the set is written again).
struct DraftReviewView: View {
    let sourceID: UUID
    let isOnboarding: Bool
    /// Called once the set is approved (with its course) or put aside (nil). Without it the review dismisses itself.
    var onFinish: ((UUID?) -> Void)? = nil
    /// Writes the set again; the capture flow passes it, so allowing Cloud AI here rewrites the set with it.
    var onRewrite: (() -> Void)? = nil
    /// The pages of the PDF a "questions for the rest" review is about; nil for a review of the whole source. The formulas card counts
    /// and reads only these.
    var restPages: [Int]? = nil
    /// Onboarding: back to choosing a page.
    var onStartOver: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [DraftRow] = []
    @State private var report: DraftReport?
    @State private var excluded: Set<UUID> = []
    @State private var filter: ItemKind?
    @State private var courseID: UUID?
    /// The class picked from the suggestions, and one typed in (which wins when there is one).
    @State private var pickedClass: String?
    @State private var typedClass = ""
    @State private var suggestions: [String] = []
    @State private var editing: DraftEditTarget?
    @State private var peek: DraftPeek?
    @State private var confirmingClose = false
    @State private var loaded = false
    @State private var finished = false
    @State private var context = DraftContext()
    @State private var scrollTarget: String?
    /// PDF pages of this source whose text layer lost its formulas, and the state of reading them with Cloud AI.
    @State private var formulaPages = 0
    @State private var formulasProblem: String?
    /// The formulas card's steps (`FormulasSteps`).
    @State private var steps = FormulasSteps()
    @State private var formulasTask: Task<Void, Never>?
    @FocusState private var classFieldFocused: Bool

    /// The pages are being read with Cloud AI (the Add button waits for it).
    private var readingFormulas: Bool { steps.reading }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    CaptureOriginNote(systemImage: originIcon, text: originText, tone: report?.origin == .rules ? .sun : .sky)
                        .padding(.top, 16)
                    if let extraNote {
                        CaptureOriginNote(systemImage: "info.circle", text: extraNote, tone: .sun).padding(.top, 8)
                    }
                    if formulaPages > 0 { formulasCard.padding(.top, 8) }
                    if let suggestion = visibleSuggestion { suggestionCard(suggestion).padding(.top, 12) }
                    if isOnboarding { classCard.padding(.top, 16) }
                    if kindsPresent.count > 1 { filterChips.padding(.top, 18) }
                    ForEach(groups, id: \.topic) { group in
                        section(group.topic, rows: group.rows)
                    }
                    if !(report?.leftOut ?? []).isEmpty { leftOutSection.id("leftout") }
                    if loaded && rows.isEmpty && !finished { emptyState }
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 2)
                .padding(.bottom, 24)
                .frame(maxWidth: CLMetrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(CLMotion.settle) { proxy.scrollTo(target, anchor: .top) }
            }
        }
        .clScreenBackground()
        .safeAreaBar(edge: .top) {
            HStack { topButton; Spacer() }
                .frame(minHeight: 50)
        }
        .safeAreaBar(edge: .bottom) { bottomBar }
        .sheet(item: $editing, onDismiss: load) { target in
            DraftItemEditor(itemID: target.id)
        }
        .sheet(item: $peek) { peek in
            NavigationStack {
                if peek.isLecture {
                    LectureNotesView(sourceID: sourceID, focusTime: peek.time)
                } else {
                    SourcePageView(sourceID: sourceID, pageIndex: peek.pageIndex, highlight: peek.anchors)
                }
            }
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Keep these questions?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Keep for later") {
                app.router.toast("Kept for later, with the \(context.isLecture ? "lecture" : "page") in your Library",
                                 systemImage: "tray.full", tone: .neutral)
                finish(nil)
            }
            Button("Discard \(CLFormat.count(rows.count, "question"))", role: .destructive) {
                finished = true
                // A lecture keeps its recording, transcript and notes; so does material reviewed later from elsewhere, and a source
                // that already has questions (a set added for the rest of it). A page the capture flow has just read goes with its
                // questions.
                app.discardDrafts(sourceID: sourceID,
                                  keepSource: context.isLecture || onFinish == nil || !app.items(fromSource: sourceID).isEmpty)
                finish(nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing has been added to a course yet.")
        }
        .onAppear(perform: load)
        .onDisappear { formulasTask?.cancel() }
        .onChange(of: app.revision) { _, _ in load() }
        .onChange(of: unlockKey) { old, new in
            switch steps.consentChanged(cloudAllowed: app.ai.hasCloudConsent, photosAllowed: AIConsent.photosGranted(app.settings)) {
            case .read: if !finished { startFormulasRead() }
            case .hold: break
            case .ordinary: rewriteIfUnlocked(old: old, new: new)
            }
        }
        .onChange(of: app.router.sheet) { _, sheet in endFormulasStepsIfAbandoned(sheet) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isOnboarding {
                Text("Your first set")
                    .clFont(.eyebrow)
                    .foregroundStyle(CLColor.tangerineInk)
            }
            Text(title)
                .clFont(isOnboarding ? .brandTitle(30) : .largeTitle)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .clFont(.callout)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        let name = (report?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return context.sourceTitle.isEmpty ? "Your questions" : context.sourceTitle
    }

    private var subtitle: String {
        let count = CLFormat.count(rows.count, "question")
        if context.isLecture { return "\(count) from \(context.sourceTitle)" }
        let place = context.pagePhrase.isEmpty ? "" : ", \(context.pagePhrase)"
        return "\(count) from \(context.sourceTitle)\(place)"
    }

    @ViewBuilder private var topButton: some View {
        if isOnboarding {
            if onStartOver != nil {
                CaptureGlassButton(systemImage: "chevron.backward", label: "Pick another page") { startOver() }
                    .padding(.leading, 12)
            }
        } else {
            CaptureGlassButton(systemImage: "xmark", label: "Close") {
                CLHaptics.tap()
                confirmingClose = true
            }
            .padding(.leading, 12)
        }
    }

    // MARK: Origin and suggestion

    private var originIcon: String {
        switch report?.origin {
        case .cloud: "cloud"
        case .onDevice: "iphone"
        case .rules: "list.bullet.rectangle"
        default: "checkmark.seal"
        }
    }

    /// Who wrote the set, who checked it and against what, in plain words.
    private var originText: String {
        let place = context.checkPlace
        let lead: String
        switch report?.origin {
        case .cloud:
            lead = report?.checkedBy == .cloud
                ? "Written by Cloud AI and checked against \(place)."
                : "Written by Cloud AI and checked against \(place) on your iPhone."
        case .onDevice:
            lead = "Written on this iPhone and checked against \(place)."
        case .rules:
            lead = report?.note ?? "Basic questions from the offline rules, checked against \(place)."
        default:
            lead = "Checked against \(place)."
        }
        return "\(lead) Each one shows where it came from. Untick anything you don't want."
    }

    /// The better-AI suggestion, while it still applies (consent not yet given, photos still off, still on free).
    private var visibleSuggestion: AISuggestion? {
        guard let suggestion = report?.suggestion?.aiSuggestion else { return nil }
        switch suggestion {
        case .allowCloud: return app.ai.cloudAvailableInThisBuild && !app.ai.hasCloudConsent ? suggestion : nil
        case .allowPhotos: return AIConsent.photosGranted(app.settings) ? nil : suggestion
        case .upgrade: return app.ai.plan.isPaid ? nil : suggestion
        }
    }

    private func suggestionCard(_ suggestion: AISuggestion) -> some View {
        let words: (title: String, body: String, action: String) = switch suggestion {
        case .allowCloud:
            ("Want better questions?",
             "Cloud AI writes richer questions from this page, in your own words and multiple choice, and checks each one against it. It stays off until you say so.",
             "Use Cloud AI")
        case .allowPhotos:
            ("Let Cloud AI see the page",
             "With page photos it can read handwriting, math and diagram labels, not just the printed text.",
             "Send page photos")
        case .upgrade(_, let message):
            ("Free AI scans used up", message, "See plans")
        }
        return HStack(alignment: .top, spacing: 12) {
            CaptureBadge(systemImage: "sparkles", tint: .tangerine, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(words.title).clFont(.headline).foregroundStyle(CLColor.ink)
                Text(words.body)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button(words.action) {
                    CLHaptics.tap()
                    app.router.present(suggestion.sheet)
                }
                .buttonStyle(.cl(.dark, size: .small, fullWidth: false))
                .padding(.top, 8)
            }
        }
        .clCard(padding: 16)
    }

    /// The person allowed what the suggestion asked for: write the set again with it.
    private var unlockKey: String {
        "\(app.ai.hasCloudConsent)-\(AIConsent.photosGranted(app.settings))-\(app.ai.plan.isPaid)"
    }

    private func rewriteIfUnlocked(old: String, new: String) {
        guard old != new, !finished, let onRewrite, let suggestion = report?.suggestion?.aiSuggestion else { return }
        let satisfied: Bool = switch suggestion {
        case .allowCloud: app.ai.hasCloudConsent
        case .allowPhotos: AIConsent.photosGranted(app.settings)
        case .upgrade: app.ai.plan.isPaid
        }
        guard satisfied else { return }
        finished = true
        onRewrite()
    }

    /// What else the run has to say: a long reading read in parts, the pages left out, a check done on this iPhone, why this
    /// iPhone wrote the set, the lecture ideas that didn't become questions. (For the offline rules the note is the origin
    /// line itself.)
    private var extraNote: String? {
        guard let report, report.origin != .rules, let note = report.note, !note.isEmpty else { return nil }
        return note
    }

    // MARK: Formulas

    /// The text layer of a PDF lost its typeset formulas (`PageLayout.formulasMayBeMissing`). The page can be read as an
    /// image with Cloud AI to get them back, when the set was made in the capture flow (which can write it again).
    private var formulasCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaptureOriginNote(systemImage: "function", text: Source.missingFormulasNote, tone: .sky)
            if onRewrite != nil, app.ai.cloudAvailableInThisBuild {
                Button {
                    CLHaptics.tap()
                    switch steps.tapped(cloudAllowed: app.ai.hasCloudConsent, photosAllowed: AIConsent.photosGranted(app.settings)) {
                    case .askCloudAI: app.router.present(.consent(.cloudAI(feature: AIJob.transcribeImage.feature)))
                    case .askPhotos: app.router.present(.consent(.photos))
                    case .read: startFormulasRead()
                    }
                } label: {
                    ZStack {
                        Group {
                            if !app.ai.hasCloudConsent {
                                Text("Use Cloud AI")
                            } else if !AIConsent.photosGranted(app.settings) {
                                Text("Allow page photos")
                            } else {
                                Text("Read the pages with Cloud AI")
                            }
                        }
                        .opacity(readingFormulas ? 0 : 1)
                        if readingFormulas { ProgressView().tint(CLColor.onFill) }
                    }
                }
                .buttonStyle(.cl(.dark, size: .small, fullWidth: false))
                .disabled(readingFormulas || finished)
            }
            if let formulasProblem {
                Text(formulasProblem)
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.roseInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func startFormulasRead() {
        guard !steps.reading else { return }
        formulasTask = Task { await readFormulasWithCloud() }
    }

    /// The consent sheet closed. If the card's steps didn't get as far as the read (Cloud AI or the photos weren't allowed), they are
    /// over, and allowing Cloud AI from the offer later writes the set again as usual. Decided after the consent change itself has
    /// been seen, which can arrive in the same update.
    private func endFormulasStepsIfAbandoned(_ sheet: AppSheet?) {
        guard sheet == nil, steps.started, !steps.reading else { return }
        Task { @MainActor in
            steps.sheetClosed(cloudAllowed: app.ai.hasCloudConsent, photosAllowed: AIConsent.photosGranted(app.settings))
        }
    }

    /// Renders the flagged pages, reads them with Cloud AI (merged into the pages' lines, so questions made already keep their
    /// anchors), and writes the set again from the better text. The Add button waits for it.
    private func readFormulasWithCloud() async {
        guard !steps.reading, !finished else { return }
        steps.readStarted()
        formulasProblem = nil
        let result = await app.readPDFPagesWithCloud(sourceID: sourceID, onlyPages: restPages.map(Set.init))
        guard !Task.isCancelled else {
            steps.readEnded(continuing: false)
            return
        }
        switch result {
        case .read:
            steps.readEnded(continuing: false)
            guard !finished, let onRewrite else { return }
            finished = true
            onRewrite()
        case .notAllowed(let suggestion):
            // Presenting what would allow it; the card's steps go on when it is allowed.
            steps.readEnded(continuing: suggestion != nil)
            if let suggestion { app.router.present(suggestion.sheet) }
        case .failed(let message):
            steps.readEnded(continuing: false)
            formulasProblem = message
        case .nothingFound:
            steps.readEnded(continuing: false)
            formulasProblem = "Cloud AI couldn't find text on those pages either."
        }
    }

    // MARK: Class (onboarding)

    private var classCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which class is this for?")
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Your set goes there, and your plan is built for it.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if !suggestions.isEmpty {
                CaptureChips(spacing: 8) {
                    ForEach(suggestions, id: \.self) { name in
                        Button {
                            CLHaptics.select()
                            pickedClass = name
                            typedClass = ""
                            classFieldFocused = false
                        } label: {
                            CLChip(title: .verbatim(name), systemImage: CourseGuess.symbol(for: name),
                                   selected: typedClass.isEmpty && pickedClass == name)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField(suggestions.isEmpty ? "Like Bio 101 or AP Psychology" : "Or type another name", text: $typedClass)
                .clFont(.body)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($classFieldFocused)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: CLRadius.field, style: .continuous))
                .accessibilityLabel("Class name")
        }
        .clCard(padding: 16)
    }

    // MARK: Filter

    private var kindsPresent: [ItemKind] {
        ItemKind.allCases.filter { kind in rows.contains { $0.kind == kind } }
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterChip(nil, title: "All \(rows.count)")
                ForEach(kindsPresent) { kind in
                    filterChip(kind, title: "\(kind.displayName) \(rows.filter { $0.kind == kind }.count)")
                }
            }
            .padding(.horizontal, CLSpace.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -CLSpace.gutter)
    }

    private func filterChip(_ kind: ItemKind?, title: String) -> some View {
        Button {
            CLHaptics.select()
            withAnimation(CLMotion.settle) { filter = kind }
        } label: {
            CLChip(title: .verbatim(title), selected: filter == kind)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(kind == nil ? "All questions" : "\(kind!.displayName) questions"))
    }

    // MARK: Questions

    private var groups: [(topic: String, rows: [DraftRow])] {
        let visible = rows.filter { filter == nil || $0.kind == filter }
        var order = report?.topics ?? []
        for row in visible where !order.contains(row.topic) { order.append(row.topic) }
        return order.compactMap { topic in
            let inTopic = visible.filter { $0.topic == topic }
            return inTopic.isEmpty ? nil : (topic.isEmpty ? "More questions" : topic, inTopic)
        }
    }

    private func section(_ topic: String, rows: [DraftRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(topic)
                    .clFont(.title3)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(rows.filter { !excluded.contains($0.id) }.count) of \(rows.count)")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink3)
                    .accessibilityLabel(Text("\(rows.filter { !excluded.contains($0.id) }.count) of \(rows.count) included"))
            }
            .padding(.top, 24)
            .padding(.bottom, 10)
            .padding(.horizontal, 2)
            CLList {
                ForEach(rows) { row in
                    DraftRowView(row: row, included: !excluded.contains(row.id),
                                 toggle: { toggle(row) },
                                 edit: { editing = DraftEditTarget(id: row.id) },
                                 openSource: { openSource(row) })
                }
            }
        }
    }

    private func toggle(_ row: DraftRow) {
        CLHaptics.select()
        withAnimation(CLMotion.snap) {
            if excluded.contains(row.id) { excluded.remove(row.id) } else { excluded.insert(row.id) }
        }
    }

    private func openSource(_ row: DraftRow) {
        CLHaptics.tap()
        peek = DraftPeek(pageIndex: row.pageIndex ?? 0, anchors: row.anchors, time: row.time, isLecture: context.isLecture)
    }

    // MARK: Left out

    private var leftOutSection: some View {
        let leftOut = report?.leftOut ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Text("Left out")
                .clFont(.title3)
                .foregroundStyle(CLColor.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 28)
                .padding(.horizontal, 2)
            Text(leftOut.count == 1
                 ? "The check took this one out, because \(context.checkPlace) doesn't back it up."
                 : "The check took these out, because \(context.checkPlace) doesn't back them up.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .padding(.horizontal, 2)
            CLList {
                ForEach(leftOut) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(CLColor.ink3)
                            .frame(width: 44, height: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.prompt)
                                .clFont(.subheadlineEmphasis)
                                .foregroundStyle(CLColor.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.reason)
                                .clFont(.footnote)
                                .foregroundStyle(CLColor.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Left out: \(item.prompt). \(item.reason)"))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            CapView(pose: .study, size: 120)
            Text("No questions waiting here")
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
            Button("Close") { finish(nil) }
                .buttonStyle(.cl(.soft, size: .small, fullWidth: false))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: Bottom bar

    private var keptCount: Int { rows.filter { !excluded.contains($0.id) }.count }

    /// The class the set goes to in onboarding: the typed name, else the picked suggestion.
    private var className: String {
        let typed = typedClass.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? (pickedClass ?? "") : typed
    }

    private var addTitle: String {
        guard keptCount > 0 else { return "Tick at least one question" }
        let count = CLFormat.count(keptCount, "question")
        if isOnboarding {
            let name = className.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Add \(count)" : "Add \(count) to \(name)"
        }
        return "Add \(count)"
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if !isOnboarding {
                CaptureCoursePicker(courseID: $courseID) { course in
                    CaptureCourseLabel(course: course, prefix: "Adding to")
                }
            }
            Button(addTitle, action: approve)
                .buttonStyle(.cl(.primary))
                .disabled(keptCount == 0 || finished || readingFormulas || (isOnboarding && className.trimmingCharacters(in: .whitespaces).isEmpty)
                          || (!isOnboarding && courseID == nil))
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: CLMetrics.readableWidth + 2 * CLSpace.gutter)
    }

    // MARK: Actions

    private func approve() {
        guard !finished, !readingFormulas, keptCount > 0 else { return }
        finished = true
        let keep = Set(rows.map(\.id)).subtracting(excluded)
        var target: Course?
        if isOnboarding {
            target = app.assignDrafts(sourceID: sourceID, toCourseNamed: className)
        } else if let courseID, courseID != app.source(sourceID)?.course?.id {
            target = app.course(courseID)
        }
        let added = app.approveDrafts(sourceID: sourceID, keeping: keep, in: target)
        let course = app.source(sourceID)?.course
        CLHaptics.success()
        if !isOnboarding, let course {
            app.router.toast("Added \(CLFormat.count(added, "question")) to \(course.name)")
        }
        finish(course?.id)
    }

    private func startOver() {
        CLHaptics.tap()
        finished = true
        app.discardDrafts(sourceID: sourceID)
        onStartOver?()
    }

    private func finish(_ courseID: UUID?) {
        if let onFinish { onFinish(courseID) } else { dismiss() }
    }

    private func load() {
        guard !finished else { return }
        let source = app.source(sourceID)
        let items = app.draftItems(sourceID: sourceID)
        report = app.draftReport(sourceID: sourceID)
        context = DraftContext(source: source)
        formulaPages = source.map { $0.modelContext != nil ? $0.pagesWithMissingFormulas.filter { restPages?.contains($0.pageIndex) ?? true }.count : 0 } ?? 0
        let topics = Dictionary((source?.course?.topics ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        rows = items.filter { $0.modelContext != nil }.map {
            DraftRow(item: $0, topic: $0.topicID.flatMap { topics[$0] } ?? "")
        }
        guard !loaded else { return }
        loaded = true
        courseID = source?.course?.id ?? app.defaultCourseID()
        if isOnboarding {
            // The page's subject first ("Biology" for the sample); a course the set already sits in (not one made for
            // it) comes first instead.
            var names = app.suggestedCourseNames(sourceID: sourceID)
            if let course = source?.course, report?.provisionalCourseID != course.id {
                names.removeAll { $0.compare(course.name, options: .caseInsensitive) == .orderedSame }
                names.insert(course.name, at: 0)
            }
            suggestions = Array(names.prefix(4))
            pickedClass = suggestions.first
        }
        #if DEBUG
        applyDebugHooks()
        #endif
    }

    #if DEBUG
    private func applyDebugHooks() {
        if let n = TestHarness.once("CRAMLESS_REVIEW_UNTICK").flatMap(Int.init) {
            excluded = Set(rows.prefix(n).map(\.id))
        }
        if TestHarness.once("CRAMLESS_REVIEW_EDIT") == "1", let first = rows.first {
            Task { try? await nap(900); editing = DraftEditTarget(id: first.id) }
        }
        if TestHarness.once("CRAMLESS_REVIEW_PEEK") == "1", let first = rows.first {
            Task { try? await nap(900); openSource(first) }
        }
        if TestHarness.once("CRAMLESS_REVIEW_SCROLL") == "leftout" {
            Task { try? await nap(700); scrollTarget = "leftout" }
        }
        if TestHarness.once("CRAMLESS_REVIEW_APPROVE") == "1" {
            Task { try? await nap(1500); approve() }
        }
        if TestHarness.once("CRAMLESS_REVIEW_ALLOW") == "1" {
            Task { try? await nap(1500); app.allowCloudAI() }
        }
    }
    #endif
}

// MARK: - Rows

/// One draft question as the review shows it, read out of the model once (rows outlive the drafts while closing).
struct DraftRow: Identifiable, Equatable {
    let id: UUID
    let kind: ItemKind
    let topic: String
    let prompt: String
    let answer: String
    let cloze: String?
    /// "4 options", the diagram's labels.
    let detail: String?
    let sourceLabel: String?
    let pageIndex: Int?
    let anchors: [String]
    let time: Double?

    init(item: StudyItem, topic: String) {
        id = item.id
        kind = item.kind
        self.topic = topic
        prompt = item.prompt
        switch item.kind {
        case .mcq:
            answer = item.choices.first(where: \.correct)?.text ?? item.answer
            detail = item.choices.count > 1 ? "\(item.choices.count) options" : nil
            cloze = nil
        case .cloze:
            answer = item.answer
            cloze = item.cloze?.text
            detail = nil
        case .diagram:
            let labels = item.diagram?.targets.map(\.label) ?? []
            answer = labels.isEmpty ? item.answer : "Label \(labels.count) parts of the page"
            detail = labels.isEmpty ? nil : labels.joined(separator: " · ")
            cloze = nil
        default:
            answer = item.answer
            detail = nil
            cloze = nil
        }
        let ref = item.sourceRef
        sourceLabel = ref?.label
        pageIndex = ref?.pageIndex
        anchors = ref?.anchorIDs ?? []
        time = ref?.start
    }
}

private struct DraftRowView: View {
    let row: DraftRow
    let included: Bool
    let toggle: () -> Void
    let edit: () -> Void
    let openSource: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggle) {
                DraftTickBox(on: included)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Include: \(row.prompt)"))
            .accessibilityValue(Text(included ? "Included" : "Not included"))
            .accessibilityAddTraits(.isToggle)

            VStack(alignment: .leading, spacing: 8) {
                Button(action: edit) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.prompt)
                            .clFont(.headline)
                            .foregroundStyle(CLColor.ink)
                            .strikethrough(!included, color: CLColor.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                        answer
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = row.detail {
                            Text(detail)
                                .clFont(.footnote)
                                .foregroundStyle(CLColor.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .opacity(included ? 1 : 0.45)
                .accessibilityLabel(Text("\(row.prompt). Answer: \(row.answer)"))
                .accessibilityHint(Text("Edits the question"))

                CaptureChips(spacing: 6) {
                    CLPill(text: .verbatim(row.kind.displayName), tone: .sky)
                        .accessibilityLabel(Text("Format: \(row.kind.displayName)"))
                    if let label = row.sourceLabel {
                        Button(action: openSource) {
                            CLSourceChip(label: label, systemImage: row.time != nil ? "waveform" : "book.pages")
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text(row.time != nil ? "Shows that moment of the lecture" : "Shows the page, with the lines marked"))
                    }
                }
                .opacity(included ? 1 : 0.6)
            }
            .padding(.top, 11)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.bottom, 14)
        .padding(.top, 3)
    }

    @ViewBuilder private var answer: some View {
        switch row.kind {
        case .mcq:
            Label {
                Text(row.answer).clFont(.subheadline).foregroundStyle(CLColor.ink2)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CLColor.mintInk)
            }
            .labelStyle(DraftAnswerLabelStyle())
        case .cloze:
            Text(draftClozeText(row.cloze ?? row.answer))
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
        default:
            Text(row.answer)
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .lineLimit(4)
        }
    }
}

private struct DraftAnswerLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

/// What the review knows about its source: its title, kind and where the check looked.
struct DraftContext: Equatable {
    var sourceTitle = ""
    var isLecture = false
    /// "p. 87", "pp. 12–15".
    var pagePhrase = ""
    /// "p. 87", "your text", "the transcript".
    var checkPlace = "your page"

    init() {}

    init(source: Source?) {
        guard let source, source.modelContext != nil else { return }
        sourceTitle = source.title
        isLecture = source.kind == .lecture
        // No-break spaces, so "p. 87" never splits across lines.
        let labels = source.sortedPages.map(\.label)
        if let first = labels.first, let last = labels.last {
            pagePhrase = labels.count == 1 ? "p.\u{00A0}\(first)" : "pp.\u{00A0}\(first)–\(last)"
        }
        switch source.kind {
        case .lecture: checkPlace = "the transcript"
        case .text: checkPlace = "your text"
        default: checkPlace = pagePhrase.isEmpty ? "your page" : pagePhrase
        }
    }
}

struct DraftEditTarget: Identifiable {
    let id: UUID
}

struct DraftPeek: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let anchors: [String]
    let time: Double?
    let isLecture: Bool
}

// MARK: - The formulas card's steps

/// The steps the formulas card walks through on the review: allow Cloud AI, allow page photos, read the pages, then write the set again
/// (once, by the read). Allowing Cloud AI from the card must not also trigger the automatic rewrite that allowing it from the offer
/// does: that would spend scans on text that still lacks its formulas, and the read after it would spend more.
struct FormulasSteps: Equatable {
    /// The card has started its steps.
    private(set) var started = false
    private(set) var reading = false

    enum Next: Equatable { case askCloudAI, askPhotos, read }

    /// What the review does when consent changes while these steps may be under way.
    enum Reaction: Equatable {
        /// Both are allowed now: read the pages.
        case read
        /// The steps are under way and one is still missing: wait, and don't rewrite.
        case hold
        /// The steps aren't under way: the offer's own rule applies.
        case ordinary
    }

    /// The card's button was tapped: what comes next.
    mutating func tapped(cloudAllowed: Bool, photosAllowed: Bool) -> Next {
        started = true
        if !cloudAllowed { return .askCloudAI }
        return photosAllowed ? .read : .askPhotos
    }

    /// Consent changed (Cloud AI or the page photos were allowed or withdrawn).
    func consentChanged(cloudAllowed: Bool, photosAllowed: Bool) -> Reaction {
        guard started else { return .ordinary }
        if cloudAllowed, photosAllowed, !reading { return .read }
        return .hold
    }

    /// The consent sheet closed: the steps are over unless both are allowed (then the change already started the read).
    mutating func sheetClosed(cloudAllowed: Bool, photosAllowed: Bool) {
        guard started, !reading, !(cloudAllowed && photosAllowed) else { return }
        started = false
    }

    mutating func readStarted() { reading = true }

    /// The read ended. `continuing`: a sheet was presented to allow what was missing, and the steps go on when it is allowed.
    mutating func readEnded(continuing: Bool) {
        reading = false
        started = continuing
    }
}
