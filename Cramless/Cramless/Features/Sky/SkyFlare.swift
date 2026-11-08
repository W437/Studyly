import SwiftUI

/// A save in a session: the star that just lit up again, and the course it belongs to.
struct SaveFlare: Equatable, Identifiable {
    /// Each save has its own, so two in a row both play.
    var id: Int
    var color: CourseColor
    /// When the save happened. The flare plays from here, so one published before the overlay was watching (the very
    /// first question) still plays, and an old one never plays again.
    var at = Date()
}

/// The flare over a session when an answer is a save ("Just in time!"): a four-point star blooms, a ring opens round it
/// and a few motes drift off, about a second in all. It's the memory sky coming into the session, and it has no
/// sound of its own (the save's cue plays with the verdict). Under Reduce Motion the star only fades in and out.
struct SkyFlareView: View {
    let flare: SaveFlare?

    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var shown: SaveFlare?
    @State private var start = Date()

    static let duration = 1.15

    var body: some View {
        ZStack {
            if let shown {
                TimelineView(.animation) { timeline in
                    Canvas { g, size in
                        let t = timeline.date.timeIntervalSince(start)
                        guard t < Self.duration else { return }
                        Self.draw(&g, size: size, t: t, color: shown.color.fill, reduceMotion: reduceMotion)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: flare?.id) {
            guard let flare, Date().timeIntervalSince(flare.at) < Self.duration else { return }
            shown = flare
            start = flare.at
            let left = Self.duration - Date().timeIntervalSince(flare.at)
            // If SwiftUI cancels this (the view was rebuilt), leave the flare as it is: the rebuilt view carries on from
            // the flare's own timestamp.
            do { try await nap(Int(max(0, left) * 1000) + 100) } catch { return }
            if shown == flare { shown = nil }
        }
    }

    // MARK: Drawing

    /// How far the star has grown: 0 at the start, a little over 1 near the end of its first third, then 1 (the
    /// classic ease-out-back curve, a gentle overshoot).
    static func bloom(_ t: Double) -> Double {
        guard t < 0.32 else { return 1 }
        let x = min(1, t / 0.32) - 1
        let s = 1.70158
        return 1 + (s + 1) * x * x * x + s * x * x
    }

    /// 1 until it starts to leave, then down to 0.
    static func fade(_ t: Double) -> Double {
        t < 0.72 ? 1 : max(0, 1 - (t - 0.72) / (duration - 0.72))
    }

    static func star(center: CGPoint, outer: Double, inner: Double) -> Path {
        var path = Path()
        for k in 0..<8 {
            let angle = Double(k) * .pi / 4 - .pi / 2
            let radius = k % 2 == 0 ? outer : inner
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static func draw(_ g: inout GraphicsContext, size: CGSize, t: Double, color: Color, reduceMotion: Bool) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.24)
        let sun = CLColor.sun
        if reduceMotion {
            // A star that fades in, holds and fades out.
            let a = min(1, t / 0.15) * fade(t)
            g.fill(star(center: center, outer: 24, inner: 7), with: .color(sun.opacity(a)))
            return
        }
        let grow = bloom(t)
        let a = fade(t)
        // The glow.
        g.blendMode = .plusLighter
        let glow = 80.0 * grow
        g.fill(Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: 2 * glow, height: 2 * glow)),
               with: .radialGradient(Gradient(colors: [color.opacity(0.55 * a), color.opacity(0)]), center: center, startRadius: 0, endRadius: glow))
        g.blendMode = .normal
        // The ring that opens.
        if t > 0.1 {
            let p = min(1, (t - 0.1) / 0.7)
            let open = 14 + 86 * (1 - pow(1 - p, 3))
            g.stroke(Path(ellipseIn: CGRect(x: center.x - open, y: center.y - open, width: 2 * open, height: 2 * open)),
                     with: .color(color.opacity(0.7 * (1 - p) * a)), lineWidth: 2)
        }
        // Motes drifting out.
        for k in 0..<8 {
            let angle = Double(k) * .pi / 4 + 0.3
            let p = min(1, max(0, (t - 0.12) / 0.8))
            let distance = 22 + 58 * (1 - pow(1 - p, 2)) + Double(k % 3) * 6
            let r = 2.6 * (1 - p) + 0.4
            let at = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
            g.fill(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r)),
                   with: .color(sun.opacity(0.9 * (1 - p) * a)))
        }
        // The star: gold, with a pale heart and rounded tips.
        let outer = 26 * grow
        let shape = star(center: center, outer: outer, inner: outer * 0.3)
        g.fill(shape, with: .color(sun.opacity(a)))
        g.stroke(shape, with: .color(sun.opacity(a)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        g.fill(star(center: center, outer: outer * 0.55, inner: outer * 0.17), with: .color(Color.white.opacity(0.85 * a)))
    }
}
