import SwiftUI
import UIKit

/// Cap's speech balloon: what he says when he is tapped, in a rounded bubble whose tail points down at his head. `tail` is how
/// far the tail sits from the bubble's middle, so it still points at him when the bubble has slid sideways to stay on screen.
struct CapBubble: View {
    let text: LocalizedStringResource
    var tail: CGFloat = 0

    private static let widest: CGFloat = 232

    var body: some View {
        Text(text)
            .clFont(.subheadlineEmphasis)
            .foregroundStyle(CLColor.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 9 + CapBubbleShape.tailHeight)
            .frame(maxWidth: Self.widest)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                CapBubbleShape(tail: tail)
                    .fill(CLColor.surface)
                    .overlay { CapBubbleShape(tail: tail).stroke(CLColor.hairline, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.16), radius: 9, y: 3)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A rounded rectangle with a small tail on its bottom edge.
struct CapBubbleShape: Shape {
    static let tailHeight: CGFloat = 8
    private static let tailWidth: CGFloat = 16
    private static let radius: CGFloat = 18

    /// The tail's middle against the bubble's.
    var tail: CGFloat

    var animatableData: CGFloat {
        get { tail }
        set { tail = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0, rect.height - Self.tailHeight))
        let reach = Self.radius + Self.tailWidth / 2
        let mid = rect.width > reach * 2 ? min(max(rect.midX + tail, rect.minX + reach), rect.maxX - reach) : rect.midX
        var spike = Path()
        spike.move(to: CGPoint(x: mid - Self.tailWidth / 2, y: body.maxY - 1))
        spike.addQuadCurve(to: CGPoint(x: mid, y: rect.maxY), control: CGPoint(x: mid - 1.5, y: body.maxY + Self.tailHeight * 0.8))
        spike.addQuadCurve(to: CGPoint(x: mid + Self.tailWidth / 2, y: body.maxY - 1), control: CGPoint(x: mid + 1.5, y: body.maxY + Self.tailHeight * 0.8))
        spike.closeSubpath()
        return Path(roundedRect: body, cornerRadius: Self.radius, style: .continuous).union(spike)
    }
}

/// The width of the screen Cap is on, for keeping his bubble inside it.
enum CapScreen {
    @MainActor static var width: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds.width ?? 402
    }
}

/// A tap's squash, stretch, rock and shimmy applied to Cap, on top of whatever else he is doing. Scales and the rock pivot on
/// his feet, so he stays planted.
struct CapPokeEffect: ViewModifier {
    let poke: CapPoke?
    let seconds: Double
    let size: CGFloat

    func body(content: Content) -> some View {
        let frame = poke?.frame(at: seconds) ?? CapFrame()
        content
            .scaleEffect(x: frame.scaleX, y: frame.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(frame.tilt), anchor: .bottom)
            .offset(x: frame.sway * size, y: -frame.lift * size)
    }
}
