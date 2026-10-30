import SwiftUI

// Drawing the memory sky. Stars are batched: every star of one course colour, brightness step, restlessness and
// twinkle phase goes into one path, so two thousand stars are a few dozen fills, not two thousand. What stays the
// same from frame to frame (`SkyPlan`) is worked out once per scene.

// MARK: - Plan

/// The parts of a scene that don't change between frames: each star's colour, step and twinkle phase.
struct SkyPlan {
    /// Per star: its batch, or `hollow` for an item never studied.
    let group: [UInt16]
    /// Per star: the course colour's index in `SkyPlan.colors`.
    let color: [UInt8]
    static let hollow = UInt16.max

    static let colors = CourseColor.allCases
    static let steps = 8
    /// Steps 0…3 are dim stars, 4…7 bright ones.
    static let dimSteps = 4
    static let groupCount = colors.count * steps * 2 * 3

    init(_ scene: SkyScene) {
        let layout = scene.layout, light = scene.light
        var group = [UInt16](repeating: Self.hollow, count: layout.stars.count)
        var color = [UInt8](repeating: 0, count: layout.stars.count)
        let colorIndex = Dictionary(uniqueKeysWithValues: Self.colors.enumerated().map { ($1, $0) })
        for (i, star) in layout.stars.enumerated() {
            let c = layout.constellations[star.constellation]
            let ci = colorIndex[scene.color(of: c)] ?? 0
            color[i] = UInt8(ci)
            if light.hollow[i] { continue }
            let step = Self.step(brightness: light.brightness[i], dim: light.isDim(i))
            let restless = light.flicker[i] >= 0.5 ? 1 : 0
            let phase = Int(StableRandom.seed(star.id, day: 0, salt: 0x91) % 3)
            group[i] = UInt16(((ci * Self.steps + step) * 2 + restless) * 3 + phase)
        }
        self.group = group
        self.color = color
    }

    /// This plan if it was made for a sky of `scene`'s size, else nil. A scene that has just grown (questions added from Today, with the
    /// hero still on screen behind the sheet) reaches the canvas a frame before its new plan does; drawing with the old one reads past its end.
    func fitting(_ scene: SkyScene) -> SkyPlan? {
        group.count == scene.layout.stars.count ? self : nil
    }

    /// Dim stars spread over steps 0…3 by their brightness, bright ones over 4…7.
    static func step(brightness b: Double, dim: Bool) -> Int {
        let edge = SkyEngine.brightness(recall: ReviewOutcome.fadingRecall)
        if dim { return min(dimSteps - 1, max(0, Int(b / max(edge, 0.01) * Double(dimSteps)))) }
        let t = (b - edge) / max(1 - edge, 0.01)
        return dimSteps + min(dimSteps - 1, max(0, Int(t * Double(dimSteps))))
    }

    static func decode(_ g: Int) -> (color: Int, step: Int, restless: Bool, phase: Int) {
        let phase = g % 3, r = g / 3
        let restless = r % 2 == 1, s = r / 2
        return (s / steps, s % steps, restless, phase)
    }
}

// MARK: - Playback

/// Stars igniting after a session: each relit star rises from where it began to where it is now, in a sweep through
/// the constellations, with a ring that opens round it. Saves get a gold ring and a sparkle.
struct SkyPlayback: Equatable {
    var start: Double
    var relight: SkyRelight
    /// Per star: the time (on the animation clock) its ignition ends, or `-infinity` for a star that isn't playing.
    private(set) var ends: [Double]
    private(set) var begins: [Double]
    private(set) var end: Double

    static let igniteSeconds = 0.8

