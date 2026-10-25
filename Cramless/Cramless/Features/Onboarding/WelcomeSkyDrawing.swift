import SwiftUI

/// Draws the welcome's sky each frame: the faint stars, the constellation and everything that happens to it, and its reflection in
/// the lake. Light on purpose: about fifty plain fills and strokes, a radial gradient for each lit star, no blend modes, shadows or
/// offscreen layers, and the faint stars' paths built once per size. The still scenery is `WelcomeBackdrop`'s, under it.
enum WelcomeSkyDrawing {
    /// A touch's ripple: where, and when (seconds on the world's clock).
    struct Ripple: Equatable, Sendable {
        var point: CGPoint
        var start: Double
    }

    /// Everything one frame needs.
    struct Frame {
        /// Seconds on the world's clock.
        var time: Double
        /// The phone's tilt, each -1 to 1 (or the idle sway when there is no motion sensor).
        var tilt: CGPoint
        /// Where the constellation is seen from, tilt included (what a finger's touch is tested against too).
        var camera: SkyCamera
        var geometry: HeroWorldGeometry
        /// Per star: when it ignites (negative infinity: already lit), or nil while it is dark.
        var litAt: [Double?]
        /// The star a ring marks as the next to touch.
        var hint: Int?
        var ripples: [Ripple]
        /// When all the cap lit: its glow and shooting star start from here.
        var finaleAt: Double?
        /// Reduce Motion: nothing twinkles, ripples or crosses the sky; a star is lit or it isn't.
        var calm: Bool
    }

    private static let cool = Color(hex: 0xEAF0FF)
    private static let warm = Color(hex: 0xFFF1CF)
    private static let gold = Color(hex: 0xFFC96B)
    private static let lineWarm = Color(hex: 0xFFE9B5)

    /// The faint stars as paths, one for each twinkle group and brightness, made when the size changes and not every frame.
    final class StarCache: @unchecked Sendable {
        private var key: [CGFloat] = []
        private var made: [[Path]] = []

        func paths(size: CGSize, top: CGFloat, bottom: CGFloat) -> [[Path]] {
            let wanted = [size.width, size.height, top, bottom]
            if wanted == key { return made }
            var groups = [[Path]](repeating: [Path](repeating: Path(), count: 3), count: 3)
            for dot in WelcomeLook.starField() {
                let x = dot.x * size.width, y = top + dot.y * max(1, bottom - top), r = dot.radius
                groups[dot.group][dot.tier].addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            key = wanted
            made = groups
            return groups
        }
    }

    static func draw(_ g: inout GraphicsContext, size: CGSize, frame f: Frame, stars: StarCache) {
        #if DEBUG
        let started = ContinuousClock.now
        defer { HeroPerf.record(ContinuousClock.now - started, stars: WelcomeSky.count) }   // CRAMLESS_SKY_PERF=1 logs "hero frame: …"
        #endif
        guard size.width > 1, size.height > 1 else { return }
        faintStars(&g, size: size, f, stars)
        glow(&g, size: size, f)
        shootingStar(&g, size: size, f)
        constellation(&g, size: size, f)
        reflection(&g, size: size, f)
        ripples(&g, f)
    }

    // MARK: Layers

    private static func faintStars(_ g: inout GraphicsContext, size: CGSize, _ f: Frame, _ cache: StarCache) {
        let paths = cache.paths(size: size, top: f.geometry.skyTop, bottom: f.geometry.farHills - 26)
        var layer = g
        layer.translateBy(x: f.tilt.x * WelcomeLook.faintReach, y: f.tilt.y * WelcomeLook.faintReach * 0.55)
        for group in 0..<3 {
            let wobble = f.calm ? 1 : WelcomeLook.twinkle(group: group, time: f.time)
            for tier in 0..<3 where !paths[group][tier].isEmpty {
                layer.fill(paths[group][tier], with: .color(cool.opacity(WelcomeLook.tierAlpha[tier] * wobble)))
            }
        }
    }

    /// The glow behind the cap when all of it is lit: one soft radial wash.
    private static func glow(_ g: inout GraphicsContext, size: CGSize, _ f: Frame) {
        guard let start = f.finaleAt else { return }
        let strength = WelcomeLook.glow(after: f.time - start)
        guard strength > 0.002 else { return }
        let middle = f.camera.screen(SkyPoint(x: WelcomeSky.layout.width / 2, y: WelcomeSky.layout.height / 2), in: size)
        let radius = size.width * 0.85
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(Gradient(colors: [gold.opacity(strength), gold.opacity(strength * 0.3), gold.opacity(0)]),
                                     center: middle, startRadius: 0, endRadius: radius))
    }

