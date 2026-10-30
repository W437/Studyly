import SwiftUI

/// A small picture of a sky: its gradient, the dusk at the horizon, a few stars with a little constellation, and the hills.
/// It is drawn from the same palette the world uses (`SkyPalette`), so what the picker shows is what Today becomes. A sky not
/// lit yet shows as a dim grey shape with a lock.
struct SkySwatch: View {
    let theme: SkyTheme
    var width: CGFloat = 96
    var height: CGFloat = 120
    var locked = false

    /// Where the faint stars sit, as shares of the swatch (the same in every sky, so they compare).
    private static let stars: [(x: Double, y: Double, r: Double)] = [
        (0.10, 0.10, 0.9), (0.24, 0.26, 0.7), (0.36, 0.08, 1.0), (0.52, 0.20, 0.7), (0.66, 0.06, 0.8), (0.80, 0.22, 1.0),
        (0.90, 0.10, 0.7), (0.16, 0.42, 0.8), (0.46, 0.38, 0.7), (0.74, 0.40, 0.9), (0.92, 0.34, 0.7), (0.06, 0.28, 0.6),
    ]
    /// A little constellation in three course colours.
    private static let shape: [(x: Double, y: Double, color: Color)] = [
        (0.30, 0.20, CLColor.sky), (0.50, 0.12, CLColor.sun), (0.70, 0.28, CLColor.rose),
    ]

    var body: some View {
        let palette = theme.palette
        Canvas { g, size in
            let w = size.width, h = size.height
            let horizon = h * 0.64
            g.fill(Path(CGRect(origin: .zero, size: size)),
                   with: .linearGradient(Gradient(colors: [palette.top, palette.bottom]), startPoint: .zero,
                                         endPoint: CGPoint(x: 0, y: h)))
            // The dusk at the horizon.
            let glow = Gradient(stops: [.init(color: palette.glowHigh.opacity(0), location: 0),
                                        .init(color: palette.glowHigh.opacity(0.34), location: 0.38),
                                        .init(color: palette.glowMid.opacity(0.42), location: 0.74),
                                        .init(color: palette.glowLow.opacity(0.62), location: 1)])
            g.blendMode = .plusLighter
            g.fill(Path(CGRect(x: 0, y: horizon - h * 0.46, width: w, height: h * 0.46 + 4)),
                   with: .linearGradient(glow, startPoint: CGPoint(x: 0, y: horizon - h * 0.46), endPoint: CGPoint(x: 0, y: horizon + 4)))
            g.blendMode = .normal
            // Stars, then the constellation.
            for star in Self.stars {
                let r = max(0.5, w * 0.008 * star.r)
                g.fill(Path(ellipseIn: CGRect(x: w * star.x - r, y: h * star.y * 0.9 - r, width: 2 * r, height: 2 * r)),
                       with: .color(palette.dustCool.opacity(0.85)))
            }
            var line = Path()
            for (index, point) in Self.shape.enumerated() {
                let p = CGPoint(x: w * point.x, y: h * point.y * 0.9)
                index == 0 ? line.move(to: p) : line.addLine(to: p)
            }
            g.stroke(line, with: .color(.white.opacity(0.28)), lineWidth: max(0.6, w * 0.008))
            for point in Self.shape {
                let r = max(1.4, w * 0.026)
                let c = CGPoint(x: w * point.x, y: h * point.y * 0.9)
                g.fill(Path(ellipseIn: CGRect(x: c.x - r * 2.6, y: c.y - r * 2.6, width: r * 5.2, height: r * 5.2)),
                       with: .color(point.color.opacity(0.22)))
                g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(point.color))
            }
            // Hills, the lit ridge, the lake and the ground.
            var far = Path()
            far.move(to: CGPoint(x: 0, y: horizon + h * 0.01))
            far.addCurve(to: CGPoint(x: w * 0.5, y: horizon - h * 0.02), control1: CGPoint(x: w * 0.16, y: horizon - h * 0.08),
                         control2: CGPoint(x: w * 0.32, y: horizon - h * 0.10))
            far.addCurve(to: CGPoint(x: w, y: horizon), control1: CGPoint(x: w * 0.68, y: horizon + h * 0.04),
                         control2: CGPoint(x: w * 0.84, y: horizon - h * 0.06))
            var farFill = far
            farFill.addLine(to: CGPoint(x: w, y: h))
            farFill.addLine(to: CGPoint(x: 0, y: h))
            farFill.closeSubpath()
            g.fill(farFill, with: .linearGradient(Gradient(colors: [palette.farHills.top, palette.farHills.bottom]),
                                                  startPoint: CGPoint(x: 0, y: horizon - h * 0.1), endPoint: CGPoint(x: 0, y: h)))
            g.stroke(far, with: .color(palette.crestWarm.opacity(0.7)), lineWidth: max(0.7, w * 0.010))
            var mid = Path()
            mid.move(to: CGPoint(x: 0, y: horizon + h * 0.12))
            mid.addCurve(to: CGPoint(x: w * 0.55, y: horizon + h * 0.12), control1: CGPoint(x: w * 0.2, y: horizon + h * 0.04),
                         control2: CGPoint(x: w * 0.38, y: horizon + h * 0.08))
            mid.addCurve(to: CGPoint(x: w, y: horizon + h * 0.10), control1: CGPoint(x: w * 0.72, y: horizon + h * 0.15),
                         control2: CGPoint(x: w * 0.88, y: horizon + h * 0.06))
            mid.addLine(to: CGPoint(x: w, y: h))
            mid.addLine(to: CGPoint(x: 0, y: h))
            mid.closeSubpath()
            g.fill(mid, with: .linearGradient(Gradient(colors: [palette.midHills.top, palette.midHills.bottom]),
                                              startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
            g.fill(Path(CGRect(x: 0, y: horizon + h * 0.2, width: w, height: h)),
                   with: .linearGradient(Gradient(colors: [palette.water.top, palette.water.bottom]),
                                         startPoint: CGPoint(x: 0, y: horizon + h * 0.2), endPoint: CGPoint(x: 0, y: h)))
            var ground = Path()
            ground.move(to: CGPoint(x: 0, y: h * 0.90))
            ground.addCurve(to: CGPoint(x: w, y: h * 0.88), control1: CGPoint(x: w * 0.35, y: h * 0.84), control2: CGPoint(x: w * 0.7, y: h * 0.90))
            ground.addLine(to: CGPoint(x: w, y: h))
            ground.addLine(to: CGPoint(x: 0, y: h))
            ground.closeSubpath()
            g.fill(ground, with: .linearGradient(Gradient(colors: [palette.ground.top, palette.ground.bottom]),
                                                 startPoint: CGPoint(x: 0, y: h * 0.84), endPoint: CGPoint(x: 0, y: h)))
        }
        .frame(width: width, height: height)
        .saturation(locked ? 0 : 1)
        .opacity(locked ? 0.4 : 1)
        .overlay {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: min(width, height) * 0.24, weight: .semibold))
                    .foregroundStyle(CLColor.ink2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: min(width, height) * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}
