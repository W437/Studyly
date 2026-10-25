import SwiftUI

/// A flashcard: say it to yourself, then flip (a 3D turn; a cross-fade under Reduce Motion) and rate how well you
/// knew it. Each rating shows when the card comes back, from the scheduler itself.
struct FlashcardQuestionView: View {
    let runner: SessionRunner
    let entry: SessionEntry
    let item: StudyItem
    /// DEBUG: flip on appear.
    var autoFlip = false
    /// DEBUG: after flipping, rate it this way after this many milliseconds (session autoplay).
    var autoRate: Rating? = nil
    var autoContinue: Int? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var flipped = false
    @State private var intervals: [Rating: Double] = [:]
    @State private var flippedAtMs = 0

    var body: some View {
        QuestionScroll {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: item.kind.studySymbol)
                    Text([item.kind.displayName, runner.topicName(entry.topicID)].compactMap { $0 }.joined(separator: " · "))
                }
                .clFont(.eyebrow)
                .foregroundStyle(CLColor.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityElement(children: .combine)
                ReadAloudButton(item: item)
            }
            .padding(.horizontal, 4)
            if entry.attempt > 0 {
                CLPill(text: "Back again", tone: .sky, systemImage: "arrow.uturn.backward")
                    .padding(.horizontal, 4)
            }
            card
        }
        .sessionFooter { footer }
        .task {
            app.readAloud(question: item)
            intervals = app.intervalPreview(itemID: item.id, sessionID: runner.sessionID)
            if autoFlip {
                do { try await nap(450) } catch { return }
                flip()
                guard let autoRate else { return }
                do { try await nap(autoContinue ?? 1200) } catch { return }
                rate(autoRate)
            }
        }
    }

    // MARK: The card

    private var card: some View {
        ZStack {
            face(front: true)
                .modifier(FlipFace(angle: flipped ? 180 : 0, isBack: false, flat: reduceMotion))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Double-tap to show the answer")
                .accessibilityAction { flip() }
                .accessibilityHidden(flipped)
            face(front: false)
                .modifier(FlipFace(angle: flipped ? 180 : 0, isBack: true, flat: reduceMotion))
                .accessibilityElement(children: .contain)
                .accessibilityHidden(!flipped)
        }
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture { if !flipped { flip() } }
    }

    private func face(front: Bool) -> some View {
        VStack(spacing: 16) {
            if front {
                Text(item.prompt)
                    .clFont(.title)
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Say it to yourself, then tap to check")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .multilineTextAlignment(.center)
            } else {
                Text(item.answer)
                    .clFont(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let ref = item.sourceRef { SourceButton(ref: ref) }
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
        .shadow(color: CLColor.night.opacity(0.07), radius: 14, y: 9)
    }

    // MARK: Rating

    @ViewBuilder private var footer: some View {
        if flipped {
            if !typeSize.isAccessibilitySize {
                Text("How well did you know it?")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink3)
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Rating.allCases) { rating in
                    ratingButton(rating)
                }
            }
            .transition(.opacity.combined(with: .offset(y: 12)))
        } else {
            Button("Show answer", action: flip)
                .buttonStyle(.cl(.primary))
        }
    }

    private func ratingButton(_ rating: Rating) -> some View {
        let tone = Self.tone(rating)
        let interval = intervals[rating]
        return Button { rate(rating) } label: {
            VStack(spacing: 4) {
                Text(rating.title)
                    .clFont(.bodyEmphasis)
                if let interval {
                    Text(SessionCopy.interval(days: interval))
                        .clFont(.number(12, .semibold))
                        .opacity(0.85)
                }
            }
            .foregroundStyle(tone.ink)
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(CLColor.background)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tone.fill))
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable(depth: 4, edge: tone.edge, cornerRadius: 18))
        .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
        .accessibilityLabel(rating.title)
        .accessibilityValue(interval.map { "Next review \(SessionCopy.inInterval(days: $0))" } ?? "")
    }

    /// The colours of each rating's tile (the intro's flashcard demo uses them too).
    static func tone(_ rating: Rating) -> (fill: Color, ink: Color, edge: Color) {
        switch rating {
        case .again: (CLColor.roseSoft, CLColor.roseInk, CLColor.roseEdge.opacity(0.45))
        case .hard: (CLColor.sunSoft, CLColor.sunInk, CLColor.sunEdge.opacity(0.5))
        case .good: (CLColor.mintSoft, CLColor.mintInk, CLColor.mintEdge.opacity(0.45))
        case .easy: (CLColor.skySoft, CLColor.skyInk, CLColor.skyInk.opacity(0.35))
        }
    }

    // MARK: Actions

    private func flip() {
        guard !flipped else { return }
        flippedAtMs = runner.elapsedMs()
        CLFeel.play(.flip)
        app.stopReadingAloud()
        withAnimation(reduceMotion ? CLMotion.fade : CLMotion.calm) { flipped = true }
        runner.hasUnsavedAnswer = false
        AccessibilityNotification.Announcement("Answer: \(item.answer)").post()
        if app.settings.readAloud { app.readAloud(item.answer) }
    }

    private func rate(_ rating: Rating) {
        // A self-rating sounds the same whatever it is, and neither builds nor breaks a run (ComboRun).
        CLFeel.play(.rated)
        app.stopReadingAloud()
        let review = runner.record(rating: rating, score: -1, answer: nil, gradedBy: "person", durationMs: flippedAtMs,
                                   outcome: SessionRunner.Outcome(rating: rating))
        if review?.isSave == true { runner.flareSave(of: item) }
        withAnimation(CLMotion.settle) { runner.advance() }
    }
}

/// One face of a flipping card. The angle animates; each face shows only on its own side of 90°, so the turn
/// reads as a real card. `flat` (Reduce Motion) skips the rotation and cross-fades.
struct FlipFace: ViewModifier, Animatable {
    var angle: Double
    var isBack: Bool
    var flat: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let showing = isBack ? angle >= 90 : angle < 90
        if flat {
            content
                .opacity(isBack ? angle / 180 : 1 - angle / 180)
        } else {
            content
                .rotation3DEffect(.degrees(isBack ? angle - 180 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .opacity(showing ? 1 : 0)
        }
    }
}
