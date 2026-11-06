import SwiftUI

/// "Looks wrong?", in the answer panel's second row and under a flipped flashcard. Icon only when the row has no room for its words.
struct LooksWrongButton: View {
    let item: StudyItem
    var given: String? = nil

    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            CLHaptics.tap()
            app.router.present(.looksWrong(itemID: item.id, given: given ?? ""))
        } label: {
            ViewThatFits(in: .horizontal) {
                Label("Looks wrong?", systemImage: "exclamationmark.bubble").fixedSize()
                Image(systemName: "exclamationmark.bubble")
            }
        }
        .buttonStyle(.cl(.ghost, size: .medium, fullWidth: false))
        .accessibilityLabel(Text("Looks wrong?"))
    }
}

/// What's off with a question. The lines it came from show at once, read on this iPhone; then the student says what looks wrong and Cap re-reads
/// them (`AppModel+Report`). Nothing is held against them: until it's settled the question is out of sessions and counts for nothing. A
/// question with no lines to read offers Edit and Skip only, and so does anyone Cloud AI isn't for.
///
/// DEBUG hook: `CRAMLESS_LOOKSWRONG=sheet|checking|fixed|stands|retired|queued`, with an answered session state
/// (`CRAMLESS_SESSION_STATE=mcq-answered CRAMLESS_SESSION_PICK=wrong`): opens over the first question, in that state.
struct LooksWrongSheet: View {
    let itemID: UUID
    /// What the student answered ("" for none).
    let given: String

    private enum Phase: Equatable {
        case choose, checking, outcome(RecheckResult)
    }

    private struct OpenedSource: Identifiable {
        let ref: SourceRef
        let isLecture: Bool
        var id: UUID { ref.sourceID }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .choose
    @State private var reason: CheckReport.Reason?
    @State private var note = ""
    @State private var opened: OpenedSource?
    @State private var contentHeight: CGFloat = 420
    @State private var detent: PresentationDetent = .height(420)
    /// The sheet went on to consent or the editor: the question's report waits.
    @State private var handedOff = false
    @State private var didStart = false

    private var item: StudyItem? {
        guard let item = app.item(itemID), item.modelContext != nil, item.deletedAt == nil else { return nil }
        return item
    }

