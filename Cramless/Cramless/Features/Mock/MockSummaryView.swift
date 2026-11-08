import SwiftUI

/// The end of a mock: "You scored 76%." and "Cap expected 79%.", then the weakest topics with a practice round each, and a way to
/// see every answer. Answers no model graded wait for the person's mark ("Mark 3 answers yourself"): they count once marked.
struct MockSummaryView: View {
    let runner: MockRunner
    let onDone: () -> Void
    let onPractice: (SessionRequest) -> Void

    @Environment(AppModel.self) private var app
    @State private var showsMarking = false
    @State private var showsAnswers = false
    @State private var told = false

    var body: some View {
        QuestionScroll {
            VStack(spacing: 16) {
                hero
                if !runner.toMark.isEmpty { markCard }
                if let result = runner.result, !result.weakest.isEmpty {
                    topics(result)
                }
                if runner.result?.score != nil {
                    Text(verbatim: MockCopy.tomorrow)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                AccessibilityOnly { secondary }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .sessionFooter {
            // One tangerine button: while answers wait for a mark, marking is what moves things forward.
            Button("Done", action: onDone)
                .buttonStyle(.cl(runner.toMark.isEmpty ? .primary : .soft))
        } secondary: {
            secondary
        }
        .sheet(isPresented: $showsMarking) {
            MockMarkingSheet(runner: runner)
                .environment(\.clDyslexicFont, app.settings.dyslexicFont)
        }
        .sheet(isPresented: $showsAnswers) {
            MockAnswersSheet(runner: runner)
                .environment(\.clDyslexicFont, app.settings.dyslexicFont)
        }
        .task {
            guard !told else { return }
            told = true
            CLFeel.play(.done)
            // A badge the sitting earned is told here, and opens from the toast.
            if let badge = runner.game.badges.first, !app.settings.quietMode {
                app.router.toast("New badge: \(String(localized: badge.title))", systemImage: "medal.fill", actionTitle: "See it",
                                 action: .present(.badge(badge)))
            }
            #if DEBUG
            if TestHarness.value("CRAMLESS_MOCK") == "selfcheck", !runner.toMark.isEmpty {
                try? await nap(600)
                showsMarking = true
            }
            #endif
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 8) {
            CapView(pose: capPose, size: 120)
            if let result = runner.result, let score = result.score {
                Text(verbatim: MockCopy.scored(score))
                    .clFont(.brandTitle(32))
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: MockCopy.expected(result.expected))
                    .clFont(.title3)
                    .foregroundStyle(CLColor.ink2)
                if let scope = MockCopy.scopeLine(counted: result.counted + runner.toMark.count, total: result.total, inTime: runner.answeredInTime) {
                    Text(verbatim: scope)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if !runner.toMark.isEmpty {
                Text("Mark your answers to see your score.")
                    .clFont(.title2)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Text("Nothing to mark.")
                    .clFont(.title2)
                    .foregroundStyle(CLColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("You left every question blank. Your plan hasn't changed.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var capPose: CapPose {
        switch runner.result?.verdict {
        case .better: .proud
        case .asExpected: .nice
        case .below: .notYet
        case nil: .study
        }
    }

    // MARK: Marking

    private var markCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("They count once you've marked them.")
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                CLHaptics.tap()
                showsMarking = true
            } label: {
                Text(verbatim: MockCopy.markYourself(runner.toMark.count))
            }
            .buttonStyle(.cl(.primary, size: .medium))
        }
        .clCard()
    }

    // MARK: Topics

    /// The topics to practice, weakest first, each with its round. (Every topic's answers are under "See your answers".)
    private func topics(_ result: MockResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CLEyebrow(text: "Practice these").accessibilityAddTraits(.isHeader)
            ForEach(result.weakest) { topic in
                topicRow(topic)
            }
        }
        .clCard()
    }

    private func topicRow(_ topic: MockResult.Topic) -> some View {
        ReflowStack(verticalAlignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: topic.name)
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(CLFormat.percent(topic.score)).clFont(.number(15, .bold)).foregroundStyle(CLColor.ink)
                }
                .accessibilityElement(children: .combine)
                CLBar(value: topic.score).accessibilityHidden(true)
            }
            Button {
                CLHaptics.tap()
                onPractice(SessionRequest(kind: .practice, courseID: runner.courseID, examID: runner.examID, minutes: 5, topicID: topic.id))
            } label: {
                Label("Practice", systemImage: "play.fill")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.tangerineInk)
                    .padding(.horizontal, 14)
                    .frame(minHeight: CLMetrics.minHitTarget)
                    .background(CLColor.tangerineSoft, in: Capsule())
                    .fixedSize()
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("Practice \(topic.name)"))
        }
    }

    @ViewBuilder private var secondary: some View {
        Button {
            CLHaptics.tap()
            showsAnswers = true
        } label: {
            Text("See your answers")
        }
        .buttonStyle(.cl(.ghost, size: .medium))
    }
}

// MARK: - Marking it yourself

/// One own-words answer at a time: the question, the person's answer, the model answer and the key ideas to tick. "None of these" is a mark like
/// any other; with nothing found and nothing touched, Save waits (`SelfCheck.canContinue`).
private struct MockMarkingSheet: View {
    let runner: MockRunner

    @Environment(\.dismiss) private var dismiss
    /// The first question left is what's shown: marking one moves on by itself.
    @State private var entry: SessionEntry?
    @State private var ticked: Set<String> = []
    @State private var touched = false
    @State private var found = false

