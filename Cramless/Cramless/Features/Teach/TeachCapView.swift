import SwiftUI

/// Teach Cap: the student explains a topic to him, the way they would to someone who missed the class. Saying a thing shows what's really stuck.
///
/// Cap asks; the student says it or types it, and his notes fill in as he hears each idea (`TeachSession`). Done shows what was covered ("4 of 6 ideas"), with one
/// follow-up on the first missed idea and the missing idea as a new question. Never a percentage.
///
/// DEBUG: `CRAMLESS_ROUTE=teach[:n]`, `CRAMLESS_TEACH_SCRIPT=good|thin`, `CRAMLESS_TEACH_STATE=prompt|listening|check|followup|added` (`TeachDebug`).
struct TeachCapView: View {
    let topicID: UUID

    @Environment(AppModel.self) private var app
    @State private var session: TeachSession?
    @State private var loaded = false

    var body: some View {
        ZStack {
            CLColor.background.ignoresSafeArea()
            if let session {
                TeachContent(session: session, onClose: { app.router.dismissCover() })
            } else if loaded {
                TeachUnavailable(onClose: { app.router.dismissCover() })
            }
        }
        .captureDebugCanvas()
        .task {
            guard !loaded else { return }
            if let plan = app.teachPlan(topicID: topicID) {
                #if DEBUG
                let ports: TeachPorts? = app.config.isHarness ? TeachDebug.ports(plan: plan) : nil
                #else
                let ports: TeachPorts? = nil
                #endif
                let made = TeachSession(app: app, plan: plan, ports: ports)
                session = made
                loaded = true
                CLHaptics.prepare()
                #if DEBUG
                await TeachDebug.play(made)
                #endif
            } else {
                loaded = true
            }
        }
        .onDisappear { session?.close() }
    }
}

private struct TeachUnavailable: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            CapView(pose: .ask, size: 120, idle: .breathe)
            Text(TeachCopy.tooFew)
                .clFont(.title3)
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Done", action: onClose)
                .buttonStyle(.cl(.primary))
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.bottom, 12)
    }
}

private struct TeachContent: View {
    let session: TeachSession
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CLIconButton(systemImage: "xmark", label: String(localized: "Close"), action: onClose)
                Spacer()
                if session.phase == .listening || session.phase == .followUpListening {
                    Text(session.listenStartedAt, style: .timer)
                        .clFont(.number(15, .bold))
                        .foregroundStyle(CLColor.ink2)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 58, minHeight: 32)
                        .glassEffect(.regular, in: Capsule())
                        .accessibilityLabel(Text("Time listening"))
                }
            }
            .padding(.horizontal, 12)
            page
                .transition(.opacity)
        }
        .animation(CLMotion.settle, value: session.phase)
    }

    @ViewBuilder private var page: some View {
        switch session.phase {
        case .prompt, .gettingReady:
            if session.followUp == nil { TeachPromptPage(session: session) } else { TeachFollowUpPage(session: session, onDone: onClose) }
        case .listening, .typing:
            TeachListeningPage(session: session)
        case .check:
            TeachCheckPage(session: session, onDone: onClose)
        case .followUp, .followUpListening, .followUpTyping, .followUpDone:
            TeachFollowUpPage(session: session, onDone: onClose)
        }
    }
}

/// A page: what scrolls, and its buttons, pinned below it except at the largest text sizes, where they would take the screen.
private struct TeachPage<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            ScrollView {
                content
                footer
            }
        } else {
            VStack(spacing: 0) {
                ScrollView { content }
                    .scrollBounceBehavior(.basedOnSize)
                footer
            }
        }
    }
}

// MARK: - Cap asks

private struct TeachPromptPage: View {
    let session: TeachSession

