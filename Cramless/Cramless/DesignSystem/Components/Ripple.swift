import SwiftUI

/// A ripple through a view when an answer lands (`Shaders/Ripple.metal`): a ring travels out from the view's
/// centre and dies away in 0.9 s. Its strength follows the verdict (6 pt right, 4 partly, 3 not yet). Off under
/// Reduce Motion, and switched off between ripples, so it costs nothing at rest. Don't put it over text fields:
/// a layer effect draws them as placeholders.
struct CLRipple: ViewModifier {
    /// Changes once per ripple.
    let trigger: Int
    let amplitude: Double

    @Environment(\.clReduceMotion) private var reduceMotion

    static let duration = 0.9

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: Self.duration, trigger: trigger) { view, elapsed in
            view.visualEffect { effect, proxy in
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                let live = !reduceMotion && amplitude > 0 && elapsed < Self.duration
                return effect.layerEffect(
                    ShaderLibrary.Ripple(.float2(center), .float(elapsed), .float(amplitude), .float(14),
                                         .float(7), .float(900)),
                    maxSampleOffset: CGSize(width: amplitude, height: amplitude),
                    isEnabled: live)
            }
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(Self.duration, duration: Self.duration)
        }
    }
}

extension FeedbackTone {
    /// How strongly an answer's ripple moves.
    var rippleAmplitude: Double {
        switch self {
        case .mint: 6
        case .sun: 4
        case .rose: 3
        case .neutral: 0
        }
    }
}

extension View {
    /// A ripple each time `trigger` changes (`CLRipple`).
    func clRipple(trigger: Int, amplitude: Double) -> some View {
        modifier(CLRipple(trigger: trigger, amplitude: amplitude))
    }
}
