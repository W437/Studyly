import CoreMotion
import SwiftUI

/// A badge as a medal: a metal rim, a darker disc and the badge's glyph (a streak badge shows its flame), with a sheen that
/// slides across as the phone tilts and the medal turning a few degrees with it. A badge not earned yet is a silhouette.
///
/// The medal itself doesn't read the sensor: it takes `tilt`, each of x and y from -1 to 1, so a grid of them can stand still
/// and the one in the badge sheet (`TiltingMedal`) can move.
struct BadgeMedal: View {
    let badge: Badge
    var earned = true
    var size: CGFloat = 96
    /// x: the right edge down is positive. y: the top leaning away is positive.
    var tilt: CGPoint = .zero

    /// The most the medal turns, in degrees.
    static let reach = 12.0

    private var isFlame: Bool {
        if case .flame = badge.glyph { return true }
        return false
    }

    var body: some View {
        let metal = badge.metal
        ZStack {
            if earned {
                // The medal's shadow is a soft disc of its own beneath it, a gradient and not a blur. (A `.shadow` on the whole
                // medal, a blur, `inset(by:)` and a blended sheen, together in a faded card, drew a second hard-edged medal beside
                // the first on screen: every layer here has its own size and no filter.)
                Circle()
                    .fill(RadialGradient(colors: [metal.deep.opacity(0.42), metal.deep.opacity(0.20), metal.deep.opacity(0)],
                                         center: .center, startRadius: size * 0.25, endRadius: size * 0.58))
                    .frame(width: size * 1.16, height: size * 1.16)
                    .offset(y: size * 0.08)
                Circle()
                    .fill(LinearGradient(colors: [metal.light, metal.mid, metal.deep], startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: size, height: size)
                // A streak badge's flame glows against a night disc (orange on orange would vanish); the rest sit on their metal.
                Circle()
                    .fill(LinearGradient(colors: isFlame ? [Color(hex: 0x26386A), Color(hex: 0x0D1630)] : [metal.mid, metal.deep],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.85, height: size * 0.85)
                Circle()
                    .stroke(metal.light.opacity(0.7), lineWidth: max(1, size * 0.012))
                    .frame(width: size * 0.85, height: size * 0.85)
                glyph(color: Color(hex: 0xFFF6E0))
                sheen(metal.light)
            } else {
                Circle().fill(CLColor.surface3)
                Circle().strokeBorder(CLColor.hairline, lineWidth: max(1, size * 0.018))
                glyph(color: CLColor.ink4.opacity(0.75), lit: false)
            }
        }
        .frame(width: size, height: size)
        .modifier(MedalTurn(tilt: earned ? tilt : .zero))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func glyph(color: Color, lit: Bool = true) -> some View {
        switch badge.glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(color)
                .shadow(color: .black.opacity(earned ? 0.25 : 0), radius: size * 0.02, y: size * 0.015)
        case .flame(let stage):
            StreakFlame(stage: stage, size: size * 0.56, lit: lit)
                .shadow(color: .black.opacity(earned ? 0.22 : 0), radius: size * 0.02, y: size * 0.015)
        }
    }

    /// A pale diagonal band that slides with the tilt, and a soft light that follows it.
    private func sheen(_ light: Color) -> some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.42), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.34, height: size * 1.6)
                .rotationEffect(.degrees(24))
                .offset(x: tilt.x * size * 0.45 - size * 0.12)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: size * 0.34))
                .frame(width: size * 0.7, height: size * 0.7)
                .offset(x: -tilt.x * size * 0.14 - size * 0.12, y: tilt.y * size * 0.14 - size * 0.16)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// The medal turning a few degrees with the phone. A medal that isn't tilted isn't turned at all: an identity 3D turn still
/// makes SwiftUI draw it through a transform layer.
private struct MedalTurn: ViewModifier {
    let tilt: CGPoint

    @ViewBuilder
    func body(content: Content) -> some View {
        if tilt == .zero {
            content
        } else {
            content
                .rotation3DEffect(.degrees(tilt.x * BadgeMedal.reach), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .rotation3DEffect(.degrees(-tilt.y * BadgeMedal.reach), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
        }
    }
}

// MARK: - The sensor

/// The phone's tilt for a medal, smoothed, with where it was held a moment ago as the middle (`HeroTiltFilter`, which Today's
/// world uses too). It has a motion manager of its own: a medal is on screen on its own sheet, and Today's world stops when it
/// isn't the tab in front.
///
/// With no sensor (the Simulator) it sways on its own, slowly. `CRAMLESS_TILT=<pitch>,<roll>` (each -1 to 1) holds a tilt, for
/// screenshots.
@MainActor
@Observable
final class MedalTilt {
    private(set) var x = 0.0
    private(set) var y = 0.0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var filter = HeroTiltFilter()
    @ObservationIgnored private var lastStamp: TimeInterval?

    var hasSensor: Bool { manager.isDeviceMotionAvailable }

    /// A tilt the harness holds, if it asks for one.
    static var held: CGPoint? {
        #if DEBUG
        guard let raw = TestHarness.value("CRAMLESS_TILT") else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: max(-1, min(1, parts[1])), y: max(-1, min(1, parts[0])))
        #else
        return nil
        #endif
    }

    func start() {
        guard hasSensor, !manager.isDeviceMotionActive else { return }
        filter.reset()
        lastStamp = nil
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let side = motion.gravity.x, lean = -motion.gravity.z, stamp = motion.timestamp
            MainActor.assumeIsolated { self?.consume(side: side, lean: lean, at: stamp) }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        filter.reset()
        lastStamp = nil
        x = 0
        y = 0
    }

    private func consume(side: Double, lean: Double, at stamp: TimeInterval) {
        let dt = lastStamp.map { min(0.25, max(0.001, stamp - $0)) } ?? (1.0 / 30.0)
        lastStamp = stamp
        filter.update(side: side, lean: lean, dt: dt)
        x = filter.x
        y = filter.y
    }

    /// The sway a medal shows at `time` seconds when there is no sensor.
    nonisolated static func idle(at time: Double) -> CGPoint {
        CGPoint(x: 0.7 * sin(2 * .pi * time / 9.0), y: 0.4 * sin(2 * .pi * time / 13.0 + 1.1))
    }
}

/// A medal that follows the phone: the sensor's tilt where there is one, a slow sway where there isn't, and a still sheen under
/// Reduce Motion (the medal doesn't turn).
struct TiltingMedal: View {
    let badge: Badge
    var earned = true
    var size: CGFloat = 220

    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var tilt = MedalTilt()

    var body: some View {
        if let held = MedalTilt.held {
            BadgeMedal(badge: badge, earned: earned, size: size, tilt: reduceMotion ? .zero : held)
        } else if reduceMotion || !earned {
            BadgeMedal(badge: badge, earned: earned, size: size)
        } else if tilt.hasSensor {
            BadgeMedal(badge: badge, size: size, tilt: CGPoint(x: tilt.x, y: tilt.y))
                .onAppear { tilt.start() }
                .onDisappear { tilt.stop() }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                BadgeMedal(badge: badge, size: size, tilt: MedalTilt.idle(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        }
    }
}
