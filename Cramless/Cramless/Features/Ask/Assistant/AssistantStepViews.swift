import SwiftUI

// What Cap's assistant does, shown in the chat. Each tool the model calls is a card: it works (the work is shown as it
// happens), proposes (the student adds, changes or skips), and settles (added, with Undo; skipped; taken back; or failed).
// The same card is shown while a reply is being written and afterwards, so nothing jumps when the reply is saved.
//
// Harness (DEBUG): `CRAMLESS_ASSISTANT=<script>` sends a message through the mock relay and lets it play (see `AskDemo`).

/// What the student can do with a step. Nil closures (a reply still being written) hide the buttons.
struct AssistantStepActions {
    var approve: ((AssistantStep) -> Void)?
    var skip: ((AssistantStep) -> Void)?
    var undo: ((AssistantStep) -> Void)?
    var reopen: ((AssistantStep) -> Void)?
    var edit: ((AssistantStep, (inout AssistantStep) -> Void) -> Void)?
    var perform: ((AssistantPayload) -> Void)?
    var upgrade: (() -> Void)?

    /// The reply is still being written.
    static let live = AssistantStepActions()

    var isLive: Bool { approve == nil }
}

/// The steps of one reply, one card each.
struct AssistantStepList: View {
    let steps: [AssistantStep]
    var actions: AssistantStepActions = .live
    /// A reply being written: cards slide in, tick and sound. A saved reply shows its steps as they are.
    var animated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps) { step in
                AssistantStepView(step: step, actions: actions, animated: animated)
                    .transition(animated
                        ? .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottom)),
                                      removal: .opacity)
                        : .identity)
            }
        }
        .animation(animated ? CLMotion.settle : nil, value: steps.map(\.id))
    }
}

struct AssistantStepView: View {
    let step: AssistantStep
    let actions: AssistantStepActions
    var animated = false

    var body: some View {
        switch step.payload {
        case .lookup(let lookup): LookupStepView(step: step, lookup: lookup, animated: animated)
        case .cards: DraftsStepView(step: step, actions: actions, animated: animated)
        case .questions: DraftsStepView(step: step, actions: actions, animated: animated)
        case .note(let note): NoteStepView(step: step, note: note, actions: actions, animated: animated)
        case .exam(let plan): ExamStepView(step: step, plan: plan, actions: actions, animated: animated)
        case .practice, .open: OfferStepView(step: step, actions: actions)
        case .research(let result): ResearchStepView(step: step, result: result, actions: actions, animated: animated)
        case .none: FailedStepView(step: step, actions: actions)
        }
    }
}

// MARK: - The card

extension AssistantStep {
    var accent: CourseColor {
        switch tool {
        case .createFlashcards: .tangerine
        case .createQuizQuestions: .sky
        case .createNote: .sun
        case .createExam: .mint
        case .researchWeb: .sky
        case .startPractice: .tangerine
        case .openScreen, .searchNotes: .sky
        }
    }

    var icon: String {
        switch tool {
        case .searchNotes: "text.book.closed"
        case .createFlashcards: "rectangle.stack"
        case .createQuizQuestions: "checklist"
        case .createNote: "doc.text"
        case .createExam: "calendar"
        case .startPractice: "bolt.fill"
        case .openScreen: "arrow.up.right.square"
        case .researchWeb: "globe"
        }
    }
}

