import SwiftUI

// The pieces every question format shares: the card, its header (format, topic, read aloud), the footer bar that
// becomes the answer panel (DesignSystem/Components/FeedbackSheet.swift), the source chip, the gentle AI prompt, the
// rating line, and the highlighter's timing (so the haptic lands with the mark).

/// The raised card a question sits in (the prototype's `.qcard`).
struct QuestionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)
    }
}

/// A question's scroll view: readable width on big screens, keyboard dismissed by dragging.
struct QuestionScroll<Content: View>: View {
    /// Where the page is scrolled to, for a view that moves it itself (the summary's film hook).
    var position: Binding<ScrollPosition>?
    @ViewBuilder var content: Content

    var body: some View {
        if let position { scroll.scrollPosition(position) } else { scroll }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: CLMetrics.readableWidth, alignment: .leading)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 6)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}

extension View {
    /// The question's buttons, pinned above the home indicator (and above the keyboard while typing). The
    /// secondary ones join the primary in the footer, except at accessibility text sizes, where the view shows
    /// them in its scroll content instead (`AccessibilityOnly`) so the pinned bar stays one button tall. Once the
    /// answer is checked, `feedback` turns the bar into the answer panel, rising from the bottom edge.
    func sessionFooter<Primary: View, Secondary: View>(feedback: AnswerFeedback? = nil,
                                                      @ViewBuilder primary: () -> Primary,
                                                      @ViewBuilder secondary: () -> Secondary) -> some View {
        modifier(SessionFooter(feedback: feedback, primary: primary(), secondary: secondary()))
    }

    func sessionFooter<Primary: View>(feedback: AnswerFeedback? = nil, @ViewBuilder _ primary: () -> Primary) -> some View {
        modifier(SessionFooter(feedback: feedback, primary: primary(), secondary: EmptyView()))
    }
}

private struct SessionFooter<Primary: View, Secondary: View>: ViewModifier {
    let feedback: AnswerFeedback?
    let primary: Primary
    let secondary: Secondary

    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.safeAreaBar(edge: .bottom) {
            ZStack(alignment: .bottom) {
                if let feedback {
                    FeedbackPanel(feedback: feedback, primary: primary, secondary: secondary)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    bar.transition(.opacity)
                }
            }
            .animation(CLMotion.sheet, value: feedback != nil)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    private var bar: some View {
        VStack(spacing: 8) {
            primary
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 10) { secondary }
            }
        }
        .frame(maxWidth: CLMetrics.readableWidth)
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(stops: [.init(color: CLColor.background.opacity(0), location: 0),
                                   .init(color: CLColor.background.opacity(0.94), location: 0.28),
                                   .init(color: CLColor.background, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -18)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}

/// Content shown only at accessibility text sizes: a question's secondary actions, moved out of the pinned
/// footer into the scroll.
struct AccessibilityOnly<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 8) { content }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }
}

extension ItemKind {
    /// The format's glyph in the question header.
    var studySymbol: String {
        switch self {
        case .recall: "pencil.line"
        case .apply: "lightbulb"
        case .mcq: "list.bullet"
        case .cloze: "character.cursor.ibeam"
        case .diagram: "photo"
        case .flashcard: "rectangle.on.rectangle"
        }
    }
}

/// "IN YOUR OWN WORDS · WHY MITOSIS MATTERS", the read-aloud button, and "Back again" for a repeat.
struct QuestionHeader: View {
    let item: StudyItem
    let entry: SessionEntry
    let topic: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: item.kind.studySymbol)
                    Text([item.kind.displayName, topic].compactMap { $0 }.joined(separator: " · "))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .clFont(.eyebrow)
                .foregroundStyle(CLColor.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityElement(children: .combine)
                ReadAloudButton(item: item)
            }
            if entry.attempt > 0 {
                CLPill(text: "Back again", tone: .sky, systemImage: "arrow.uturn.backward")
                    .accessibilityLabel("This one is back: you missed it earlier in the session")
            }
        }
        .padding(.top, -10)
    }
}