    init(start: Double, relight: SkyRelight, layout: SkyLayout) {
        self.start = start
        self.relight = relight
        var begins = [Double](repeating: -.infinity, count: layout.stars.count)
        var ends = begins
        let playing = layout.stars.indices.filter { relight.relit.contains(layout.stars[$0].id) }
        let spread = min(1.4, 0.06 * Double(playing.count))
        var last = start
        for (k, i) in playing.enumerated() {
            let delay = playing.count > 1 ? spread * Double(k) / Double(playing.count - 1) : 0
            begins[i] = start + delay
            ends[i] = start + delay + Self.igniteSeconds
            last = max(last, ends[i])
        }
        self.begins = begins
        self.ends = ends
        self.end = last
    }

    func isPlaying(_ i: Int, at time: Double) -> Bool { ends[i] > time }
    /// 0 before the star ignites, rising to 1 when it has.
    func progress(_ i: Int, at time: Double) -> Double {
        guard ends[i].isFinite else { return 1 }
        return min(1, max(0, (time - begins[i]) / Self.igniteSeconds))
    }
    func isDone(at time: Double) -> Bool { time >= end }
}

// MARK: - Frame

/// Everything one frame needs.
struct SkyFrame {
    var scene: SkyScene
    var plan: SkyPlan
    var camera: SkyCamera
    /// Seconds on the animation clock.
    var time: Double
    /// Twinkling and flickering run. Off for Reduce Motion, Low Power Mode and stills.
    var animated: Bool
    /// Differentiate Without Color: bright stars get a cross, so no state is colour alone.
    var differentiate: Bool
    /// Restless stars get a dashed ring instead of a flutter: for Reduce Motion, and for Differentiate Without Color.
    var restlessRing = false
    /// The focused constellation: the others dim away.
    var focus: Int?
    /// An exam whose region is lit: the constellations inside it shine, the rest dim away (exam eve on Today).
    var litRegion: UUID?
    /// How much of the others shows while something is focused or lit: a little, or none at all.
    var recede = 0.32
    /// Stars drawn this much larger: the small pictures (Today's band, a region's still) need bigger stars to read.
    var starScale = 1.0
    var playback: SkyPlayback?
    /// Names of constellations and exams.
    var labels = true
    /// The brightest stars get a faint four-point glint, as in a photograph of the night sky (Today's world).
    var spikes = false
    /// Constellation lines, in points: a little heavier in the hero, where they are drawn large.
    var lineWidth = 0.9
    /// While one constellation is focused or lit, how far (0 to 1) its dim stars, rings and lines are lifted toward full
    /// brightness, so a fading constellation is still easy to see when you have come in to look at it. Today's hero uses it.
    var focusLift = 0.0
    /// The sky behind the stars (`SkyTheme`): the text on it gets a shadow of its own darkest colour.
    var palette = SkyPalette.night
}

// MARK: - Renderer

enum SkyRenderer {
    /// The default sky's background: night, a little lighter towards the horizon. The sky a person has chosen
    /// (`SkyTheme`) comes with the frame's palette; these are Night's, for what isn't on screen with a theme.
    static let top = SkyPalette.night.top
    static let bottom = SkyPalette.night.bottom

    static func draw(_ g: inout GraphicsContext, size: CGSize, frame f: SkyFrame) {
        #if DEBUG
        let started = ContinuousClock.now
        defer { SkyPerf.record(ContinuousClock.now - started, stars: f.scene.starCount) }
        #endif
        guard size.width > 1, size.height > 1, !f.scene.isEmpty else { return }
        let layout = f.scene.layout, camera = f.camera
        let spacing = camera.scale
        // The core's radius: a star is a point in a wide view and grows a little as you zoom in.
        let r0 = min(5.0, max(1.5, spacing * 0.15)) * f.starScale
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -24, dy: -24)
        let many = layout.stars.count > 3000

        drawRegions(&g, f, size: size)
        let lit = litConstellations(f)
        let backdrop = lit == nil ? 1.0 : f.recede

        drawLines(&g, f, size: size, lit: lit, backdrop: backdrop)