    /// One thin shooting star across the upper sky as the cap lights.
    private static func shootingStar(_ g: inout GraphicsContext, size: CGSize, _ f: Frame) {
        guard !f.calm, let start = f.finaleAt, let progress = WelcomeLook.shooting(after: f.time - start - 0.15) else { return }
        let top = f.geometry.skyTop
        let from = CGPoint(x: size.width * 0.08, y: top + 14), to = CGPoint(x: size.width * 0.92, y: top + size.height * 0.2)
        let head = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
        let tail = CGPoint(x: head.x - (to.x - from.x) * 0.12, y: head.y - (to.y - from.y) * 0.12)
        let fade = sin(.pi * progress)
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        g.stroke(path, with: .linearGradient(Gradient(colors: [cool.opacity(0), cool.opacity(0.9 * fade)]), startPoint: tail, endPoint: head),
                 style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    private static func isLit(_ f: Frame, _ star: Int) -> Bool { f.litAt[star].map { f.time >= $0 } ?? false }

    private static func constellation(_ g: inout GraphicsContext, size: CGSize, _ f: Frame) {
        let points = WelcomeSky.points.map { f.camera.screen($0, in: size) }
        let t = f.time

        // The lines: dashed while they wait, drawn solid from the star that lit last toward the one that lit before it.
        var waiting = Path()
        for line in WelcomeSky.lines {
            let a = points[line.a], b = points[line.b]
            guard let la = f.litAt[line.a], let lb = f.litAt[line.b], t >= max(la, lb) else {
                waiting.move(to: a)
                waiting.addLine(to: b)
                continue
            }
            let progress = f.calm ? 1 : WelcomeLook.lineProgress(after: t - max(la, lb))
            let (from, to) = la >= lb ? (a, b) : (b, a)
            let end = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
            var solid = Path()
            solid.move(to: from)
            solid.addLine(to: end)
            g.stroke(solid, with: .color(gold.opacity(0.13)), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
            g.stroke(solid, with: .color(lineWarm.opacity(0.85)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            if progress < 1 {
                waiting.move(to: end)
                waiting.addLine(to: to)
            }
        }
        g.stroke(waiting, with: .color(cool.opacity(0.22)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, dash: [2, 5]))

        // The stars still dark: a small ring with a point in it, breathing (the fragile ones faster).
        for star in points.indices where !isLit(f, star) {
            let p = points[star]
            let breath = f.calm ? 1 : WelcomeLook.breath(star: star, time: t)
            g.stroke(Path(ellipseIn: CGRect(x: p.x - 3.8, y: p.y - 3.8, width: 7.6, height: 7.6)), with: .color(cool.opacity(0.55 * breath)), lineWidth: 1)
            g.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)), with: .color(cool.opacity(0.85 * breath)))
        }

        // The stars lit: a soft glow, a disc, and while one ignites a ring, a glint and a swell.
        for star in points.indices where isLit(f, star) {
            let p = points[star]
            let e = f.calm ? WelcomeLook.Ignition.settled : WelcomeLook.ignition(after: t - (f.litAt[star] ?? t))
            let reach = 30.0
            g.fill(Path(ellipseIn: CGRect(x: p.x - reach, y: p.y - reach, width: 2 * reach, height: 2 * reach)),
                   with: .radialGradient(Gradient(stops: [.init(color: gold.opacity(0.9 * e.halo), location: 0), .init(color: gold.opacity(0.32 * e.halo), location: 0.42),
                                                          .init(color: gold.opacity(0), location: 1)]),
                                         center: p, startRadius: 0, endRadius: reach))
            if e.ringAlpha > 0.01 {
                g.stroke(Path(ellipseIn: CGRect(x: p.x - e.ringRadius, y: p.y - e.ringRadius, width: 2 * e.ringRadius, height: 2 * e.ringRadius)),
                         with: .color(gold.opacity(e.ringAlpha)), lineWidth: 1.2)
            }
            if e.glintAlpha > 0.02 {
                var cross = Path()
                cross.move(to: CGPoint(x: p.x - e.glint, y: p.y)); cross.addLine(to: CGPoint(x: p.x + e.glint, y: p.y))
                cross.move(to: CGPoint(x: p.x, y: p.y - e.glint)); cross.addLine(to: CGPoint(x: p.x, y: p.y + e.glint))
                g.stroke(cross, with: .color(warm.opacity(e.glintAlpha)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            }
            let r = 4.0 * e.core
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(cool.mix(with: warm, by: e.brightness)))
        }

        // The star to touch next: a ring that opens and fades.
        if let hint = f.hint, !isLit(f, hint) {
            let p = points[hint]
            let ring = f.calm ? (radius: 12.0, alpha: 0.4) : WelcomeLook.hint(at: t)
            g.stroke(Path(ellipseIn: CGRect(x: p.x - ring.radius, y: p.y - ring.radius, width: 2 * ring.radius, height: 2 * ring.radius)),
                     with: .color(gold.opacity(ring.alpha)), lineWidth: 1.2)
        }
    }

    /// The lit stars again, flattened into the lake: a short dash each, wavering a little.
    private static func reflection(_ g: inout GraphicsContext, size: CGSize, _ f: Frame) {
        let geometry = f.geometry
        guard !geometry.compact else { return }
        for star in WelcomeSky.points.indices {
            guard let lit = f.litAt[star], f.time >= lit else { continue }
            let p = f.camera.screen(WelcomeSky.points[star], in: size)
            let y = geometry.lakeTop + 5 + min(geometry.lakeDepth - 8, (geometry.lakeTop - p.y) * 0.085)
            let sway = f.calm ? 0 : sin(f.time * 1.6 + Double(star) * 1.3) * 1.6
            let rise = f.calm ? 1 : min(1, (f.time - lit) / 0.6)
            g.fill(Path(roundedRect: CGRect(x: p.x - 5 + sway, y: y, width: 10, height: 1.2), cornerRadius: 0.6), with: .color(warm.opacity(0.4 * rise)))
        }
    }

    private static func ripples(_ g: inout GraphicsContext, _ f: Frame) {
        guard !f.calm else { return }
        for ripple in f.ripples {
            guard let r = WelcomeLook.ripple(after: f.time - ripple.start) else { continue }
            g.stroke(Path(ellipseIn: CGRect(x: ripple.point.x - r.radius, y: ripple.point.y - r.radius, width: 2 * r.radius, height: 2 * r.radius)),
                     with: .color(cool.opacity(r.alpha)), lineWidth: 1)
        }
    }
}
