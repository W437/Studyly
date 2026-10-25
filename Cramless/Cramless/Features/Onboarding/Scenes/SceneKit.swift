import SwiftUI

// The pieces every live-demo scene shares: the lifecycle (play while front-most, loop through a fade, settle under
// Reduce Motion, reset while off-screen), the card the scene plays in, and the miniature vocabulary (paper,
// text lines, scanner brackets, chat bubbles). Scenes replay the product's own motion with CLMotion tokens and
// fire no haptics: page turns own the haptic.

/// Applies a change without animation (a reset nobody should see).
@MainActor
func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

/// The shared scene lifecycle.
///
/// - Plays `script` while `active` (its page is front-most). Leaving cancels it mid-beat: `nap` throws.
/// - Loops go through a fade: out, reset while invisible, back in. Never a visible snap.
/// - A page that slid away is reset once it's off-screen, so coming back starts from the first frame.
/// - Reduce Motion shows `settle`'s final frame and never moves.
/// - `playsOnce` (the trust page): one pass, then it rests on the final frame for good.
struct SceneLifecycle: ViewModifier {
    let active: Bool
    var playsOnce = false
    let reset: @MainActor () -> Void
    let settle: @MainActor () -> Void
    let script: @MainActor () async throws -> Void

    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var visible = true
    @State private var state: PlayState = .fresh

    private enum PlayState { case fresh, dirty, rested }

    private struct Key: Hashable {
        var active: Bool
        var reduceMotion: Bool
    }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .task(id: Key(active: active, reduceMotion: reduceMotion)) { await drive() }
    }

    private func drive() async {
        if reduceMotion {
            withoutAnimation { settle(); visible = true }
            state = .rested
            return
        }
        guard active else {
            // Let the page slide away first, then put the scene back to its first frame unseen.
            guard state == .dirty else { return }
            do { try await nap(520) } catch { return }
            withoutAnimation { reset(); visible = true }
            state = .fresh
            return
        }
        if state == .rested, playsOnce { return }
        do {
            if state != .fresh { try await fade(through: reset) }
            state = .dirty
            while true {
                try await script()
                if playsOnce { state = .rested; return }
                try await fade(through: reset)
            }
        } catch {
            // Cancelled: the page changed. The inactive pass resets it.
        }
    }

    private func fade(through change: () -> Void) async throws {
        withAnimation(CLMotion.fade) { visible = false }
        try await nap(340)
        withoutAnimation(change)
        withAnimation(CLMotion.fade) { visible = true }
        try await nap(260)
    }
}

extension View {
    func sceneLifecycle(active: Bool, playsOnce: Bool = false, reset: @escaping @MainActor () -> Void,
                        settle: @escaping @MainActor () -> Void,
                        script: @escaping @MainActor () async throws -> Void) -> some View {
        modifier(SceneLifecycle(active: active, playsOnce: playsOnce, reset: reset, settle: settle, script: script))
    }
}

/// The raised card a scene plays in. Its text is capped at a modest Dynamic Type size because the scene is a
/// miniature with a fixed stage; the page's title and body below it scale fully, and VoiceOver reads the
/// scene's description instead of its parts.
struct SceneCard<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            // VoiceOver reads the scene's one description (set by the page), never the miniature's parts.
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: CLColor.night.opacity(0.08), radius: 18, y: 10)
            .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

/// Ink on paper. Paper is white in both appearances (it's paper), so these never adapt.
enum PaperInk {
    static let line = CLColor.night.opacity(0.13)
    static let heading = CLColor.night.opacity(0.88)
    static let cellFill = CLColor.sky.opacity(0.16)
    static let cellStroke = CLColor.sky.opacity(0.55)
    static let highlighter = CLColor.sun.opacity(0.8)
}

/// One line of text on a miniature page: a rounded grey capsule, optionally swept by the highlighter.
struct PaperLine: View {
    var fraction: CGFloat
    var height: CGFloat = 7
    var color: Color = PaperInk.line
    var marked = false

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(color)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(PaperInk.highlighter)
                        .scaleEffect(x: marked ? 1 : 0.001, anchor: .leading)
                        .opacity(marked ? 1 : 0)
                }
                .frame(width: geo.size.width * fraction)
        }
        .frame(height: height)
    }
}

/// One corner of the scanner's brackets: an L with a rounded elbow.
struct BracketCorner: Shape {
    enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }
    var corner: Corner
    var radius: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let (a, elbow, b): (CGPoint, CGPoint, CGPoint) = switch corner {
        case .topLeading: (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY))
        case .topTrailing: (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomLeading: (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomTrailing: (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY))
        }
        p.move(to: a)
        p.addArc(tangent1End: elbow, tangent2End: b, radius: radius)
        p.addLine(to: b)
        return p
    }
}

/// A chat bubble shape: round, with the tail corner tucked in.
struct BubbleShape: Shape {
    var mine: Bool

    func path(in rect: CGRect) -> Path {
        let big: CGFloat = 20, tail: CGFloat = 7
        return UnevenRoundedRectangle(topLeadingRadius: big, bottomLeadingRadius: mine ? big : tail,
                                      bottomTrailingRadius: mine ? tail : big, topTrailingRadius: big,
                                      style: .continuous).path(in: rect)
    }
}

/// Three dots breathing while Cap "types". Only ever on screen for a beat inside a playing scene.
struct TypingDots: View {
    /// Draws its own bubble; false when a surrounding bubble already does.
    var bubble = true

    var body: some View {
        let dots = TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = sin((t * 2 * .pi / 1.0) - Double(i) * 0.9)
                    Circle()
                        .fill(CLColor.ink3)
                        .frame(width: 7, height: 7)
                        .opacity(0.45 + 0.55 * max(0, phase))
                        .offset(y: -2.5 * max(0, phase))
                }
            }
        }
        if bubble {
            dots
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(CLColor.surface2, in: BubbleShape(mine: false))
        } else {
            dots
        }
    }
}