        // Stars: one set of paths for the constellations that shine and one for the rest.
        var paths = [[Path]](repeating: [Path](repeating: Path(), count: SkyPlan.groupCount), count: 2)
        var halos = paths, blooms = paths, glows = paths
        var rings: [[Path]] = [[Path]](repeating: [Path](repeating: Path(), count: SkyPlan.colors.count), count: 2)
        var crosses = rings, dashes = rings, glints = rings
        let playback = f.playback

        for i in layout.stars.indices {
            if let playback, playback.isPlaying(i, at: f.time) { continue }
            let p = camera.screen(layout.stars[i].point, in: size)
            guard visible.contains(p) else { continue }
            let set = lit.map { $0[layout.stars[i].constellation] ? 1 : 0 } ?? 1
            if set == 0, backdrop == 0 { continue }
            let g16 = f.plan.group[i]
            let ci = Int(f.plan.color[i])
            if g16 == SkyPlan.hollow {
                let r = r0 * 1.45
                rings[set][ci].addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                continue
            }
            let (_, step, restless, _) = SkyPlan.decode(Int(g16))
            let r = r0 * radiusFactor[step]
            let gi = Int(g16)
            paths[set][gi].addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            if step >= 5, !many || spacing > 7 {
                // The glow is three faint discs, so it fades out instead of ending at an edge.
                let h = r * 1.8
                halos[set][gi].addEllipse(in: CGRect(x: p.x - h, y: p.y - h, width: 2 * h, height: 2 * h))
                if !many {
                    let g1 = r * 2.9
                    glows[set][gi].addEllipse(in: CGRect(x: p.x - g1, y: p.y - g1, width: 2 * g1, height: 2 * g1))
                    if step >= 6 {
                        let b = r * 4.6
                        blooms[set][gi].addEllipse(in: CGRect(x: p.x - b, y: p.y - b, width: 2 * b, height: 2 * b))
                    }
                }
            }
            if f.spikes, step >= 6, spacing > 6 {
                // Two thin lines through the star, longer for the brightest, that taper to nothing at the ends.
                let a = r * (step >= 7 ? 4.4 : 3.2)
                glints[set][ci].move(to: CGPoint(x: p.x - a, y: p.y)); glints[set][ci].addLine(to: CGPoint(x: p.x + a, y: p.y))
                glints[set][ci].move(to: CGPoint(x: p.x, y: p.y - a)); glints[set][ci].addLine(to: CGPoint(x: p.x, y: p.y + a))
            }
            if f.differentiate, step >= SkyPlan.dimSteps {
                let a = r * 2.4
                crosses[set][ci].move(to: CGPoint(x: p.x - a, y: p.y)); crosses[set][ci].addLine(to: CGPoint(x: p.x + a, y: p.y))
                crosses[set][ci].move(to: CGPoint(x: p.x, y: p.y - a)); crosses[set][ci].addLine(to: CGPoint(x: p.x, y: p.y + a))
            }
            if restless, step >= SkyPlan.dimSteps, f.restlessRing || f.differentiate {
                let d = r * 2.1
                dashes[set][ci].addEllipse(in: CGRect(x: p.x - d, y: p.y - d, width: 2 * d, height: 2 * d))
            }
        }