/// Reads the question aloud, whatever the Read aloud setting (an explicit tap); tap again to stop.
struct ReadAloudButton: View {
    let item: StudyItem

    @Environment(AppModel.self) private var app

    var body: some View {
        let speaking = ReadAloud.shared.isSpeaking
        Button {
            if speaking { app.stopReadingAloud() } else { app.readAloud(question: item, force: true) }
        } label: {
            Image(systemName: speaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(speaking ? CLColor.tangerineInk : CLColor.ink2)
                .frame(width: 34, height: 34)
                .background(CLColor.surface2, in: Circle())
                .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speaking ? "Stop reading" : "Read the question aloud")
    }
}

/// A grade's colours (the tone itself is in DesignSystem/Components/FeedbackSheet.swift).
extension FeedbackTone {
    init(_ verdict: GradeResponse.Verdict) {
        switch verdict {
        case .correct: self = .mint
        case .partial: self = .sun
        case .incorrect: self = .rose
        }
    }

    init(_ outcome: SessionRunner.Outcome) {
        switch outcome {
        case .right: self = .mint
        case .partial: self = .sun
        case .wrong: self = .rose
        }
    }
}

extension CapMoment {
    /// Cap on the answer panel, beside the headline `SessionCopy.headline` picks from the same facts.
    static func verdict(_ outcome: SessionRunner.Outcome, answered: Bool = true, saved: Bool = false,
                        combo: Int) -> CapMoment {
        guard answered else { return .answerShown }
        switch outcome {
        case .right: return ComboRun.isMilestone(combo) ? .runMilestone : saved ? .saved : .nice
        case .partial: return .almost
        case .wrong: return .notYet
        }
    }
}

/// "Textbook p. 87 · Why is mitosis important?": opens the page with the question's lines marked (or the
/// lecture at its moment), over the session.
struct SourceButton: View {
    let ref: SourceRef

    @Environment(AppModel.self) private var app

    var body: some View {
        let isLecture = ref.start != nil || app.source(ref.sourceID)?.kind == .lecture
        Button {
            CLHaptics.tap()
            if isLecture {
                app.router.present(.lectureMoment(sourceID: ref.sourceID, time: ref.start))
            } else {
                app.router.present(.sourcePage(sourceID: ref.sourceID, pageIndex: ref.pageIndex ?? 0,
                                               highlight: ref.anchorIDs))
            }
        } label: {
            CLSourceChip(label: ref.label, systemImage: isLecture ? "mic" : "book.pages")
                .padding(.vertical, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityHint(isLecture ? "Opens the lecture at this moment" : "Opens the page this question came from")
    }
}

/// A gentle note when a better grade needs consent or Pro. Never a wall: the grade above still counts.
struct SuggestionBanner: View {
    let suggestion: AISuggestion

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CLColor.skyInk)
                .frame(width: 34, height: 34)
                .background(CLColor.skySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button(actionTitle) {
                    CLHaptics.tap()
                    app.router.present(suggestion.sheet)
                }
                .buttonStyle(.cl(.soft, size: .medium, fullWidth: false))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(CLColor.hairline, lineWidth: 1))
    }

    private var symbol: String {
        switch suggestion {
        case .allowCloud: "sparkles"
        case .allowPhotos: "photo.badge.checkmark"
        case .upgrade: "infinity"
        }
    }

    private var message: String {
        switch suggestion {
        case .allowCloud:
            "Cloud AI can double-check answers like this one. The grade above already counts."
        case .allowPhotos:
            "Sending page photos lets Cloud AI read diagrams and handwriting."
        case .upgrade(_, let line):
            "\(line) This answer was checked on your iPhone and still counts."
        }
    }