    init(runner: MockRunner) {
        self.runner = runner
        // Set before the first body: an empty sheet closes itself.
        _entry = State(initialValue: runner.toMark.first)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let entry, let item = runner.item(entry) {
                    ScrollView {
                        content(entry: entry, item: item)
                            .frame(maxWidth: CLMetrics.readableWidth, alignment: .leading)
                            .padding(.horizontal, CLSpace.gutter)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button("Save this mark") { save(entry) }
                            .buttonStyle(.cl(.primary))
                            .disabled(!SelfCheck.canContinue(changedByPerson: touched, rulesFoundIdeas: found))
                            .padding(.horizontal, CLSpace.gutter)
                            .padding(.bottom, 8)
                    }
                    .id(entry.id)
                } else {
                    Color.clear.onAppear { dismiss() }
                }
            }
            .clScreenBackground()
            .navigationTitle(Text(verbatim: MockCopy.markYourself(runner.toMark.count)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(CLColor.background)
        .onAppear { load(runner.toMark.first) }
    }

    private func content(entry: SessionEntry, item: StudyItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.prompt)
                .clFont(.title3)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            answerBox("Your answer", runner.given(for: item.id).text.clTrimmed)
            answerBox("The answer", item.answer)
            VStack(alignment: .leading, spacing: 0) {
                CLEyebrow(text: "Tick what you had")
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(item.keyIdeas, id: \.id) { idea in
                    checkRow(idea.label, isOn: ticked.contains(idea.id)) {
                        CLHaptics.select()
                        withAnimation(CLMotion.snap) {
                            if ticked.contains(idea.id) { ticked.remove(idea.id) } else { ticked.insert(idea.id) }
                            touched = true
                        }
                    }
                }
                checkRow("None of these", isOn: touched && ticked.isEmpty) {
                    CLHaptics.select()
                    withAnimation(CLMotion.snap) {
                        ticked.removeAll()
                        touched = true
                    }
                }
            }
        }
    }

    private func answerBox(_ title: LocalizedStringResource, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CLEyebrow(text: title)
            Text(verbatim: text)
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func checkRow(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? CLColor.mintInk : CLColor.ink3)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(verbatim: label)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(isOn ? Text("Ticked") : Text("Not ticked"))
        .accessibilityAddTraits(.isToggle)
    }

    private func checkRow(_ label: LocalizedStringResource, isOn: Bool, action: @escaping () -> Void) -> some View {
        checkRow(String(localized: label), isOn: isOn, action: action)
    }

    private func load(_ next: SessionEntry?) {
        entry = next
        guard let next, case .toMark(_, let found) = runner.marks[next.itemID] else { return }
        ticked = found
        self.found = !found.isEmpty
        touched = false
    }

    private func save(_ entry: SessionEntry) {
        CLFeel.play(.rated)
        runner.mark(entry.itemID, ticked: ticked)
        load(runner.toMark.first)
    }
}

// MARK: - See your answers

/// Every question with what the person gave, the answer, and how it counted.
private struct MockAnswersSheet: View {
    let runner: MockRunner

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(runner.plan.entries.enumerated()), id: \.element.id) { index, entry in
                        if let item = runner.item(entry) {
                            row(index: index, entry: entry, item: item)
                        }
                    }
                }
                .frame(maxWidth: CLMetrics.readableWidth, alignment: .leading)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .clScreenBackground()
            .navigationTitle("Your answers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(CLColor.background)
    }

    private func row(index: Int, entry: SessionEntry, item: StudyItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(index + 1). \(item.kind.displayName)")
                    .clFont(.eyebrow)
                    .foregroundStyle(CLColor.ink3)
                Spacer(minLength: 8)
                pill(runner.marks[entry.itemID] ?? .blank)
            }
            Text(item.prompt.isEmpty ? LibraryFormat.clozeDisplay(item.cloze?.text ?? "") : prompt(of: item))
                .clFont(.bodyEmphasis)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let given = runner.answerText(for: entry) {
                Text("You: \(given)")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Answer: \(item.answer)")
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !item.explanation.isEmpty {
                Text(verbatim: item.explanation)
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ref = item.sourceRef, app.opens(ref) {
                sourceLink(ref)
            }
        }
        .clCard(padding: 16)
        .accessibilityElement(children: .contain)
    }

    /// A fill-in's sentence reads with its blank; anything else, its question.
    private func prompt(of item: StudyItem) -> String {
        if item.kind == .cloze, let text = item.cloze?.text { return LibraryFormat.clozeDisplay(text) }
        return item.prompt
    }

    /// Opens the page or the lecture it came from, inside this sheet.
    private func sourceLink(_ ref: SourceRef) -> some View {
        let isLecture = ref.start != nil || app.source(ref.sourceID)?.kind == .lecture
        return NavigationLink {
            if isLecture {
                LectureNotesView(sourceID: ref.sourceID, focusTime: ref.start)
            } else {
                SourcePageView(sourceID: ref.sourceID, pageIndex: ref.pageIndex ?? 0, highlight: ref.anchorIDs)
            }
        } label: {
            CLSourceChip(label: ref.label, systemImage: isLecture ? "mic" : "book.pages")
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder private func pill(_ mark: MockRunner.Mark) -> some View {
        switch mark {
        case .blank:
            CLPill(text: "Left blank", tone: .neutral)
        case .toMark:
            CLPill(text: "To mark", tone: .sky, systemImage: "pencil")
        case .graded(let score, _), .selfMarked(let score):
            if score >= Grading.goodFrom {
                CLPill(text: "Right", tone: .mint, systemImage: "checkmark")
            } else if score >= Grading.againBelow {
                CLPill(text: "Partly", tone: .sun, systemImage: "circle.lefthalf.filled")
            } else {
                CLPill(text: "Not yet", tone: .rose, systemImage: "xmark")
            }
        }
    }
}