        let palette = SkyPlan.colors.map(\.fill)
        for set in 0..<2 {
            let fade = set == 1 ? 1.0 : backdrop
            // Glow first, then cores, so a core is never under another star's halo.
            g.blendMode = .plusLighter
            for gi in 0..<SkyPlan.groupCount {
                let (ci, step, restless, phase) = SkyPlan.decode(gi)
                let wobble = twinkle(phase: phase, restless: restless, time: f.time, animated: f.animated)
                if !blooms[set][gi].isEmpty {
                    g.fill(blooms[set][gi], with: .color(palette[ci].opacity(0.035 * wobble * fade)))
                }
                if !glows[set][gi].isEmpty {
                    g.fill(glows[set][gi], with: .color(palette[ci].opacity(0.06 * alpha[step] * wobble * fade)))
                }
                if !halos[set][gi].isEmpty {
                    g.fill(halos[set][gi], with: .color(palette[ci].opacity(0.10 * alpha[step] * wobble * fade)))
                }
            }
            if f.spikes {
                for ci in 0..<SkyPlan.colors.count where !glints[set][ci].isEmpty {
                    g.stroke(glints[set][ci], with: .color(palette[ci].mix(with: .white, by: 0.55).opacity(0.5 * fade)),
                             style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                }
            }
            g.blendMode = .normal
            // A focused constellation's dim stars are brought up (`focusLift`); everything else is as it was.
            let lift = lit != nil && set == 1 ? f.focusLift : 0
            for gi in 0..<SkyPlan.groupCount where !paths[set][gi].isEmpty {
                let (ci, step, restless, phase) = SkyPlan.decode(gi)
                let wobble = twinkle(phase: phase, restless: restless, time: f.time, animated: f.animated)
                let base = step >= SkyPlan.dimSteps ? palette[ci].mix(with: .white, by: 0.30 + 0.05 * Double(step - SkyPlan.dimSteps)) : palette[ci]
                let shown = alpha[step] + (1 - alpha[step]) * lift
                g.fill(paths[set][gi], with: .color(base.opacity(min(1, shown * wobble) * fade)))
            }
            for ci in 0..<SkyPlan.colors.count {
                if !rings[set][ci].isEmpty {
                    g.stroke(rings[set][ci], with: .color(palette[ci].opacity((0.55 + 0.45 * lift) * fade)), lineWidth: 1)
                }
                if !crosses[set][ci].isEmpty {
                    g.stroke(crosses[set][ci], with: .color(palette[ci].mix(with: .white, by: 0.4).opacity(0.85 * fade)), lineWidth: 1)
                }
                if !dashes[set][ci].isEmpty {
                    g.stroke(dashes[set][ci], with: .color(.white.opacity(0.5 * fade)),
                             style: StrokeStyle(lineWidth: 0.8, dash: [1.6, 1.6]))
                }
            }
        }

        if let playback, !playback.isDone(at: f.time) { drawPlayback(&g, f, playback, size: size, r0: r0) }
        drawFocus(&g, f, size: size)
        if f.labels { drawLabels(&g, f, size: size) }
    }

    // MARK: Outline sky

    /// Three unlit constellations: hollow rings joined by faint dashed lines, breathing slowly. Drawn when there is
    /// nothing studied yet, so the first screen shows what the sky will become. Positions are shares of the free
    /// rectangle (`top`…`bottom` down the view), the same every time.
    static let outlineShapes: [[(x: Double, y: Double)]] = [
        [(0.10, 0.30), (0.17, 0.12), (0.27, 0.24), (0.31, 0.44), (0.21, 0.58)],
        [(0.47, 0.16), (0.56, 0.34), (0.66, 0.26), (0.62, 0.08), (0.74, 0.46), (0.52, 0.56)],
        [(0.80, 0.18), (0.90, 0.34), (0.84, 0.52), (0.94, 0.66)],
    ]