    private var actionTitle: String {
        switch suggestion {
        case .allowCloud: "Allow Cloud AI"
        case .allowPhotos: "Review"
        case .upgrade: "See Pro"
        }
    }
}

/// "Counts as Good · next review in 4 days", with a menu to change the rating the grade suggested.
struct RatingAdjuster: View {
    let auto: Rating
    @Binding var override: Rating?
    let intervals: [Rating: Double]

    var body: some View {
        let effective = override ?? auto
        Menu {
            Picker("Counts as", selection: Binding(get: { effective }, set: { picked in
                CLHaptics.select()
                override = picked == auto ? nil : picked
            })) {
                ForEach(Rating.allCases) { rating in
                    Text(intervals[rating].map { "\(rating.title) · \(SessionCopy.interval(days: $0))" } ?? rating.title)
                        .tag(rating)
                }
            }
        } label: {
            line(effective)
                .frame(minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Counts as \(effective.title)")
        .accessibilityValue(intervals[effective].map { "Next review \(SessionCopy.inInterval(days: $0))" } ?? "")
        .accessibilityHint("Change how this answer counts")
    }

    private func line(_ effective: Rating) -> some View {
        let next = intervals[effective].map { " · next review \(SessionCopy.inInterval(days: $0))" } ?? ""
        let picked = override != nil ? " (your call)" : ""
        let lead = Text("Counts as ").foregroundStyle(CLColor.ink2)
        let rating = Text("\(effective.title) \(Image(systemName: "chevron.up.chevron.down"))").fontWeight(.semibold)
            .foregroundStyle(CLColor.skyInk)
        let rest = Text("\(picked)\(next)").foregroundStyle(CLColor.ink2)
        return Text("\(lead)\(rating)\(rest)")
            .clFont(.footnote)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The small score capsule ("2 of 3 key ideas") whose number rolls when a refined grade changes it.
struct ScorePill: View {
    let text: String
    let tone: FeedbackTone

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .contentTransition(.numericText())
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .frame(minHeight: 24)
            .foregroundStyle(tone.ink)
            .background(tone.fill, in: Capsule())
    }
}

/// The highlighter's sweep is `HighlightedText`'s timing curve (0.2, 0.8, 0.2, 1) over `max(0.55, marks × 0.35)`
/// seconds; mark `i` of `n` is fully drawn when the sweep's progress reaches `i × 0.6 / n + 1 / n`. These give the
/// moment each mark lands, by inverting the curve, so a key idea's haptic fires as its mark completes.
enum SweepTiming {
    static func duration(marks: Int) -> Double { max(0.55, Double(marks) * 0.35) }

    /// Seconds after the sweep starts at which mark `index` of `count` is fully drawn.
    static func landing(of index: Int, count: Int) -> Double {
        guard count > 0 else { return 0 }
        let slot = 1 / Double(count)
        let progress = min(1, Double(index) * slot * 0.6 + slot)
        return time(toReach: progress) * duration(marks: count)
    }

    /// The fraction of the duration at which the curve's progress reaches `p` (bisection on the bezier).
    static func time(toReach p: Double) -> Double {
        let target = min(1, max(0, p))
        func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
        }
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if bezier(mid, 0.8, 1.0) < target { lo = mid } else { hi = mid }
        }
        return bezier((lo + hi) / 2, 0.2, 0.2)
    }
}

/// A stable order for a multiple choice's options: shuffled per item and per day (so "B" can't be memorised),
/// with "All/None of the above" kept last.
enum ChoiceOrder {
    static func order(texts: [String], itemID: UUID, day: Int) -> [Int] {
        let pinned = Set(texts.indices.filter { i in
            let t = texts[i].lowercased()
            return t.hasPrefix("all of the") || t.hasPrefix("none of the") || t.hasPrefix("both ")
        })
        let free = texts.indices.filter { !pinned.contains($0) }
            .map { ($0, StableRandom.unit(itemID, day: day, salt: UInt64($0 + 1) &* 0x9E37)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        return free + texts.indices.filter { pinned.contains($0) }
    }

    static let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
}
