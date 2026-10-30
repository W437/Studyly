import SwiftUI

// The cards that are not decks: a note being written on a page, an exam on a calendar tile, a button for a practice session or
// a screen, and a lookup of the student's notes.

// MARK: - A note

/// A note Cap is writing: the page fills as the words arrive, with a caret. When it is done the student can read it, change it
/// or add it.
struct NoteStepView: View {
    let step: AssistantStep
    let note: NoteDraft
    let actions: AssistantStepActions
    var animated = false

    @State private var editing = false
    @State private var title = ""
    @State private var text = ""
    @State private var expanded = false

    private var working: Bool { step.status == .working }
    private var open: Bool { step.status == .proposed && !actions.isLive }

    var body: some View {
        StepCard(step: step, actions: actions, addTitle: "Add note") {
            VStack(alignment: .leading, spacing: 8) {
                page
                if open && !editing {
                    Button("Change the words") {
                        CLHaptics.tap()
                        title = note.title
                        text = note.body
                        withAnimation(CLMotion.settle) { editing = true }
                    }
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.skyInk)
                    .buttonStyle(.plain)
                    .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
                }
            }
        }
        .onChange(of: step.status) { old, new in
            if animated, new == .applied, old != .applied { CLFeel.play(.saved) }
        }
    }

    /// Always white, like paper, whatever the appearance.
    private var page: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editing {
                TextField("Title", text: $title)
                    .clFont(.bodyEmphasis)
                    .foregroundStyle(CLColor.night)
                TextEditor(text: $text)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.night)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                Button("Done") {
                    let t = title.clTrimmed
                    let b = text.clTrimmed
                    withAnimation(CLMotion.settle) { editing = false }
                    guard !b.isEmpty else { return }
                    actions.edit?(step) { s in s.payload = .note(NoteDraft(title: t.isEmpty ? note.title : t, body: b)); if !t.isEmpty { s.title = t } }
                }
                .buttonStyle(.cl(.soft, size: .small, fullWidth: false))
            } else {
                Text(verbatim: note.title.isEmpty ? String(localized: "New note") : note.title)
                    .clFont(.bodyEmphasis)
                    .foregroundStyle(CLColor.night)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(CLColor.night.opacity(0.08)).frame(height: 1)
                paperText(note.body)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CLColor.night.opacity(0.06)))
        .shadow(color: CLColor.night.opacity(0.08), radius: 6, y: 3)
        .workingShimmer(working && note.body.isEmpty)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder private func paperText(_ text: String) -> some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // While it is written: the last lines, so the page seems to scroll under the pen.
        let shown = working ? Array(lines.suffix(9)) : (expanded || lines.count <= 9 ? lines : Array(lines.prefix(8)))
        VStack(alignment: .leading, spacing: 3) {
            if working, lines.count > shown.count {
                Text("…").foregroundStyle(CLColor.night.opacity(0.4))
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { i, line in
                let last = working && i == shown.count - 1
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: line.isEmpty ? " " : line)
                        .clFont(isHeading(line) ? .subheadlineEmphasis : .subheadline)
                        .foregroundStyle(CLColor.night.opacity(isHeading(line) ? 1 : 0.82))
                        .fixedSize(horizontal: false, vertical: true)
                    if last { Caret() }
                }
            }
            if working && lines.isEmpty { Caret() }
            if !working, lines.count > 9 {
                Button(expanded ? "Show less" : "Read it all") { withAnimation(CLMotion.settle) { expanded.toggle() } }
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
                    .buttonStyle(.plain)
                    .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
            }
        }
    }

    private func isHeading(_ line: String) -> Bool {
        let t = line.clTrimmed
        return !t.isEmpty && t.count <= 40 && !t.hasSuffix(".") && !t.hasPrefix("•") && !t.hasPrefix("-")
            && line.split(separator: " ").count <= 5
    }
}

