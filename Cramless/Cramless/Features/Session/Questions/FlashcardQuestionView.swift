import SwiftUI

/// A flashcard: say it to yourself, then flip (a 3D turn; a cross-fade under Reduce Motion) and rate how well you
/// knew it. Each rating shows when the card comes back, from the scheduler itself.
///
/// Once it is flipped, a swipe rates it: right is "got it" (Good), left is Again (`SwipeRule`; the ← → keys and the two chips do the same).
/// Hard and Easy stay as tiles. With VoiceOver or Switch Control, or at the accessibility text sizes, the footer is the four-tile grid,
/// and VoiceOver has the four as actions on the answer. A tally of got it and again sits above the card once there is one.
///
/// DEBUG (`SessionDebug`): `CRAMLESS_SESSION_STATE=flashcard-drag` holds the flipped card 60% of the way right; `flashcard-swiped`
/// swipes it: the next one is up, the tally says 1 and 0, and the Undo pill stays; `CRAMLESS_SESSION_SWIPE=rrlhe` plays a session of
/// flashcards by that pattern (`r` swipe right, `l` swipe left, `h` the Hard tile, `e` the Easy tile).
struct FlashcardQuestionView: View {
    let runner: SessionRunner
    let entry: SessionEntry
    let item: StudyItem
    /// DEBUG: flip on appear.
    var autoFlip = false
    /// DEBUG: after flipping, rate it this way after this many milliseconds (session autoplay).
    var autoRate: Rating? = nil
    var autoContinue: Int? = nil
    /// DEBUG: after flipping, swipe it this way (with `autoContinue`'s wait).
    var autoSwipe: Rating? = nil
    /// DEBUG: after flipping, hold the card this far across (a share of its width).
    var autoHold: Double? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl

    @State private var swipeState = FlashcardSwipeState()
    /// The session's tally as this card came up: its own rating shows on the card after it.
    @State private var tally = SessionRunner.FlashcardTally()
    @State private var flipped = false
    @State private var intervals: [Rating: Double] = [:]
    @State private var flippedAtMs = 0
    /// Back from an Undo: flipped as it was, and nothing plays again.
    @State private var restored = false