    static func drawOutline(_ g: inout GraphicsContext, size: CGSize, top: Double, bottom: Double, time: Double, animated: Bool) {
        let free = CGRect(x: 18, y: top, width: size.width - 36, height: max(1, size.height - top - bottom))
        let ring = Color.white.mix(with: CLColor.sky, by: 0.5)
        for (k, shape) in outlineShapes.enumerated() {
            let points = shape.map { CGPoint(x: free.minX + $0.x * free.width, y: free.minY + $0.y * free.height) }
            var lines = Path()
            for (a, b) in zip(points, points.dropFirst()) { lines.move(to: a); lines.addLine(to: b) }
            g.stroke(lines, with: .color(ring.opacity(0.16)), style: StrokeStyle(lineWidth: 0.9, dash: [3, 4]))
            for (i, p) in points.enumerated() {
                let breath = animated ? 0.75 + 0.25 * sin(2 * .pi * (time / 4.2 + Double(k * 5 + i) / 9)) : 1
                let r = i % 3 == 0 ? 4.6 : 3.4
                g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(ring.opacity(0.62 * breath)), lineWidth: 1.1)
            }
        }
    }

    // MARK: Appearance

    /// Core radius by step, as a share of the base radius.
    static let radiusFactor: [Double] = [0.72, 0.78, 0.84, 0.9, 0.98, 1.08, 1.22, 1.42]
    /// Opacity by step: dim stars are faint, bright ones are lit.
    static let alpha: [Double] = [0.20, 0.28, 0.36, 0.46, 0.64, 0.76, 0.88, 1.0]

    /// How much a batch of stars shines at `time`: a slow breath for steady stars, an uneven flutter for restless
    /// ones (fragile memories). Still when nothing animates.
    static func twinkle(phase: Int, restless: Bool, time: Double, animated: Bool) -> Double {
        guard animated else { return restless ? 0.86 : 1 }
        let p = Double(phase) / 3
        if restless {
            let wave = sin(2 * .pi * (time * 1.35 + p) + 1.7 * sin(2 * .pi * time * 0.37))
            return 1 - 0.30 * (0.5 + 0.5 * wave)
        }
        return 1 + 0.07 * sin(2 * .pi * (time / 4.2 + p))
    }

    // MARK: Layers

    /// Which constellations shine when something is focused or lit: just that one, or the ones an exam's region covers.
    /// Nil when nothing is, and every star shines.
    static func litConstellations(_ f: SkyFrame) -> [Bool]? {
        let layout = f.scene.layout
        if let focus = f.focus, layout.constellations.indices.contains(focus) {
            return layout.constellations.indices.map { $0 == focus }
        }
        if let id = f.litRegion, let region = layout.regions.first(where: { $0.examID == id }) {
            let covered = Set(region.covers)
            return layout.constellations.indices.map { covered.contains($0) }
        }
        return nil
    }

    private static func drawRegions(_ g: inout GraphicsContext, _ f: SkyFrame, size: CGSize) {
        for region in f.scene.layout.regions {
            // With one lit, it glows and the others recede.
            let strength = f.litRegion == nil ? 1.0 : (region.examID == f.litRegion ? 2.6 : 0.3)
            let middle = f.camera.screen(region.center, in: size)
            let radius = region.radius * f.camera.scale
            guard radius > 6 else { continue }
            let color = (f.scene.courseColors[region.courseID] ?? .sky).fill
            let rect = CGRect(x: middle.x - radius, y: middle.y - radius, width: 2 * radius, height: 2 * radius)
            guard rect.intersects(CGRect(origin: .zero, size: size)) else { continue }
            let nebula = Gradient(stops: [.init(color: color.opacity(min(1, 0.13 * strength)), location: 0),
                                          .init(color: color.opacity(min(1, 0.07 * strength)), location: 0.7),
                                          .init(color: color.opacity(0), location: 1)])
            g.fill(Path(ellipseIn: rect), with: .radialGradient(nebula, center: middle, startRadius: 0, endRadius: radius))
            g.stroke(Path(ellipseIn: rect), with: .color(color.opacity(min(1, 0.30 * strength))), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
        }
    }

    private static func drawLines(_ g: inout GraphicsContext, _ f: SkyFrame, size: CGSize, lit: [Bool]?, backdrop: Double) {
        let layout = f.scene.layout, light = f.scene.light
        let levels = 5
        // [shines][colour][brightness level]
        var paths = [[[Path]]](repeating: [[Path]](repeating: [Path](repeating: Path(), count: levels), count: SkyPlan.colors.count), count: 2)
        for (index, c) in layout.constellations.enumerated() {
            let ci = SkyPlan.colors.firstIndex(of: f.scene.color(of: c)) ?? 0
            let set = lit.map { $0[index] ? 1 : 0 } ?? 1
            for line in c.lines {
                let m = min(light.brightness[line.a], light.brightness[line.b])
                let level = min(levels - 1, Int(m * Double(levels - 1) + 0.5))
                paths[set][ci][level].move(to: f.camera.screen(layout.stars[line.a].point, in: size))
                paths[set][ci][level].addLine(to: f.camera.screen(layout.stars[line.b].point, in: size))
            }
        }
        for set in 0..<2 {
            for ci in 0..<SkyPlan.colors.count {
                let color = SkyPlan.colors[ci].fill
                for level in 0..<levels where !paths[set][ci][level].isEmpty {
                    // A line is as bright as its dimmer star.
                    var a = 0.07 + 0.33 * Double(level) / Double(levels - 1)
                    if lit != nil, set == 1 { a += (1 - a) * f.focusLift * 0.6 }
                    g.stroke(paths[set][ci][level], with: .color(color.opacity(a * (set == 1 ? 1 : backdrop))), lineWidth: f.lineWidth)
                }
            }
        }
    }

    private static func drawFocus(_ g: inout GraphicsContext, _ f: SkyFrame, size: CGSize) {
        guard let i = f.focus, f.scene.layout.constellations.indices.contains(i) else { return }
        let c = f.scene.layout.constellations[i]
        let middle = f.camera.screen(c.center, in: size)
        let radius = c.radius * f.camera.scale * 0.96
        let turn = f.animated ? f.time * 6 : 0
        g.stroke(Path(ellipseIn: CGRect(x: middle.x - radius, y: middle.y - radius, width: 2 * radius, height: 2 * radius)),
                 with: .color(.white.opacity(0.26)),
                 style: StrokeStyle(lineWidth: 1, dash: [2, 6], dashPhase: turn))
    }

    private static func drawLabels(_ g: inout GraphicsContext, _ f: SkyFrame, size: CGSize) {
        let layout = f.scene.layout
        // The focused constellation is always named; the rest when there is room to read them.
        var shown = 0
        for (i, c) in layout.constellations.enumerated() {
            let focused = f.focus == i
            guard focused || (f.focus == nil && c.radius * f.camera.scale > 62 && shown < 24) else { continue }
            let middle = f.camera.screen(c.center, in: size)
            let y = middle.y - c.radius * f.camera.scale - 6
            guard y > 8, y < size.height else { continue }
            let text = g.resolve(Text(verbatim: c.name).font(.caption.weight(.semibold)).foregroundColor(.white.opacity(focused ? 0.92 : 0.6)))
            g.draw(text, at: CGPoint(x: middle.x, y: y), anchor: .bottom)
            shown += 1
        }
        for region in layout.regions where f.focus == nil {
            let middle = f.camera.screen(region.center, in: size)
            let radius = region.radius * f.camera.scale
            guard radius > 40 else { continue }
            let y = middle.y + radius - 8
            guard y > 8, y < size.height - 8 else { continue }
            let color = (f.scene.courseColors[region.courseID] ?? .sky).fill.mix(with: .white, by: 0.4)
            var text = g.resolve(Text(verbatim: region.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundColor(color.opacity(0.8)))
            text.shading = .color(color.opacity(0.8))
            g.drawLayer { layer in
                layer.addFilter(.shadow(color: f.palette.top.opacity(0.9), radius: 3))
                layer.draw(text, at: CGPoint(x: middle.x, y: y), anchor: .bottom)
            }
        }
    }

    /// The ignition: the star climbs from its old brightness to its new one, a ring opens round it, and a save also
    /// gets a gold ring and a four-point sparkle.
    private static func drawPlayback(_ g: inout GraphicsContext, _ f: SkyFrame, _ playback: SkyPlayback, size: CGSize, r0: Double) {
        let layout = f.scene.layout, light = f.scene.light
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -30, dy: -30)
        for i in layout.stars.indices where playback.isPlaying(i, at: f.time) {
            let star = layout.stars[i]
            let p = f.camera.screen(star.point, in: size)
            guard visible.contains(p) else { continue }
            let t = playback.progress(i, at: f.time)
            let ease = 1 - pow(1 - t, 3)
            let from = playback.relight.from[star.id] ?? 0
            let b = from + (light.brightness[i] - from) * ease
            let c = f.scene.color(of: layout.constellations[star.constellation]).fill
            let lit = playback.relight.lit.contains(star.id)
            let saved = playback.relight.saved.contains(star.id)
            let r = r0 * (0.8 + 0.7 * b) * (1 + 0.7 * sin(.pi * min(1, t * 1.5)))
            if lit, t < 0.25 {
                let ring = r0 * 1.45
                g.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: 2 * ring, height: 2 * ring)),
                         with: .color(c.opacity(0.55 * (1 - t / 0.25))), lineWidth: 1)
            }
            // The glow, then the core.
            g.blendMode = .plusLighter
            let halo = r * 3.4
            g.fill(Path(ellipseIn: CGRect(x: p.x - halo, y: p.y - halo, width: 2 * halo, height: 2 * halo)),
                   with: .color(c.opacity(0.22 * b + 0.2 * sin(.pi * t))))
            g.blendMode = .normal
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                   with: .color(c.mix(with: .white, by: 0.35).opacity(0.3 + 0.7 * b)))
            // The ring that opens and fades.
            let open = r0 * (2.2 + 9 * ease)
            g.stroke(Path(ellipseIn: CGRect(x: p.x - open, y: p.y - open, width: 2 * open, height: 2 * open)),
                     with: .color((saved ? CLColor.sun : c).opacity(0.6 * (1 - t))), lineWidth: saved ? 1.6 : 1)
            if saved {
                let spark = r0 * (3 + 7 * sin(.pi * min(1, t * 1.2)))
                var cross = Path()
                cross.move(to: CGPoint(x: p.x - spark, y: p.y)); cross.addLine(to: CGPoint(x: p.x + spark, y: p.y))
                cross.move(to: CGPoint(x: p.x, y: p.y - spark)); cross.addLine(to: CGPoint(x: p.x, y: p.y + spark))
                g.stroke(cross, with: .color(CLColor.sun.opacity(0.9 * (1 - t * 0.6))), lineWidth: 1.2)
            }
        }
    }
}