/// A step's frame: icon, title, status, then the content, then what the student can do.
struct StepCard<Content: View>: View {
    let step: AssistantStep
    var actions: AssistantStepActions = .live
    /// "Add 6 to Bio 101": the one button of a proposal.
    var addTitle: String?
    var addEnabled = true
    var subtitle: String?
    @ViewBuilder var content: Content

    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var working: Bool { step.status == .working }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { border }
        .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
        .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)
        .opacity(step.status == .skipped || step.status == .undone ? 0.72 : 1)
        .animation(CLMotion.settle, value: step.status)
        .accessibilityElement(children: .contain)
    }

    private var border: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !working || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let glow = working && !reduceMotion ? 0.35 + 0.35 * (sin(t * 3.2) + 1) / 2 : 0
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(working ? step.accent.fill.opacity(glow) : step.status == .proposed ? step.accent.fill.opacity(0.55) : CLColor.hairline,
                              lineWidth: working || step.status == .proposed ? 1.5 : 0.5)
        }
        .allowsHitTesting(false)
    }

    private var badge: some View {
        ZStack {
            CLIconBadge(systemImage: step.icon, tint: step.accent, size: 40)
                .symbolEffect(.pulse, isActive: working && !reduceMotion)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: step.title)
                .clFont(.bodyEmphasis)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let line = subtitleLine {
                Text(verbatim: line).clFont(.footnote).foregroundStyle(CLColor.ink2).lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if typeSize.isAccessibilitySize {
            // Big text: the title keeps the card's whole width and the status sits under it, instead of squeezing the title.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    badge
                    titleBlock
                }
                StatusChip(step: step)
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                badge
                titleBlock
                Spacer(minLength: 6)
                StatusChip(step: step)
            }
        }
    }

    private var subtitleLine: String? {
        if let subtitle { return subtitle }
        let parts = [step.courseName.clNonEmpty].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var footer: some View {
        switch step.status {
        case .proposed where !actions.isLive:
            HStack(spacing: 10) {
                Button("Skip") { CLHaptics.select(); actions.skip?(step) }
                    .buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
                Spacer(minLength: 0)
                if let addTitle {
                    Button { actions.approve?(step) } label: { Text(verbatim: addTitle) }
                        .buttonStyle(.cl(.primary, size: .small, fullWidth: false))
                        .disabled(!addEnabled)
                }
            }
        case .applied:
            AppliedFooter(step: step, actions: actions)
        case .skipped where !actions.isLive, .undone where !actions.isLive:
            HStack {
                Text(step.status == .undone ? "Taken back" : "Skipped").clFont(.footnoteEmphasis).foregroundStyle(CLColor.ink3)
                Spacer(minLength: 0)
                if step.payloadCanReopen {
                    Button(step.status == .undone ? "Add again" : "Add after all") { CLHaptics.select(); actions.reopen?(step) }
                        .buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
                }
            }
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                if let detail = step.detail {
                    Text(verbatim: detail).clFont(.footnote).foregroundStyle(CLColor.ink2).fixedSize(horizontal: false, vertical: true)
                }
                if step.needsPro, !actions.isLive {
                    Button("See Capling Pro") { actions.upgrade?() }
                        .buttonStyle(.cl(.primary, size: .small, fullWidth: false))
                }
            }
        default:
            EmptyView()
        }
    }
}

extension AssistantStep {
    var payloadCanReopen: Bool {
        switch payload {
        case .cards, .questions, .note, .exam, .research: true
        default: false
        }
    }
}

/// "Writing…", "Ready", "Added", "Skipped", "Couldn't".
struct StatusChip: View {
    let step: AssistantStep

    var body: some View {
        switch step.status {
        case .working:
            HStack(spacing: 6) {
                WorkingDots(tint: step.accent.ink)
                Text("Working").clFont(.caption).fontWeight(.semibold).foregroundStyle(step.accent.ink)
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 24)
            .background(step.accent.soft, in: Capsule())
        case .proposed:
            CLPill(text: "Your call", tone: .tangerine, systemImage: "hand.tap")
        case .applied:
            CLPill(text: "Added", tone: .mint, systemImage: "checkmark")
        case .skipped:
            CLPill(text: "Skipped", tone: .neutral)
        case .undone:
            CLPill(text: "Taken back", tone: .neutral, systemImage: "arrow.uturn.backward")
        case .failed:
            CLPill(text: "Didn't work", tone: .rose, systemImage: "exclamationmark")
        case .done:
            CLPill(text: "Read", tone: .sky, systemImage: "checkmark")
        case .offered:
            EmptyView()
        }
    }
}

// MARK: - A step that failed

struct FailedStepView: View {
    let step: AssistantStep
    let actions: AssistantStepActions

    var body: some View {
        StepCard(step: step, actions: actions) { EmptyView() }
    }
}

// MARK: - Added

/// Steps added a moment ago in this run of the app, so the tick draws itself and the sparkles fly only then, not every time an
/// old chat is opened.
@MainActor
enum AssistantFresh {
    private static var ids: Set<String> = []

    static func mark(_ id: String) { ids.insert(id) }

    /// True once, for a step added just now.
    static func take(_ id: String) -> Bool { ids.remove(id) != nil }
}

/// "Added to Bio 101": the tick draws itself with a few sparkles when the step was just added, and Undo.
private struct AppliedFooter: View {
    let step: AssistantStep
    let actions: AssistantStepActions

    @State private var fresh: Bool
    @State private var drawn: Bool
    @State private var burst = 0

    init(step: AssistantStep, actions: AssistantStepActions) {
        self.step = step
        self.actions = actions
        let fresh = AssistantFresh.take(step.id)
        _fresh = State(initialValue: fresh)
        _drawn = State(initialValue: !fresh)
    }

    var body: some View {
        HStack(spacing: 8) {
            DrawnCheck(done: drawn, size: 20)
                .overlay { SparkBurst(trigger: burst, tint: CLColor.mint, count: 8, radius: 30) }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: step.courseName.isEmpty ? String(localized: "Added to your library") : String(localized: "Added to \(step.courseName)"))
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.mintInk)
                if step.auto {
                    Text("Cap did this because you switched on “Let Cap do it”.").clFont(.caption).foregroundStyle(CLColor.ink3)
                }
            }
            Spacer(minLength: 0)
            if !actions.isLive {
                Button("Undo") { CLHaptics.select(); actions.undo?(step) }
                    .buttonStyle(.cl(.ghost, size: .small, fullWidth: false))
            }
        }
        .task {
            guard fresh else { return }
            try? await nap(90)
            drawn = true
            burst += 1
        }
    }
}