    private var inSession: Bool {
        if case .session = app.router.cover { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CLSpace.l) {
                if let item {
                    let source = app.reportSource(of: item)
                    content(item, source: source)
                } else {
                    Text("This question isn't here anymore.")
                        .clFont(.body)
                        .foregroundStyle(CLColor.ink2)
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 26)
            .padding(.bottom, 16)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                let fitted = height + 12
                guard abs(fitted - contentHeight) > 1 else { return }
                let wasFitted = detent != .large
                contentHeight = fitted
                if wasFitted { detent = .height(fitted) }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(CLColor.background.ignoresSafeArea())
        .presentationDetents([.height(contentHeight), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(CLColor.background)
        .sheet(item: $opened) { opened in
            NavigationStack {
                if opened.isLecture {
                    LectureNotesView(sourceID: opened.ref.sourceID, focusTime: opened.ref.start)
                } else {
                    SourcePageView(sourceID: opened.ref.sourceID, pageIndex: opened.ref.pageIndex ?? 0,
                                   highlight: opened.ref.anchorIDs, closes: true)
                }
            }
            .environment(\.clDyslexicFont, app.settings.dyslexicFont)
            .environment(\.skyTheme, app.skyTheme)
            .tint(CLColor.tangerine)
        }
        .onAppear(perform: start)
        .onDisappear(perform: finish)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ item: StudyItem, source: ReportSource?) -> some View {
        switch phase {
        case .choose:
            if let source, app.canAskCapToCheck {
                if item.reported { waiting(source) } else { choosing(item, source: source) }
            } else {
                noCheck(source: source)
            }
        case .checking:
            checking(source)
        case .outcome(let result):
            outcome(result, source: source)
        }
    }

    private func choosing(_ item: StudyItem, source: ReportSource) -> some View {
        VStack(alignment: .leading, spacing: CLSpace.l) {
            Text("What looks wrong?")
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .accessibilityAddTraits(.isHeader)
            sourceCard(source)
            reasons(item)
            VStack(spacing: 8) {
                Button("Ask Cap to check") { ask(item, source: source) }
                    .buttonStyle(.cl(.primary))
                    .disabled(reason == nil)
                Text("Free. Cap re-reads \(source.place) with Cloud AI.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func sourceCard(_ source: ReportSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From \(source.place):")
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink2)
            Text(source.lines.joined(separator: " "))
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                CLHaptics.tap()
                opened = OpenedSource(ref: source.ref, isLecture: source.isLecture)
            } label: {
                CLSourceChip(label: source.ref.label, systemImage: source.isLecture ? "mic" : "book.pages")
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint(source.isLecture ? "Opens the lecture at this moment" : "Opens the page this question came from")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard(padding: 16)
    }

    private func reasons(_ item: StudyItem) -> some View {
        let left = app.myAnswerReportsLeft()
        return VStack(spacing: 0) {
            reasonRow(.answerWrong, title: "The answer is wrong")
            reasonRow(.questionUnclear, title: "The question doesn't make sense")
            if !given.isEmpty {
                reasonRow(.myAnswerCounts, title: "My answer should count",
                          detail: left == 0 ? "That's today's 3. It comes back tomorrow." : nil, enabled: left > 0)
            }
            reasonRow(.other, title: "Something else")
            if reason == .other {
                TextField("What's off? (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .clFont(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .onChange(of: note) { _, words in
                        if words.count > RelayLimits.reportNote { note = String(words.prefix(RelayLimits.reportNote)) }
                    }
            }
        }
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.list, style: .continuous))
    }

    private func reasonRow(_ choice: CheckReport.Reason, title: LocalizedStringResource, detail: LocalizedStringResource? = nil,
                           enabled: Bool = true) -> some View {
        Button {
            CLHaptics.select()
            withAnimation(CLMotion.fade) { reason = choice }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: reason == choice ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(reason == choice ? CLColor.tangerineInk : CLColor.ink3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .clFont(.body)
                        .foregroundStyle(enabled ? CLColor.ink : CLColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .clFont(.footnote)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: CLMetrics.minHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(reason == choice ? [.isSelected] : [])
    }

    private func checking(_ source: ReportSource?) -> some View {
        HStack(spacing: 12) {
            CapView(.working, size: 60, interactive: false)
            Text("Cap is re-reading \(source?.place ?? String(localized: "the page"))…")
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func outcome(_ result: RecheckResult, source: ReportSource?) -> some View {
        let place = source?.place ?? String(localized: "the page")
        return VStack(alignment: .leading, spacing: CLSpace.l) {
            HStack(alignment: .center, spacing: 12) {
                CapView(result == .fixed ? .nice : .answerShown, size: 60, interactive: false)
                Text(LooksWrongCopy.outcome(result, place: place, inSession: inSession))
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            if let why = app.recheckReason(for: itemID), !why.isEmpty {
                Text(verbatim: why)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if result == .needsEdit {
                Button("Edit") {
                    handedOff = true
                    app.router.present(.editItem(itemID))
                }
                .buttonStyle(.cl(.soft))
            }
            Button(inSession && result != .stands ? "Continue" : "Done") { dismiss() }
                .buttonStyle(.cl(.primary))
        }
    }

    /// Reported earlier and not settled yet.
    private func waiting(_ source: ReportSource) -> some View {
        VStack(alignment: .leading, spacing: CLSpace.l) {
            Text(LooksWrongCopy.outcome(.queued, place: source.place, inSession: inSession))
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            sourceCard(source)
            Button("Put it back in my sessions") {
                CLHaptics.tap()
                app.withdrawReport(itemID)
                dismiss()
            }
            .buttonStyle(.cl(.soft))
            Button("Done") { dismiss() }
                .buttonStyle(.cl(.primary))
        }
    }

    /// Nothing for Cap to read, or no Cap to ask: Edit and Skip.
    private func noCheck(source: ReportSource?) -> some View {
        VStack(alignment: .leading, spacing: CLSpace.l) {
            Text("What looks wrong?")
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .accessibilityAddTraits(.isHeader)
            if let source {
                sourceCard(source)
            } else {
                Text("This question has no page behind it, so Cap has nothing to check it against. You can change it yourself.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Edit") {
                handedOff = true
                app.router.present(.editItem(itemID))
            }
            .buttonStyle(.cl(.primary))
            if inSession {
                Button("Skip this question") {
                    app.deliverRecheck(itemID, result: .queued, given: nil)
                    dismiss()
                }
                .buttonStyle(.cl(.soft))
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(.cl(.soft))
            }
        }
    }

    // MARK: Actions

    private func start() {
        guard !didStart else { return }
        didStart = true
        #if DEBUG
        switch TestHarness.value("CRAMLESS_LOOKSWRONG") {
        case "checking": phase = .checking
        case "fixed": phase = .outcome(.fixed)
        case "stands": phase = .outcome(.stands)
        case "retired": phase = .outcome(.retired)
        case "queued": phase = .outcome(.queued)
        default: break
        }
        #endif
    }

    private func ask(_ item: StudyItem, source: ReportSource) {
        guard let reason else { return }
        CLHaptics.tap()
        let answer = given.isEmpty ? nil : given
        // Own words go back to the grader, which is the check made for them.
        if reason == .myAnswerCounts, item.kind.isOwnWords, let answer, inSession,
           app.ai.canGradeAgain(app.gradeSubject(for: item), answer: .text(answer)), app.spendMyAnswerReport() {
            app.deliverRecheck(itemID, result: .regrade, given: answer)
            handedOff = true
            dismiss()
            return
        }
        guard app.reportItem(itemID, reason: reason, given: answer, note: note) else { return }
        guard app.ai.hasCloudConsent else {
            // The consent sheet takes this one's place. Consent runs the check; until then it counts for nothing.
            app.deliverRecheck(itemID, result: .queued, given: answer)
            handedOff = true
            app.router.present(.consent(.cloudAI(feature: String(localized: "Check this question"))))
            return
        }
        withAnimation(CLMotion.fade) { phase = .checking }
        Task {
            let result = await app.recheck(itemID)
            guard phase == .checking else { return }
            if result == .fixed { CLHaptics.success() }
            withAnimation(CLMotion.fade) { phase = .outcome(result) }
            AccessibilityNotification.Announcement(LooksWrongCopy.outcome(result, place: source.place, inSession: inSession)).post()
        }
    }

    /// The sheet went away: the open question acts on how it came out. Closed while Cap was reading, it counts for nothing for now.
    private func finish() {
        guard !handedOff else { return }
        switch phase {
        case .choose: break
        case .checking: app.deliverRecheck(itemID, result: .queued, given: given.isEmpty ? nil : given)
        case .outcome(let result): app.deliverRecheck(itemID, result: result, given: given.isEmpty ? nil : given)
        }
    }
}

/// The sheet's words for how a report came out.
enum LooksWrongCopy {
    static func outcome(_ result: RecheckResult, place: String, inSession: Bool) -> String {
        switch result {
        case .fixed:
            inSession ? String(localized: "You were right. Cap fixed the question. This one counts as right.") : String(localized: "You were right. Cap fixed the question.")
        case .stands:
            String(localized: "The page agrees with the answer.")
        case .retired:
            String(localized: "Cap couldn't back this question with \(place), so it's out of your sessions.")
        case .needsEdit:
            String(localized: "Cap found a mistake, and this kind of question needs your edit. It's out of your sessions until then.")
        case .queued:
            String(localized: "Cap will check this when you're online. It won't count against you.")
        case .regrade:
            String(localized: "Cap is grading it again.")
        }
    }
}
