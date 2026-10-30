import SwiftUI

/// Small pictures of the sky for Progress: an exam's region on its card, and a constellation beside its name.
/// Decorative; the words beside them say the same thing.

/// An exam's region as a still: its constellations in a circle of sky, glowing. `scene` is the region itself
/// (`SkyScene.region(of:)`), already fitted to a square.
struct SkyRegionStill: View {
    let scene: SkyScene
    var cornerRadius: CGFloat = 18

    @Environment(\.clDifferentiateWithoutColor) private var differentiate
    @Environment(\.skyTheme) private var skyTheme

    var body: some View {
        Canvas { g, size in
            let camera = SkyCamera.fit(scene.layout, in: size)
            SkyRenderer.draw(&g, size: size, frame: SkyFrame(
                scene: scene, plan: SkyPlan(scene), camera: camera, time: 0, animated: false, differentiate: differentiate,
                restlessRing: true, focus: nil, litRegion: scene.layout.regions.first?.examID, recede: 0, starScale: 1.7,
                playback: nil, labels: false, palette: skyTheme.palette))
        }
        .background(LinearGradient(colors: [skyTheme.palette.top, skyTheme.palette.bottom], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// One constellation as a glyph: bright stars filled, dim ones faint, unlit ones rings, joined by faint lines, on a
/// night tile.
struct SkyGlyphView: View {
    let glyph: SkyGlyph
    var size: CGFloat = 46

    @Environment(\.clDifferentiateWithoutColor) private var differentiate
    @Environment(\.skyTheme) private var skyTheme

    var body: some View {
        Canvas { g, canvas in
            Self.draw(&g, glyph, in: canvas, differentiate: differentiate)
        }
        .frame(width: size, height: size)
        .background(LinearGradient(colors: [skyTheme.palette.top, skyTheme.palette.bottom], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The glyph's marks: lines, then each star by how it shines.
    static func draw(_ g: inout GraphicsContext, _ glyph: SkyGlyph, in size: CGSize, differentiate: Bool = false) {
        let color = glyph.color.fill
        func at(_ s: SkyGlyph.Star) -> CGPoint { CGPoint(x: s.x * size.width, y: s.y * size.height) }
        var lines = Path()
        for line in glyph.lines where glyph.stars.indices.contains(line.a) && glyph.stars.indices.contains(line.b) {
            lines.move(to: at(glyph.stars[line.a]))
            lines.addLine(to: at(glyph.stars[line.b]))
        }
        g.stroke(lines, with: .color(color.opacity(0.38)), lineWidth: 0.8)
        let unit = min(size.width, size.height) / 46
        for s in glyph.stars {
            let p = at(s)
            if s.hollow {
                let r = 2.6 * unit
                g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(color.opacity(0.7)), lineWidth: 1)
            } else if s.dim {
                let r = 1.7 * unit
                g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(color.opacity(0.42)))
            } else {
                let r = (2.2 + 0.9 * s.brightness) * unit
                g.blendMode = .plusLighter
                let h = r * 2.4
                g.fill(Path(ellipseIn: CGRect(x: p.x - h, y: p.y - h, width: 2 * h, height: 2 * h)),
                       with: .color(color.opacity(0.14)))
                g.blendMode = .normal
                g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(color.mix(with: .white, by: 0.4)))
                if differentiate {
                    let a = r * 2.2
                    var cross = Path()
                    cross.move(to: CGPoint(x: p.x - a, y: p.y)); cross.addLine(to: CGPoint(x: p.x + a, y: p.y))
                    cross.move(to: CGPoint(x: p.x, y: p.y - a)); cross.addLine(to: CGPoint(x: p.x, y: p.y + a))
                    g.stroke(cross, with: .color(.white.opacity(0.8)), lineWidth: 0.8)
                }
            }
        }
    }
}