#if DEBUG
/// `CRAMLESS_SKY_PERF=1` logs how long drawing a frame takes on the CPU (building the paths and recording the fills;
/// the GPU's part comes after), averaged over 60 frames. Build with `SWIFT_OPTIMIZATION_LEVEL=-O` for real numbers.
enum SkyPerf {
    nonisolated(unsafe) private static var total = Duration.zero
    nonisolated(unsafe) private static var worst = Duration.zero
    nonisolated(unsafe) private static var frames = 0
    private static let on = ProcessInfo.processInfo.environment["CRAMLESS_SKY_PERF"] != nil

    static func record(_ time: Duration, stars: Int) {
        guard on else { return }
        total += time
        worst = max(worst, time)
        frames += 1
        guard frames == 60 else { return }
        let average = Double(total.components.attoseconds) / 1e15 + Double(total.components.seconds) * 1000
        let peak = Double(worst.components.attoseconds) / 1e15 + Double(worst.components.seconds) * 1000
        AppConfig.log.notice("sky frame: \(stars, privacy: .public) stars, average \(average / 60, format: .fixed(precision: 2), privacy: .public) ms, worst \(peak, format: .fixed(precision: 2), privacy: .public) ms over 60 frames")
        total = .zero
        worst = .zero
        frames = 0
    }
}
#endif