    var body: some View {
        TeachPage {
            VStack(spacing: 14) {
                CapView(pose: .ask, size: 130, idle: .breathe)
                Text(TeachCopy.title)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink2)
                Text(TeachCopy.ask(session.plan.topicName))
                    .clFont(.title2)
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let note = session.note {
                    Text(note)
                        .clFont(.callout)
                        .foregroundStyle(CLColor.sunInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(TeachCopy.privacy)
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
        } footer: {
            VStack(spacing: 8) {
                if case .gettingReady(let progress) = session.phase {
                    Button {} label: { Text(OutLoudCopy.downloading(progress)) }
                        .buttonStyle(.cl(.soft))
                        .disabled(true)
                } else {
                    Button {
                        CLHaptics.commit()
                        session.sayIt()
                    } label: {
                        Label { Text(TeachCopy.sayIt) } icon: { Image(systemName: "mic.fill") }
                    }
                    .buttonStyle(.cl(.primary))
                    Button {
                        CLHaptics.tap()
                        session.typeIt()
                    } label: {
                        Label { Text(TeachCopy.typeIt) } icon: { Image(systemName: "keyboard") }
                    }
                    .buttonStyle(.cl(.soft))
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - The student explains

private struct TeachListeningPage: View {
    let session: TeachSession

    @Environment(\.clReduceMotion) private var reduceMotion
    @FocusState private var editorFocused: Bool
    @State private var text = ""

    private var isTyping: Bool { session.phase == .typing }

    var body: some View {
        TeachPage {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    CapView(pose: .listen, size: 92, motion: .nod, idle: .breathe, trigger: session.nods, interactive: false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isTyping ? TeachCopy.typeHere : TeachCopy.listening)
                            .clFont(.title3)
                            .foregroundStyle(CLColor.ink)
                        Text(TeachCopy.ask(session.plan.topicName))
                            .clFont(.footnote)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if let note = session.note {
                    Text(note)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.sunInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isTyping { editor } else { TeachHeardWords(session: session) }
                TeachNotes(session: session)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            VStack(spacing: 10) {
                if !isTyping {
                    LectureLevelWaveform(levels: session.levels, active: true, animated: !reduceMotion)
                        .frame(height: 44)
                        .clipped()
                }
                Button {
                    CLHaptics.commit()
                    session.done()
                } label: {
                    Text(TeachCopy.done)
                }
                .buttonStyle(.cl(.primary))
                .disabled(isTyping && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 12)
        }
        .onAppear { if isTyping { editorFocused = true } }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .focused($editorFocused)
            .clFont(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 140)
            .padding(10)
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous))
            .onChange(of: text) { _, value in session.typed(value) }
            .accessibilityLabel(Text(TeachCopy.typeHere))
    }
}

/// The words as they come. Only this view reads them.
private struct TeachHeardWords: View {
    let session: TeachSession

    var body: some View {
        if !session.words.isEmpty {
            Text(verbatim: session.words)
                .clFont(.body)
                .italic()
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(CLColor.skySoft, in: RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous))
        }
    }
}

/// Cap's notepad: each idea, as he hears it. What hasn't been said isn't shown: that would be the answer.
private struct TeachNotes: View {
    let session: TeachSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TeachCopy.notes)
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(CLColor.ink)
            if session.liveHitLabels.isEmpty {
                Text(TeachCopy.notesEmpty)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(session.liveHitLabels, id: \.self) { label in
                    Label {
                        Text(verbatim: label)
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(CLColor.mintInk)
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard()
        .animation(CLMotion.settle, value: session.liveHitLabels)
    }
}

// MARK: - What you covered

private struct TeachCheckPage: View {
    let session: TeachSession
    let onDone: () -> Void

    var body: some View {
        let covered = session.coveredCount
        let total = session.plan.ideas.count
        TeachPage {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    CapView(moment(covered: covered, total: total), size: 92, interactive: false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(TeachCopy.covered)
                            .clFont(.title3)
                            .foregroundStyle(CLColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        ReflowPill(text: TeachCopy.ideasCount(covered, of: total), tone: covered == total ? .mint : .sky)
                        if session.isRefining {
                            Text(TeachCopy.doubleChecking)
                                .clFont(.footnote)
                                .foregroundStyle(CLColor.ink3)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if !session.isRefining {
                    Text(session.isSelfCheck ? TeachCopy.tickWhat : TeachCopy.checkLine(covered: covered, total: total))
                        .clFont(.callout)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(session.plan.ideas) { idea in
                        TeachIdeaRow(idea: idea, covered: session.covered.contains(idea.id), ticks: session.isSelfCheck) {
                            CLHaptics.select()
                            session.toggle(idea)
                        }
                    }
                }
                .clCard()
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            VStack(spacing: 8) {
                if session.firstMissing != nil, !session.isRefining {
                    Button {
                        CLHaptics.tap()
                        session.askFollowUp()
                    } label: {
                        Text(TeachCopy.answerOneMore)
                    }
                    .buttonStyle(.cl(.primary))
                    Button(action: onDone) { Text(TeachCopy.done) }
                        .buttonStyle(.cl(.soft))
                } else {
                    Button(action: onDone) { Text(TeachCopy.done) }
                        .buttonStyle(.cl(.primary))
                        .disabled(session.isRefining)
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 12)
        }
    }

    private func moment(covered: Int, total: Int) -> CapMoment {
        if session.isRefining { return .working }
        if covered == total { return .nice }
        return covered == 0 ? CapMoment(pose: .ask, idle: .breathe) : .almost
    }
}

/// An idea and whether it was covered: a mark as well as a colour. In a self-check it is the person's to tick.
private struct TeachIdeaRow: View {
    let idea: TeachIdea
    let covered: Bool
    let ticks: Bool
    let toggle: () -> Void

    var body: some View {
        if ticks {
            Button(action: toggle) { row.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityAddTraits(covered ? [.isSelected] : [])
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: covered ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(covered ? CLColor.mintInk : CLColor.ink3)
                .accessibilityHidden(true)
            Text(verbatim: idea.label)
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(minHeight: CLMetrics.minHitTarget)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(covered ? "You covered this" : "Not covered"))
    }
}

// MARK: - One more question

private struct TeachFollowUpPage: View {
    let session: TeachSession
    let onDone: () -> Void

    @Environment(\.clReduceMotion) private var reduceMotion
    @FocusState private var editorFocused: Bool
    @State private var text = ""

    private var isDone: Bool { session.phase == .followUpDone }
    private var isTyping: Bool { session.phase == .followUpTyping }
    private var isListening: Bool { session.phase == .followUpListening }

    var body: some View {
        TeachPage {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    CapView(moment, size: 92, interactive: false)
                    Text(TeachCopy.oneMore)
                        .clFont(.title3)
                        .foregroundStyle(CLColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                if let followUp = session.followUp {
                    Text(verbatim: followUp.prompt)
                        .clFont(.title2)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clCard()
                }
                if let note = session.note {
                    Text(note)
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.sunInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isTyping {
                    TextEditor(text: $text)
                        .focused($editorFocused)
                        .clFont(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .padding(10)
                        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous))
                        .onChange(of: text) { _, value in session.typedFollowUp(value) }
                        .onAppear { editorFocused = true }
                        .accessibilityLabel(Text("Your answer"))
                } else if isListening, !session.followUpWords.isEmpty {
                    Text(verbatim: session.followUpWords)
                        .clFont(.body)
                        .italic()
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(CLColor.skySoft, in: RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous))
                }
                if isDone { verdict }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            buttons
                .padding(.horizontal, CLSpace.gutter)
                .padding(.bottom, 12)
        }
    }

    private var moment: CapMoment {
        if isListening { return CapMoment(pose: .listen, idle: .breathe) }
        guard isDone else { return CapMoment(pose: .ask, idle: .breathe) }
        if session.followUpRefining { return .working }
        guard let grade = session.followUpGrade, grade.mode != .selfCheck else { return .answerShown }
        switch grade.verdict {
        case .correct: return .nice
        case .partial: return .almost
        case .incorrect: return .notYet
        }
    }

    @ViewBuilder private var verdict: some View {
        if session.followUpRefining {
            Text(TeachCopy.doubleChecking)
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink3)
        } else if let grade = session.followUpGrade, let followUp = session.followUp {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline(grade))
                    .clFont(.headline)
                    .foregroundStyle(tone(grade).ink)
                if grade.verdict != .correct || grade.mode == .selfCheck {
                    Text(verbatim: followUp.answer)
                        .clFont(.body)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(tone(grade).fill, in: RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous))
            if let added = session.addedIdea {
                Label { Text(TeachCopy.added(added)) } icon: { Image(systemName: "checkmark.circle.fill") }
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.mintInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func headline(_ grade: GradeOutcome) -> LocalizedStringResource {
        if grade.mode == .selfCheck { return SessionCopy.selfCheckHeadline }
        return SessionCopy.headline(SessionRunner.Outcome(grade.verdict))
    }

    private func tone(_ grade: GradeOutcome) -> FeedbackTone {
        grade.mode == .selfCheck ? .neutral : FeedbackTone(grade.verdict)
    }

    @ViewBuilder private var buttons: some View {
        VStack(spacing: 8) {
            switch session.phase {
            case .gettingReady(let progress):
                Button {} label: { Text(OutLoudCopy.downloading(progress)) }
                    .buttonStyle(.cl(.soft))
                    .disabled(true)
            case .followUp:
                Button {
                    CLHaptics.commit()
                    session.sayFollowUp()
                } label: {
                    Label { Text(TeachCopy.sayIt) } icon: { Image(systemName: "mic.fill") }
                }
                .buttonStyle(.cl(.primary))
                Button {
                    CLHaptics.tap()
                    session.typeFollowUp()
                } label: {
                    Label { Text(TeachCopy.typeIt) } icon: { Image(systemName: "keyboard") }
                }
                .buttonStyle(.cl(.soft))
            case .followUpListening, .followUpTyping:
                if isListening {
                    LectureLevelWaveform(levels: session.levels, active: true, animated: !reduceMotion)
                        .frame(height: 44)
                        .clipped()
                }
                Button {
                    CLHaptics.commit()
                    session.doneFollowUp()
                } label: {
                    Text(TeachCopy.done)
                }
                .buttonStyle(.cl(.primary))
                .disabled(isTyping && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            default:
                if session.followUpGrade?.mode == .selfCheck, session.followUpRating == nil {
                    Button {
                        CLHaptics.tap()
                        session.markFollowUp(hadIt: true)
                    } label: { Text(TeachCopy.hadIt) }
                    .buttonStyle(.cl(.primary))
                    Button {
                        CLHaptics.tap()
                        session.markFollowUp(hadIt: false)
                    } label: { Text(TeachCopy.notYet) }
                    .buttonStyle(.cl(.soft))
                } else if !session.followUpRefining {
                    if session.addedIdea == nil, session.followUpRating != .good, session.followUpRating != .easy {
                        Button {
                            CLHaptics.commit()
                            session.addMissingIdea()
                        } label: { Text(TeachCopy.addMissing).multilineTextAlignment(.center) }
                        .buttonStyle(.cl(.soft))
                    }
                    Button(action: onDone) { Text(TeachCopy.done) }
                        .buttonStyle(.cl(.primary))
                }
            }
        }
    }
}
