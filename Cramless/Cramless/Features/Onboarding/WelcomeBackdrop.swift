import SwiftUI

/// The welcome's still scenery: the dusk, two ridges, the lake and the mounds Cap stands on. Plain shapes and gradients that never
/// change while the screen is up, so nothing here is drawn again with the sky above it: only `WelcomeSkyDrawing`'s canvas is.
/// The same palette and ridges as Today's world (`HeroWorldRenderer`), without its moving layers.
struct WelcomeBackdrop: View {
    let geometry: HeroWorldGeometry

    private static let farTop = Color(hex: 0x333E78), farBottom = Color(hex: 0x1A2350)
    private static let midTop = Color(hex: 0x212D5E), midBottom = Color(hex: 0x121C3E)
    private static let waterTop = Color(hex: 0x24396E), waterBottom = Color(hex: 0x0C1432)
    private static let groundTop = Color(hex: 0x131F3E), groundBottom = Color(hex: 0x080E22)
    private static let crest = Color(hex: 0xB9C6FF)

    var body: some View {
        let g = geometry
        let farWaves: [Ridge.Wave] = [.init(amp: 12, length: 74, phase: 0.8), .init(amp: 6, length: 33, phase: 2.1), .init(amp: 3, length: 17, phase: 4.0)]
        let midWaves: [Ridge.Wave] = [.init(amp: 9, length: 58, phase: 2.3), .init(amp: 5, length: 26, phase: 0.4), .init(amp: 2.5, length: 13, phase: 5.1)]
        ZStack(alignment: .topLeading) {
            // The night, a little lighter and warmer toward the horizon.
            Rectangle().fill(LinearGradient(
                stops: [.init(color: Color(hex: 0x050A17), location: 0), .init(color: Color(hex: 0x0A1330), location: 0.40),
                        .init(color: Color(hex: 0x121C46), location: 0.64), .init(color: Color(hex: 0x231F58), location: 0.80),
                        .init(color: Color(hex: 0x42285F), location: 0.92), .init(color: Color(hex: 0x6E3A5E), location: 1)],
                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: g.farHills / g.height)))
            // The last of the day behind the ridge.
            Rectangle().fill(LinearGradient(colors: [Color(hex: 0xE4708C).opacity(0), Color(hex: 0xE4708C).opacity(0.16), Color(hex: 0xFFB070).opacity(0.30)],
                                            startPoint: .top, endPoint: .bottom))
                .frame(height: g.compact ? 70 : 150)
                .offset(y: g.farHills - (g.compact ? 62 : 140))
            Ridge(base: g.farHills, waves: farWaves)
                .fill(LinearGradient(colors: [Self.farTop, Self.farBottom], startPoint: UnitPoint(x: 0, y: (g.farHills - 20) / g.height), endPoint: .bottom))
            RidgeCrest(base: g.farHills, waves: farWaves).stroke(Self.crest.opacity(0.20), lineWidth: 1.1)
            Ridge(base: g.midHills, waves: midWaves)
                .fill(LinearGradient(colors: [Self.midTop, Self.midBottom], startPoint: UnitPoint(x: 0, y: (g.midHills - 14) / g.height), endPoint: .bottom))
            RidgeCrest(base: g.midHills, waves: midWaves).stroke(Self.crest.opacity(0.11), lineWidth: 1)
            // The lake, with a thin line of light where it meets the land.
            Rectangle().fill(LinearGradient(colors: [Self.waterTop, Self.waterBottom], startPoint: .top, endPoint: .bottom))
                .frame(height: g.height - g.lakeTop)
                .offset(y: g.lakeTop)
            Rectangle().fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.20), .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .offset(y: g.lakeTop)
            if !g.compact {
                // The ground in front, where Cap stands, and a small knoll on the other side.
                Ellipse().fill(LinearGradient(colors: [Self.groundTop, Self.groundBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(Ellipse().stroke(.white.opacity(0.07), lineWidth: 1))
                    .frame(width: g.width * 0.80, height: 80)
                    .offset(x: -g.width * 0.18, y: g.height - 30)
                Ellipse().fill(Self.groundBottom.opacity(0.9))
                    .frame(width: g.width * 0.5, height: 56)
                    .offset(x: g.width * 0.74, y: g.height - 16)
            }
        }
        .frame(width: g.width, height: g.height, alignment: .topLeading)
        .clipped()
        .accessibilityHidden(true)
    }

    /// A ridge: a few sine waves around `base`, filled down to the bottom of the frame.
    struct Ridge: Shape {
        struct Wave: Equatable { var amp: CGFloat; var length: CGFloat; var phase: CGFloat }
        var base: CGFloat
        var waves: [Wave]

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX - 40, y: rect.maxY + 2))
            var x = rect.minX - 40
            while x <= rect.maxX + 40 {
                path.addLine(to: CGPoint(x: x, y: Self.height(at: x, base: base, waves: waves)))
                x += 5
            }
            path.addLine(to: CGPoint(x: rect.maxX + 40, y: rect.maxY + 2))
            path.closeSubpath()
            return path
        }

        static func height(at x: CGFloat, base: CGFloat, waves: [Wave]) -> CGFloat {
            waves.reduce(base) { $0 + $1.amp * sin(x / $1.length + $1.phase) }
        }
    }

    /// The same ridge's crest as a line.
    struct RidgeCrest: Shape {
        var base: CGFloat
        var waves: [Ridge.Wave]

        func path(in rect: CGRect) -> Path {
            var path = Path()
            var x = rect.minX - 40
            var first = true
            while x <= rect.maxX + 40 {
                let p = CGPoint(x: x, y: Ridge.height(at: x, base: base, waves: waves))
                if first { path.move(to: p); first = false } else { path.addLine(to: p) }
                x += 5
            }
            return path
        }
    }
}