/// A blinking pen.
private struct Caret: View {
    @Environment(\.clReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: reduceMotion)) { timeline in
            let on = reduceMotion || Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Rectangle().fill(CLColor.tangerine).frame(width: 2, height: 15).opacity(on ? 1 : 0).padding(.leading, 2)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - An exam

/// An exam on a calendar tile, flipping into place.
struct ExamStepView: View {
    let step: AssistantStep
    let plan: ExamPlanDraft
    let actions: AssistantStepActions
    var animated = false

    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @State private var flipped: Bool
    @State private var changing = false

    init(step: AssistantStep, plan: ExamPlanDraft, actions: AssistantStepActions, animated: Bool) {
        self.step = step
        self.plan = plan
        self.actions = actions
        self.animated = animated
        _flipped = State(initialValue: !animated)
    }

    private var open: Bool { step.status == .proposed && !actions.isLive }

    var body: some View {
        StepCard(step: step, actions: actions, addTitle: "Add to calendar", subtitle: step.courseName.clNonEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 14) {
                    tile
                    VStack(alignment: .leading, spacing: 5) {
                        Text(plan.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .clFont(.subheadlineEmphasis)
                            .foregroundStyle(CLColor.ink)
                        Text(plan.hasTime ? plan.date.formatted(date: .omitted, time: .shortened) : "9:00 am unless you change it")
                            .clFont(.footnote)
                            .foregroundStyle(CLColor.ink2)
                        let days = max(0, app.calendar.dayDistance(from: app.now, to: plan.date))
                        CLPill(text: days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days", tone: .mint, systemImage: "clock")
                        if !plan.topicNames.isEmpty {
                            Text(verbatim: plan.topicNames.joined(separator: ", ")).clFont(.caption).foregroundStyle(CLColor.ink3).lineLimit(2)
                        } else {
                            Text("The whole course").clFont(.caption).foregroundStyle(CLColor.ink3)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if plan.isDuplicate {
                    Label("You already have an exam in this course that day.", systemImage: "exclamationmark.triangle.fill")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.sunInk)
                }
                if open {
                    if changing {
                        DatePicker("Exam date", selection: Binding(get: { plan.date }, set: { new in
                            actions.edit?(step) { s in
                                if case .exam(var p) = s.payload { p.date = new; p.hasTime = true; s.payload = .exam(p) }
                            }
                        }), in: app.now..., displayedComponents: [.date, .hourAndMinute])
                            .clFont(.subheadline)
                    }
                    Button(changing ? "Done" : "Change the day or time") {
                        CLHaptics.tap()
                        withAnimation(CLMotion.settle) { changing.toggle() }
                    }
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.skyInk)
                    .buttonStyle(.plain)
                    .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
                }
            }
        }
        .task {
            guard animated, !flipped else { return }
            try? await nap(260)
            withAnimation(reduceMotion ? nil : .spring(response: 0.62, dampingFraction: 0.62)) { flipped = true }
        }
        .onChange(of: step.status) { old, new in
            if animated, new == .applied, old != .applied { CLFeel.play(.saved) }
        }
    }

    private var tile: some View {
        VStack(spacing: 0) {
            Text(plan.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(CLColor.onFill)
                .frame(maxWidth: .infinity, minHeight: 22)
                .background(CLColor.tangerine)
            Text(plan.date.formatted(.dateTime.day()))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(CLColor.night)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .frame(width: 66)
        .background(CLColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CLColor.night.opacity(0.08)))
        .shadow(color: CLColor.night.opacity(0.12), radius: 6, y: 4)
        .rotation3DEffect(.degrees(flipped ? 0 : -88), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
        .opacity(flipped ? 1 : 0.2)
        .accessibilityHidden(true)
    }
}

// MARK: - A button

/// A practice session or a screen, offered: nothing opens until the student taps.
struct OfferStepView: View {
    let step: AssistantStep
    let actions: AssistantStepActions

    var body: some View {
        StepCard(step: step, actions: actions, subtitle: subtitle) {
            Button { actions.perform?(step.payload) } label: {
                HStack(spacing: 8) {
                    Image(systemName: step.tool == .startPractice ? "play.fill" : "arrow.up.right")
                    if step.tool == .startPractice { Text("Start") } else { Text("Open") }
                }
            }
            .buttonStyle(.cl(.primary, size: .medium))
            .disabled(actions.perform == nil)
        }
    }

    private var subtitle: String? {
        if step.tool == .startPractice { return String(localized: "Practice session") }
        return nil
    }
}

// MARK: - A lookup

/// "Read 3 passages": what Cap looked up in the notes, as chips of where it found them. A small page is scanned once as the
/// lookup appears.
struct LookupStepView: View {
    let step: AssistantStep
    let lookup: NotesLookup
    var animated = false

    @State private var shown: Int
    @State private var scan = 0

    init(step: AssistantStep, lookup: NotesLookup, animated: Bool) {
        self.step = step
        self.lookup = lookup
        self.animated = animated
        _shown = State(initialValue: animated ? 0 : lookup.hits.count)
    }

    private var working: Bool { step.status == .working }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            miniPage
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(verbatim: step.title).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                    if working { WorkingDots(tint: CLColor.skyInk) }
                }
                if !lookup.query.isEmpty {
                    Text(verbatim: step.courseName.isEmpty ? "“\(lookup.query)”" : String(localized: "“\(lookup.query)” in \(step.courseName)"))
                        .clFont(.caption).foregroundStyle(CLColor.ink3).lineLimit(1)
                }
                if !lookup.hits.isEmpty {
                    CLFlow(spacing: 6, lineSpacing: 6) {
                        ForEach(Array(Array(lookup.hits.prefix(6)).enumerated()), id: \.offset) { i, hit in
                            if i < shown {
                                CLSourceChip(label: hit.label)
                                    .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
                            }
                        }
                    }
                    .animation(CLMotion.pop, value: shown)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(CLColor.skySoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .task(id: lookup.hits.count) {
            guard animated, !lookup.hits.isEmpty else { return }
            scan += 1
            while shown < min(6, lookup.hits.count) {
                try? await nap(110)
                if Task.isCancelled { return }
                shown += 1
                CLFeel.play(.cardOut(shown - 1))
            }
        }
    }

    /// A tiny page whose lines light as the beam passes.
    private var miniPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(CLColor.night.opacity(i == 0 ? 0.35 : 0.16)).frame(width: i == 0 ? 20 : i == 4 ? 14 : 26, height: 3)
            }
        }
        .padding(8)
        .frame(width: 40, height: 46, alignment: .topLeading)
        .background(CLColor.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(CLColor.night.opacity(0.08)))
        .scanBeam(run: scan)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
    }
}