    var body: some View {
        QuestionScroll {
            if !tally.isEmpty {
                FlashcardTallyView(tally: tally)
                    .padding(.horizontal, 4)
            }
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
            FlashcardSwipeLayer(state: swipeState, enabled: flipped, intervals: intervals, onSwipe: swipe) { card }
            if flipped, runner.offersLooksWrong {
                LooksWrongButton(item: item)
                    .frame(maxWidth: .infinity)
                    .opacity(swipeState.isDragging ? 0 : 1)
            }
        }
        .scrollDisabled(swipeState.isDragging)
        .sessionFooter { footer }
        .onAppear {
            tally = runner.flashcardTally
            pickUpRestore()
        }
        // The rating held for Undo moved the session's due load when it was recorded: a label can be a day off until then.
        .onChange(of: runner.pending == nil) { _, recorded in
            if recorded, runner.current?.id == entry.id { intervals = app.intervalPreview(itemID: item.id, sessionID: runner.sessionID) }
        }
        .task {
            pickUpRestore()
            intervals = app.intervalPreview(itemID: item.id, sessionID: runner.sessionID)
            guard !restored else { return }
            app.readAloud(question: item)
            if autoFlip {
                do { try await nap(450) } catch { return }
                flip()
                if let autoHold {
                    do { try await nap(700) } catch { return }
                    withAnimation(CLMotion.settle) { swipeState.offset = swipeState.width * autoHold }
                    return
                }
                if autoRate == nil, autoSwipe == nil { return }
                do { try await nap(autoContinue ?? 1200) } catch { return }
                if let autoSwipe {
                    // A finger's drag, for films: part of the way, then away.
                    withAnimation(CLMotion.settle) { swipeState.offset = swipeState.width * (autoSwipe == .again ? -0.42 : 0.42) }
                    do { try await nap(320) } catch { return }
                    swipe(autoSwipe)
                } else if let autoRate {
                    rate(autoRate)
                }
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
                    .accessibilityActions {
                        Button(SessionCopy.swipeWord(.good)) { rate(.good) }
                        Button(SessionCopy.swipeWord(.again)) { rate(.again) }
                        Button("Hard") { rate(.hard) }
                        Button("Easy") { rate(.easy) }
                    }
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

    /// The four tiles stay where a swipe isn't how the person gets around, or where the chips' words wouldn't fit.
    private var usesGrid: Bool { typeSize.isAccessibilitySize || voiceOver || switchControl }

    @ViewBuilder private var footer: some View {
        if flipped {
            Group {
                if usesGrid { gridFooter } else { swipeFooter }
            }
            .background { arrowKeys }
        } else {
            Button("Show answer", action: flip)
                .buttonStyle(.cl(.primary))
        }
    }

    private var gridFooter: some View {
        VStack(spacing: 8) {
            if !typeSize.isAccessibilitySize {
                Text("How well did you know it?")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink3)
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Rating.allCases) { rating in
                    ratingButton(rating, minHeight: 62)
                }
            }
        }
        .transition(.opacity.combined(with: .offset(y: 12)))
    }

    /// Again and Got it, on the side a swipe goes; Hard and Easy below them.
    private var swipeFooter: some View {
        VStack(spacing: 8) {
            Text("Swipe right if you got it, left if not")
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink3)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                swipeChip(.again, systemImage: "arrow.left", leading: true)
                swipeChip(.good, systemImage: "arrow.right", leading: false)
            }
            HStack(spacing: 8) {
                ratingButton(.hard, minHeight: 44, inline: true)
                ratingButton(.easy, minHeight: 44, inline: true)
            }
        }
        .transition(.opacity.combined(with: .offset(y: 12)))
    }

    /// "← Again · 10 min" and "Got it → · 4 days": a tap does what the swipe does.
    private func swipeChip(_ rating: Rating, systemImage: String, leading: Bool) -> some View {
        let tone = Self.tone(rating)
        let interval = intervals[rating]
        return Button { swipe(rating) } label: {
            HStack(spacing: 6) {
                if leading { Image(systemName: systemImage).font(.system(size: 13, weight: .bold)).accessibilityHidden(true) }
                Text(SessionCopy.swipeWord(rating))
                    .clFont(.bodyEmphasis)
                if !leading { Image(systemName: systemImage).font(.system(size: 13, weight: .bold)).accessibilityHidden(true) }
                if let interval {
                    Text(SessionCopy.interval(days: interval))
                        .clFont(.number(12, .semibold))
                        .opacity(0.85)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(tone.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(CLColor.background)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tone.fill))
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable(depth: 4, edge: tone.edge, cornerRadius: 18))
        .accessibilityLabel(SessionCopy.swipeWord(rating))
        .accessibilityValue(interval.map { "Next review \(SessionCopy.inInterval(days: $0))" } ?? "")
    }

    /// The hardware keyboard: ← and → as the swipe, and 1 to 4 for the ratings the chips cover (the grid's tiles carry their own).
    private var arrowKeys: some View {
        ZStack {
            Button("") { swipe(.again) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { swipe(.good) }.keyboardShortcut(.rightArrow, modifiers: [])
            if !usesGrid {
                Button("") { rate(.again) }.keyboardShortcut("1", modifiers: [])
                Button("") { rate(.good) }.keyboardShortcut("3", modifiers: [])
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func ratingButton(_ rating: Rating, minHeight: CGFloat, inline: Bool = false) -> some View {
        let tone = Self.tone(rating)
        let interval = intervals[rating]
        let layout = inline ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 4))
        return Button { rate(rating) } label: {
            layout {
                Text(rating.title)
                    .clFont(inline ? .subheadlineEmphasis : .bodyEmphasis)
                if let interval {
                    Text(SessionCopy.interval(days: interval))
                        .clFont(.number(12, .semibold))
                        .opacity(0.85)
                }
            }
            .foregroundStyle(tone.ink)
            .frame(maxWidth: .infinity, minHeight: minHeight)
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
        guard runner.current?.id == entry.id else { return }
        // A self-rating sounds the same whatever it is, and neither builds nor breaks a run (ComboRun).
        CLFeel.play(.rated)
        app.stopReadingAloud()
        let review = runner.record(rating: rating, score: -1, answer: nil, gradedBy: "person", durationMs: flippedAtMs,
                                   outcome: SessionRunner.Outcome(rating: rating), undo: .flashcard(flippedAtMs: flippedAtMs))
        if review?.isSave == true { runner.flareSave(of: item) }
        withAnimation(CLMotion.settle) { runner.advance() }
    }

    /// A swipe, the chips or an arrow key: the rating is given now and the card flies off on its side; the next one rises in its place.
    private func swipe(_ rating: Rating) {
        guard flipped, runner.current?.id == entry.id, !swipeState.isFlying else { return }
        CLFeel.play(.rated)
        app.stopReadingAloud()
        let review = runner.record(rating: rating, score: -1, answer: nil, gradedBy: "person", durationMs: flippedAtMs,
                                   outcome: SessionRunner.Outcome(rating: rating), undo: .flashcard(flippedAtMs: flippedAtMs))
        if review?.isSave == true { runner.flareSave(of: item) }
        let runner = runner
        // Set before the card flies, so what is left of this question fades in place instead of sliding off after it.
        runner.prepareArrival(.rise)
        swipeState.fly(rating, reduceMotion: reduceMotion) {
            withAnimation(CLMotion.settle) { runner.advance(arriving: .rise) }
            // Once the next one has risen, the one after comes on from the edge again.
            Task { @MainActor in
                try? await nap(600)
                if runner.arrival == .rise { runner.prepareArrival(.forward) }
            }
        }
    }

    /// The rating was undone: the card is back, flipped, as it was.
    private func pickUpRestore() {
        guard !restored, case .flashcard(let ms)? = runner.takeRestore(for: entry.id) else { return }
        restored = true
        flipped = true
        flippedAtMs = ms
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
