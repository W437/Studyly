import SwiftUI

/// What a drag on a flipped flashcard comes to. Pure: distances and speeds in, a rating out.
enum SwipeRule {
    /// How far across the card a drag must go to count.
    static let distanceShare = 0.35
    /// A flick this fast (points a second) counts from anywhere.
    static let flickSpeed = 700.0
    /// How far a finger moves before the drag is called horizontal or vertical.
    static let lockDistance = 12.0
    /// Horizontal only when it is this much more sideways than up or down, so the question can still scroll.
    static let lockRatio = 1.5
    /// The card's tilt at the far end of a drag, in degrees.
    static let maxTilt = 8.0

    enum Lock: Equatable { case horizontal, vertical }

    /// The way a drag has gone, once it has gone far enough to say.
    static func lock(dx: Double, dy: Double) -> Lock? {
        guard (dx * dx + dy * dy).squareRoot() >= lockDistance else { return nil }
        return abs(dx) > lockRatio * abs(dy) ? .horizontal : .vertical
    }

    /// The rating a released drag gives: right is "got it" (Good), left is Again, nil springs back. A flick back the other way is a
    /// change of mind, however far the card had gone.
    static func decide(dx: Double, velocity: Double, width: Double) -> Rating? {
        guard width > 0, dx != 0 else { return nil }
        let against = dx * velocity < 0
        if abs(velocity) >= flickSpeed { return against ? nil : rating(right: dx > 0) }
        return armed(dx: dx, width: width)
    }

    /// The rating a finger at `dx` would give if it let go without a flick.
    static func armed(dx: Double, width: Double) -> Rating? {
        guard width > 0, abs(dx) >= width * distanceShare else { return nil }
        return rating(right: dx > 0)
    }

    /// The card's tilt in degrees, up to `maxTilt` a card's width out.
    static func tilt(dx: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return max(-maxTilt, min(maxTilt, dx / width * maxTilt))
    }

    /// How much of the stamp shows: nothing at rest, all of it where the drag starts to count.
    static func stampOpacity(dx: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return max(0, min(1, abs(dx) / (width * distanceShare)))
    }

    private static func rating(right: Bool) -> Rating { right ? .good : .again }
}

/// Where the card is while it is dragged or flying off. It lives outside the question view, so a finger's every move redraws the card and
/// not the whole question.
@MainActor
@Observable
final class FlashcardSwipeState {
    var offset: CGFloat = 0
    /// Faded out (Reduce Motion's way off the screen).
    var gone = false
    /// A finger has the card sideways: the question doesn't scroll under it.
    var isDragging = false
    private(set) var isFlying = false
    @ObservationIgnored var width: CGFloat = 0

    /// Off the screen on the rating's side, then `done`.
    func fly(_ rating: Rating, reduceMotion: Bool, done: @escaping () -> Void) {
        isFlying = true
        isDragging = false
        let side: CGFloat = rating == .again ? -1 : 1
        withAnimation(CLMotion.snap, completionCriteria: .logicallyComplete) {
            if reduceMotion { gone = true } else { offset = side * max(width, 320) * 1.5 }
        } completion: {
            done()
        }
    }

    func springBack() {
        isDragging = false
        guard offset != 0 else { return }
        withAnimation(CLMotion.settle) { offset = 0 }
    }
}

/// The flipped card under a finger: it follows the drag (with a little tilt, none under Reduce Motion), a stamp says what letting go would
/// do, and past the line (or on a flick) it goes.
///
/// DEBUG: `CRAMLESS_SESSION_STATE=flashcard-drag` holds the card 60% of the way right.
struct FlashcardSwipeLayer<Content: View>: View {
    let state: FlashcardSwipeState
    /// Only a flipped card can be swiped.
    let enabled: Bool
    let intervals: [Rating: Double]
    let onSwipe: (Rating) -> Void
    @ViewBuilder var content: Content

    @Environment(\.clReduceMotion) private var reduceMotion
    @GestureState private var fingerDown = false
    @State private var lock: SwipeRule.Lock?
    @State private var armed: Rating?

    var body: some View {
        let width = Double(state.width)
        let dx = Double(state.offset)
        content
            // On the side the card moves away from, so it stays on screen.
            .overlay(alignment: dx >= 0 ? .topLeading : .topTrailing) { stamp(dx: dx, width: width) }
            .rotationEffect(.degrees(reduceMotion ? 0 : SwipeRule.tilt(dx: dx, width: width)), anchor: .bottom)
            .offset(x: state.offset)
            .opacity(state.gone ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { state.width = $0 }
            .simultaneousGesture(drag, including: enabled ? .all : .subviews)
            // A gesture the system took away never says it ended.
            .onChange(of: fingerDown) { _, down in
                guard !down, !state.isFlying else { return }
                lock = nil
                armed = nil
                state.springBack()
            }
    }

    @ViewBuilder
    private func stamp(dx: Double, width: Double) -> some View {
        let opacity = SwipeRule.stampOpacity(dx: dx, width: width)
        if opacity > 0, !state.gone {
            let rating: Rating = dx > 0 ? .good : .again
            let tone = FlashcardQuestionView.tone(rating)
            let line = intervals[rating].map { SessionCopy.swipeStamp(rating, interval: SessionCopy.interval(days: $0)) } ?? SessionCopy.swipeWord(rating)
            Text(line)
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(tone.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(CLColor.background, in: Capsule())
                .background(tone.fill, in: Capsule())
                .overlay(Capsule().strokeBorder(tone.ink.opacity(0.35), lineWidth: 1.5))
                .padding(16)
                .opacity(opacity)
                .accessibilityHidden(true)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: SwipeRule.lockDistance)
            .updating($fingerDown) { _, down, _ in down = true }
            .onChanged { value in
                guard !state.isFlying else { return }
                let dx = Double(value.translation.width)
                if lock == nil { lock = SwipeRule.lock(dx: dx, dy: Double(value.translation.height)) }
                guard lock == .horizontal else { return }
                if !state.isDragging { state.isDragging = true }
                state.offset = value.translation.width
                let now = SwipeRule.armed(dx: dx, width: Double(state.width))
                if now != armed {
                    armed = now
                    CLHaptics.select()
                }
            }
            .onEnded { value in
                defer {
                    lock = nil
                    armed = nil
                }
                guard lock == .horizontal, !state.isFlying else { return }
                if let rating = SwipeRule.decide(dx: Double(value.translation.width), velocity: Double(value.velocity.width),
                                                 width: Double(state.width)) {
                    onSwipe(rating)
                } else {
                    state.springBack()
                }
            }
    }
}

/// "Got it 8" and "Again 2" over the flashcards of this session: ratings, not cards, a held one included.
struct FlashcardTallyView: View {
    let tally: SessionRunner.FlashcardTally

    var body: some View {
        HStack(spacing: 6) {
            CLPill(text: "Got it \(tally.gotIt)", tone: .mint, systemImage: "checkmark")
            CLPill(text: "Again \(tally.again)", tone: .rose, systemImage: "arrow.uturn.backward")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This session: got it \(tally.gotIt), again \(tally.again)")
    }
}
