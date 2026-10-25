import SwiftUI

/// A few small stars on the night colour, for the welcome screen and the paywall hero: the memory sky's own stars
/// (the same glow, the same slow breath), a hint of what the app will become. Most are bright, one in seven is dim, and
/// they breathe slowly (staggered); under Reduce Motion they stay still. Decorative: hidden from VoiceOver.
struct NightSky: View {
    var count = 14
    /// How far down the stars reach, as a fraction of the height.
    var depth: CGFloat = 0.72

    @Environment(\.clReduceMotion) private var reduceMotion

    /// Nothing breathes under Reduce Motion or in Low Power Mode.
    private var still: Bool { reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: still)) { timeline in
            let time = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                Self.draw(&g, size: size, count: count, depth: depth, time: time, animated: !still)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where star `i` sits, as shares of the width and the height. The prototype's deterministic scatter: no random
    /// numbers, so screenshots repeat.
    static func position(_ i: Int, depth: CGFloat) -> (x: CGFloat, y: CGFloat) {
        (CGFloat((i * 37 + 11) % 100) / 100, (CGFloat((i * 53) % 70) / 70) * depth + 0.04)
    }

    static func draw(_ g: inout GraphicsContext, size: CGSize, count: Int, depth: CGFloat, time: Double, animated: Bool) {
        for i in 0..<count {
            let at = position(i, depth: depth)
            let p = CGPoint(x: size.width * at.x, y: size.height * at.y)
            // Step 6 for the bigger stars, 5 for most, 2 for a dim one now and then.
            let step = i % 4 == 0 ? 6 : i % 7 == 3 ? 2 : 5
            let wobble = SkyRenderer.twinkle(phase: i % 3, restless: false, time: time + Double(i) * 0.9, animated: animated)
            let r = 1.6 * SkyRenderer.radiusFactor[step]
            let alpha = SkyRenderer.alpha[step] * wobble
            let color = CLColor.sky.mix(with: .white, by: 0.5)
            if step >= 5 {
                // The sky's own glow: three faint discs, so it fades out instead of ending at an edge.
                g.blendMode = .plusLighter
                for (scale, opacity) in [(4.6, step >= 6 ? 0.035 : 0), (2.9, 0.06), (1.8, 0.10)] where opacity > 0 {
                    let h = r * scale
                    g.fill(Path(ellipseIn: CGRect(x: p.x - h, y: p.y - h, width: 2 * h, height: 2 * h)),
                           with: .color(color.opacity(opacity * alpha)))
                }
                g.blendMode = .normal
            }
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(color.opacity(alpha)))
        }
    }
}
