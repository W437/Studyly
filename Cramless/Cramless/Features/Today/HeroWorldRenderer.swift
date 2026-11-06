import SwiftUI

/// Draws Today's sky band with the layers behind and in front of the memory sky itself: a field of faint background stars,
/// a soft cloud of colour behind each course, the sky (`SkyRenderer`, the same one the full screen uses), a shooting star now
/// and then, and the ground: hills, and a lake (deep enough to mirror the brightest stars only in a tall world, `HeroWorldGeometry.reflects`). Each layer moves a little differently when the
/// phone is tilted, which is what makes it a place and not a picture. Stateless: everything it needs is in the `Frame`.
enum HeroWorldRenderer {
    /// A tap's ring: where, and when (seconds on the animation clock).
    struct Ripple: Equatable {
        var point: CGPoint
        var start: Double
    }

    static let rippleSeconds = 0.9

    /// The refresh's flourish while it runs.
    struct Wave: Equatable {
        /// Seconds since the pull was let go.
        var t: Double
        /// Reduce Motion: the sky only brightens for a moment, and nothing moves.
        var calm: Bool
    }

    struct Frame {
        var scene: SkyScene
        var plan: SkyPlan?
        var camera: SkyCamera
        /// The camera that frames the whole sky, which a zoom or a pan is measured from.
        var fit: SkyCamera
        var geometry: HeroWorldGeometry
        var mode: TodayHeroContent.Sky
        /// Seconds on the animation clock.
        var time: Double
        /// The sky breathes: stars twinkle, a shooting star crosses. Off once there is nothing left to do tonight, under
        /// Reduce Motion and in Low Power Mode.
        var ambient: Bool
        /// The phone's tilt, each -1 to 1, with the idle sway added when there is no motion sensor.
        var tilt: CGPoint
        var dust: HeroDust
        var clouds: [HeroCloud]
        var differentiate: Bool
        var restlessRing: Bool
        var ripples: [Ripple]
        /// The page is pulled down this far (`HeroPull.progress`: 0 at rest, 1 at the line): the layers lean down and the sky
        /// wakes. Always 0 under Reduce Motion.
        var pull = 0.0
        var wave: Wave?
        /// The pull is past the line: letting go refreshes. The far ridge catches the light of the dawn that will follow.
        var armed = false
        /// The sky the person has chosen: what is behind the stars and what the world stands on (`SkyTheme`).
        var palette = SkyPalette.night
    }

    // MARK: The frame
    //
    // Every colour of the world comes from the frame's `palette` (`SkyTheme`): Night is the look Capling has always had.

    static func draw(_ g: inout GraphicsContext, size: CGSize, frame f: Frame) {
        #if DEBUG
        let started = ContinuousClock.now
        defer { HeroPerf.record(ContinuousClock.now - started, stars: f.scene.starCount) }
        #endif
        guard size.width > 1, size.height > 1 else { return }
        drawHorizonGlow(&g, f, size: size)
        drawMilkyWay(&g, f, size: size)
        drawDust(&g, f, size: size)
        drawClouds(&g, f, size: size)
        drawSky(&g, f, size: size)
        drawShootingStar(&g, f, size: size)
        drawRefresh(&g, f, size: size)
        drawGround(&g, f, size: size)
        drawRipples(&g, f)
        drawTopScrim(&g, f, size: size)
    }

    /// How far a layer moves for the tilt: `reach` points at the full tilt, a little less up and down.
    private static func shift(_ f: Frame, _ reach: Double) -> CGSize {
        CGSize(width: f.tilt.x * reach, height: f.tilt.y * reach * 0.55)
    }

    /// How far a layer leans down into a pull (points): `reach` at the line. The ground never leans.
    private static func lean(_ f: Frame, _ reach: Double) -> CGFloat { CGFloat(f.pull * reach) }

    /// Where the refresh's arc of light is (points from the top of the hero) and how strong it is, while it climbs.
    private static func arc(_ f: Frame) -> (y: CGFloat, glow: Double)? {
        guard let wave = f.wave, !wave.calm else { return nil }
        let glow = HeroRefreshWave.glow(at: wave.t)
        guard glow > 0.001 else { return nil }
        let g0 = f.geometry
        let from = g0.farHills, to = g0.skyTop - 50
        return (from + (to - from) * CGFloat(HeroRefreshWave.front(at: wave.t)), glow)
    }

    // MARK: Layers

    /// The dusk the world stands against: violet high up, rose, and a little peach where the far hills begin.
    private static func drawHorizonGlow(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        let g0 = f.geometry
        let top = g0.farHills - g0.glowReach
        let rect = CGRect(x: 0, y: top, width: size.width, height: size.height - top)
        let dawn = 1 + HeroPullLook.dawn * f.pull
        let p = f.palette
        let glow = Gradient(stops: [.init(color: p.glowHigh.opacity(0), location: 0),
                                    .init(color: p.glowHigh.opacity(min(1, 0.20 * dawn)), location: 0.38),
                                    .init(color: p.glowMid.opacity(min(1, 0.22 * dawn)), location: 0.74),
                                    .init(color: p.glowLow.opacity(min(1, 0.34 * dawn)), location: 1)])
        g.blendMode = .plusLighter
        g.fill(Path(rect), with: .linearGradient(glow, startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: g0.farHills + 8)))
        g.blendMode = .normal
    }

    /// A pale band of countless stars across the sky, behind everything: what a very dark night looks like.
    private static func drawMilkyWay(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        let g0 = f.geometry
        guard !g0.compact else { return }
        let move = shift(f, 3.5)
        var band = g
        band.translateBy(x: size.width * 0.52 + move.width,
                         y: g0.skyTop + g0.skyHeight * 0.42 + move.height + lean(f, HeroPullLook.milkyWay))
        band.rotate(by: .degrees(-23))
        band.blendMode = .plusLighter
        let length = size.width * 1.5
        let haze = Gradient(stops: [.init(color: f.palette.haze.opacity(0), location: 0),
                                    .init(color: f.palette.haze.opacity(0.075), location: 0.5),
                                    .init(color: f.palette.haze.opacity(0), location: 1)])
        band.fill(Path(CGRect(x: -length / 2, y: -58, width: length, height: 116)),
                  with: .linearGradient(haze, startPoint: CGPoint(x: 0, y: -58), endPoint: CGPoint(x: 0, y: 58)))
        let warm = Gradient(stops: [.init(color: f.palette.hazeWarm.opacity(0), location: 0),
                                    .init(color: f.palette.hazeWarm.opacity(0.04), location: 0.5),
                                    .init(color: f.palette.hazeWarm.opacity(0), location: 1)])
        band.fill(Path(CGRect(x: -length / 2, y: -22, width: length, height: 44)),
                  with: .linearGradient(warm, startPoint: CGPoint(x: 0, y: -22), endPoint: CGPoint(x: 0, y: 22)))
    }

    private static func drawDust(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        let g0 = f.geometry
        let top = g0.skyTop, height = g0.skyHeight
        // A zoom or a pan moves the nearer layers of dust more than the far ones: the sky changes depth as the camera goes in.
        let pan = CGSize(width: (f.camera.center.x - f.fit.center.x) * f.camera.scale,
                         height: (f.camera.center.y - f.fit.center.y) * f.camera.scale)
        let bounds = CGRect(x: -2, y: -2, width: size.width + 4, height: size.height + 4)
        let wake = 1 + HeroPullLook.wake * f.pull
        let arc = arc(f)
        for mote in f.dust.motes {
            let tilt = shift(f, HeroDust.parallax[mote.depth])
            let follow = HeroDust.zoomFollow[mote.depth]
            let x = -20 + mote.x * (size.width + 40) + tilt.width - pan.width * follow
            let y = top + mote.y * height + tilt.height - pan.height * follow + lean(f, HeroPullLook.dust[mote.depth])
            guard bounds.contains(CGPoint(x: x, y: y)) else { continue }
            let shine = HeroDust.twinkle(mote, time: f.time, animated: f.ambient)
            let color = f.palette.dustCool.mix(with: f.palette.dustWarm, by: mote.warmth)
            // The arc of a refresh lights the stars it is passing.
            let lit = arc.map { $0.glow * HeroRefreshWave.flash(distance: Double(y - $0.y)) } ?? 0
            let r = mote.radius * (1 + 0.7 * lit)
            let a = min(1, mote.alpha * shine * wake * (1 + 2.4 * lit))
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(color.opacity(a)))
            if mote.glints {
                let reach = r * (4.6 + 3 * lit)
                var cross = Path()
                cross.move(to: CGPoint(x: x - reach, y: y)); cross.addLine(to: CGPoint(x: x + reach, y: y))
                cross.move(to: CGPoint(x: x, y: y - reach)); cross.addLine(to: CGPoint(x: x, y: y + reach))
                g.stroke(cross, with: .color(color.opacity(0.55 * a)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                g.fill(Path(ellipseIn: CGRect(x: x - r * 2.6, y: y - r * 2.6, width: r * 5.2, height: r * 5.2)), with: .color(color.opacity(0.10 * a)))
            }
        }
    }

    /// A soft cloud of each course's colour behind its constellations.
    private static func drawClouds(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        guard f.plan != nil, !f.clouds.isEmpty else { return }
        let move = shift(f, 6)
        let down = lean(f, HeroPullLook.clouds)
        g.blendMode = .plusLighter
        for cloud in f.clouds {
            let middle = f.camera.screen(cloud.center, in: size)
            let rx = cloud.radius * f.camera.scale, ry = rx * 0.82
            let rect = CGRect(x: middle.x + move.width - rx, y: middle.y + move.height + down - ry, width: 2 * rx, height: 2 * ry)
            guard rect.intersects(CGRect(origin: .zero, size: size)) else { continue }
            let color = cloud.color.fill
            let body = Gradient(stops: [.init(color: color.opacity(0.20), location: 0),
                                        .init(color: color.opacity(0.10), location: 0.55),
                                        .init(color: color.opacity(0), location: 1)])
            g.fill(Path(ellipseIn: rect), with: .radialGradient(body, center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: rx))
        }
        g.blendMode = .normal
    }

    private static func drawSky(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        paintSky(&g, f, size: size)
        // Pulled down, the sky's own stars glow a little more: it is lit a second time, added.
        if f.pull > 0.02 {
            var wake = g
            wake.blendMode = .plusLighter
            wake.opacity = HeroPullLook.skyGlow * min(1, f.pull)
            wake.drawLayer { layer in paintSky(&layer, f, size: size) }
        }
    }

    /// The sky itself, once: the memory sky, or the outline of constellations waiting to be lit.
    private static func paintSky(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        let g0 = f.geometry
        let move = shift(f, 9)
        if f.mode == .outline || f.scene.isEmpty {
            SkyRenderer.drawOutline(&g, size: size, top: g0.insetTop, bottom: g0.insetBottom, time: f.time, animated: f.ambient)
            return
        }
        guard let plan = f.plan else { return }
        var litRegion: UUID?
        if case .regionLit(let id) = f.mode { litRegion = id }
        // The sky is drawn by the same renderer as the full screen; tilting moves its camera by a few points, and a pull leans it down.
        let scale = f.camera.scale
        let down = lean(f, HeroPullLook.sky)
        let camera = SkyCamera(center: SkyPoint(x: f.camera.center.x - move.width / scale,
                                                y: f.camera.center.y - (move.height + down) / scale), scale: scale)
        SkyRenderer.draw(&g, size: size, frame: SkyFrame(
            scene: f.scene, plan: plan, camera: camera, time: f.time, animated: f.ambient, differentiate: f.differentiate,
            restlessRing: f.restlessRing, focus: nil, litRegion: litRegion, starScale: 1.5, playback: nil, labels: false,
            spikes: true, lineWidth: 1.15, focusLift: 0.42, palette: f.palette))
    }

    private static func drawShootingStar(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        // While the sky is being refreshed one falls on cue, and the ambient ones wait their turn.
        if let wave = f.wave {
            if !wave.calm, let burst = HeroShootingStar.burst(at: wave.t) { drawStreak(&g, f, size: size, streak: burst, bright: 1.3) }
            return
        }
        guard f.ambient, let streak = HeroShootingStar.streak(at: f.time) else { return }
        drawStreak(&g, f, size: size, streak: streak, bright: 1)
    }

    private static func drawStreak(_ g: inout GraphicsContext, _ f: Frame, size: CGSize, streak: HeroShootingStar.Streak, bright: Double) {
        let g0 = f.geometry
        func point(_ p: CGPoint, _ t: Double) -> CGPoint {
            CGPoint(x: (streak.from.x + (streak.to.x - streak.from.x) * t) * size.width,
                    y: g0.skyTop + (streak.from.y + (streak.to.y - streak.from.y) * t) * g0.skyHeight)
        }
        let t = streak.progress
        let head = point(streak.from, t)
        let tail = point(streak.from, max(0, t - 0.28))
        let fade = sin(.pi * t) * bright
        var line = Path()
        line.move(to: tail)
        line.addLine(to: head)
        g.blendMode = .plusLighter
        g.stroke(line, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.85 * fade)]), startPoint: tail, endPoint: head),
                 style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: head.x - 3.2, y: head.y - 3.2, width: 6.4, height: 6.4)), with: .color(.white.opacity(0.9 * fade)))
        g.fill(Path(ellipseIn: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18)), with: .color(CLColor.sky.opacity(0.18 * fade)))
        g.blendMode = .normal
    }

    // MARK: The ground

    private static func drawGround(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        let g0 = f.geometry
        let compact = g0.compact

        // Far hills, with moonlight on their ridge and a low mist where they meet the dusk.
        let farWaves: [(amp: CGFloat, length: CGFloat, phase: CGFloat)] = [(12, 74, 0.8), (6, 33, 2.1), (3, 17, 4.0)]
        var far = g
        let farMove = shift(f, 3)
        far.translateBy(x: farMove.width, y: 0)
        let farShape = hills(width: size.width, height: size.height, base: g0.farHills, waves: farWaves)
        far.fill(farShape.fill, with: .linearGradient(Gradient(colors: [f.palette.farHills.top, f.palette.farHills.bottom]),
                                                       startPoint: CGPoint(x: 0, y: g0.farHills - 20), endPoint: CGPoint(x: 0, y: size.height)))
        if f.armed {
            far.blendMode = .plusLighter
            far.stroke(farShape.crest, with: .color(f.palette.glowLow.opacity(0.24)), lineWidth: 5)
            far.stroke(farShape.crest, with: .color(f.palette.crestWarm.opacity(0.85)), lineWidth: 1.6)
            far.blendMode = .normal
        } else {
            far.stroke(farShape.crest, with: .color(f.palette.crestCool.opacity(0.20)), lineWidth: 1.1)
        }
        let mist = CGRect(x: -40, y: g0.farHills - 6, width: size.width + 80, height: 46)
        far.fill(Path(mist), with: .linearGradient(Gradient(colors: [f.palette.crestCool.opacity(0.0), f.palette.crestCool.opacity(0.10), f.palette.crestCool.opacity(0)]),
                                                   startPoint: CGPoint(x: 0, y: mist.minY), endPoint: CGPoint(x: 0, y: mist.maxY)))

        // Middle hills.
        var mid = g
        let midMove = shift(f, 5)
        mid.translateBy(x: midMove.width, y: 0)
        let midShape = hills(width: size.width, height: size.height, base: g0.midHills,
                             waves: [(9, 58, 2.3), (5, 26, 0.4), (2.5, 13, 5.1)])
        mid.fill(midShape.fill, with: .linearGradient(Gradient(colors: [f.palette.midHills.top, f.palette.midHills.bottom]),
                                                       startPoint: CGPoint(x: 0, y: g0.midHills - 14), endPoint: CGPoint(x: 0, y: size.height)))
        mid.stroke(midShape.crest, with: .color(f.palette.crestCool.opacity(0.11)), lineWidth: 1)

        // The lake, mirroring the brightest stars.
        let lake = CGRect(x: 0, y: g0.lakeTop, width: size.width, height: size.height - g0.lakeTop)
        g.fill(Path(lake), with: .linearGradient(Gradient(colors: [f.palette.water.top, f.palette.water.bottom]),
                                                 startPoint: CGPoint(x: 0, y: lake.minY), endPoint: CGPoint(x: 0, y: lake.maxY)))
        if g0.reflects { drawReflections(&g, f, size: size) }
        // The shore: a thin line of light where the water meets the land.
        var shore = Path()
        shore.move(to: CGPoint(x: 0, y: lake.minY + 0.5))
        shore.addLine(to: CGPoint(x: size.width, y: lake.minY + 0.5))
        g.stroke(shore, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.20), .white.opacity(0)]),
                                              startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)), lineWidth: 1)

        // The ground in front: a low mound where Cap stands, a small one on the other side. They don't move with the tilt:
        // they are the plane of the screen.
        guard !compact else { return }
        let mound = Path(ellipseIn: CGRect(x: -size.width * 0.18, y: size.height - 30, width: size.width * 0.80, height: 80))
        g.fill(mound, with: .linearGradient(Gradient(colors: [f.palette.ground.top, f.palette.ground.bottom]),
                                            startPoint: CGPoint(x: 0, y: size.height - 30), endPoint: CGPoint(x: 0, y: size.height + 20)))
        g.stroke(mound, with: .color(.white.opacity(0.07)), lineWidth: 1)
        let knoll = Path(ellipseIn: CGRect(x: size.width * 0.74, y: size.height - 16, width: size.width * 0.5, height: 56))
        g.fill(knoll, with: .color(f.palette.ground.bottom.opacity(0.9)))
    }

    /// A hill's silhouette: a few sine waves around `base`, filled down to the bottom of the frame, and its crest as a line.
    private static func hills(width: CGFloat, height: CGFloat, base: CGFloat,
                              waves: [(amp: CGFloat, length: CGFloat, phase: CGFloat)]) -> (fill: Path, crest: Path) {
        var fill = Path(), crest = Path()
        let overscan: CGFloat = 40
        fill.move(to: CGPoint(x: -overscan, y: height + 2))
        var x = -overscan
        var first = true
        while x <= width + overscan {
            var y = base
            for wave in waves { y += wave.amp * sin(x / wave.length + wave.phase) }
            fill.addLine(to: CGPoint(x: x, y: y))
            if first { crest.move(to: CGPoint(x: x, y: y)); first = false } else { crest.addLine(to: CGPoint(x: x, y: y)) }
            x += 5
        }
        fill.addLine(to: CGPoint(x: width + overscan, y: height + 2))
        fill.closeSubpath()
        return (fill, crest)
    }

    /// The brightest stars again, flattened into the lake and broken up by ripples: short bright dashes that wander a little,
    /// as light does on water, and a few faint glints of the dusk.
    private static func drawReflections(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        let g0 = f.geometry
        let shore = g0.lakeTop
        let bottom = shore + g0.lakeDepth - 3
        g.blendMode = .plusLighter
        // The dusk's own glints, still: a little light on the water wherever the sky is warm.
        var glints = Path()
        for k in 0..<22 {
            let u = Double((k * 7919) % 101) / 101, v = Double((k * 104_729) % 53) / 53
            let x = CGFloat(u) * size.width
            let y = shore + 4 + CGFloat(v) * (g0.lakeDepth - 10)
            let w = 5 + CGFloat((k * 31) % 11)
            glints.addRect(CGRect(x: x - w / 2 + (f.ambient ? 1.5 * sin(f.time * 0.9 + Double(k)) : 0), y: y, width: w, height: 1))
        }
        g.fill(glints, with: .color(f.palette.glowLow.opacity(0.16)))

        guard let plan = f.plan, !f.scene.isEmpty, f.mode != .outline else { g.blendMode = .normal; return }
        let layout = f.scene.layout
        let move = shift(f, 9)
        let down = lean(f, HeroPullLook.sky)
        let squash = 0.105
        let r0 = min(5.0, max(1.5, f.camera.scale * 0.15)) * 1.5
        var paths = [Path](repeating: Path(), count: SkyPlan.colors.count)
        var drawn = 0
        for i in layout.stars.indices {
            let g16 = plan.group[i]
            guard g16 != SkyPlan.hollow else { continue }
            let (_, step, _, _) = SkyPlan.decode(Int(g16))
            guard step >= 5 else { continue }
            let p = f.camera.screen(layout.stars[i].point, in: size)
            let wander = f.ambient ? 2.2 * sin(f.time * 1.25 + Double(i) * 1.9) : 0
            let x = p.x + move.width + wander
            let y = shore + (shore - (p.y + move.height + down)) * squash
            guard y > shore + 2, y < bottom, x > -8, x < size.width + 8 else { continue }
            let w = r0 * SkyRenderer.radiusFactor[step] * (2.2 + 0.4 * Double(step - 5))
            paths[Int(plan.color[i])].addRect(CGRect(x: x - w, y: y, width: 2 * w, height: 1.3))
            // And a fainter, shorter echo just under it, which is what breaks it into a ripple.
            paths[Int(plan.color[i])].addRect(CGRect(x: x - w * 0.55 - wander * 0.5, y: y + 3.2, width: w * 1.1, height: 1))
            drawn += 1
            if drawn >= 150 { break }
        }
        for ci in 0..<paths.count where !paths[ci].isEmpty {
            g.fill(paths[ci], with: .color(SkyPlan.colors[ci].fill.mix(with: .white, by: 0.35).opacity(0.55)))
        }
        g.blendMode = .normal
    }

    // MARK: The refresh

    /// What letting go of a pull does to the world: an arc of light climbs from behind the hills to above the sky, lighting the
    /// stars as it passes (the sky drawn once more, added, through a soft band; the background stars flash in `drawDust`), and a
    /// star falls (`drawShootingStar`). Under Reduce Motion the sky only brightens for a moment. Drawn before the ground, so the
    /// light comes up from behind the hills.
    private static func drawRefresh(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        guard let wave = f.wave else { return }
        let g0 = f.geometry
        let arcLight = f.palette.arc, peach = f.palette.glowLow, rose = f.palette.glowMid
        if wave.calm {
            let a = HeroRefreshWave.calm(at: wave.t)
            guard a > 0.001 else { return }
            let rect = CGRect(x: 0, y: g0.skyTop - 20, width: size.width, height: g0.farHills - g0.skyTop + 20)
            g.blendMode = .plusLighter
            g.fill(Path(rect), with: .linearGradient(Gradient(colors: [arcLight.opacity(0), arcLight.opacity(0.14 * a), peach.opacity(0.20 * a)]),
                                                     startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            g.blendMode = .normal
            return
        }
        guard let arc = arc(f) else { return }

        // The stars under the arc shine twice as bright: the sky again, added, only where the light is.
        var flash = g
        flash.blendMode = .plusLighter
        flash.opacity = 0.9 * arc.glow
        flash.clipToLayer(opacity: 1) { mask in
            let band = CGRect(x: 0, y: arc.y - 120, width: size.width, height: 240)
            mask.fill(Path(band), with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                                         .init(color: .white, location: 0.5),
                                                                         .init(color: .white.opacity(0), location: 1)]),
                                                       startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))
        }
        flash.drawLayer { layer in paintSky(&layer, f, size: size) }

        // The arc: a dome of light with a soft halo, its crest at `arc.y`, sagging toward the sides like a wave spreading.
        let curve = max(size.width * 1.5, 520)
        let center = CGPoint(x: size.width / 2, y: arc.y + curve)
        let outer = curve + 160
        let core = Gradient(stops: [.init(color: arcLight.opacity(0), location: (curve - 44) / outer),
                                    .init(color: arcLight.opacity(0.27 * arc.glow), location: curve / outer),
                                    .init(color: arcLight.opacity(0), location: (curve + 44) / outer)])
        let halo = Gradient(stops: [.init(color: peach.opacity(0), location: (curve - 160) / outer),
                                    .init(color: peach.opacity(0.11 * arc.glow), location: (curve - 20) / outer),
                                    .init(color: rose.opacity(0), location: 1)])
        let region = Path(CGRect(x: 0, y: 0, width: size.width, height: g0.farHills + 14))
        g.blendMode = .plusLighter
        g.fill(region, with: .radialGradient(halo, center: center, startRadius: 0, endRadius: outer))
        g.fill(region, with: .radialGradient(core, center: center, startRadius: 0, endRadius: outer))
        g.blendMode = .normal
    }

    // MARK: Taps and the top

    private static func drawRipples(_ g: inout GraphicsContext, _ f: Frame) {
        for ripple in f.ripples {
            let t = (f.time - ripple.start) / rippleSeconds
            guard t >= 0, t < 1 else { continue }
            let ease = 1 - pow(1 - t, 3)
            let radius = 7 + 62 * ease
            let p = ripple.point
            g.blendMode = .plusLighter
            g.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)), with: .color(CLColor.sky.opacity(0.28 * (1 - t))))
            g.stroke(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius)),
                     with: .color(.white.opacity(0.5 * (1 - t))), lineWidth: 0.6 + 1.2 * (1 - t))
            g.blendMode = .normal
        }
    }

    /// Night laid over the top of the sky, so the date, the title and the pills stay easy to read over the stars.
    private static func drawTopScrim(_ g: inout GraphicsContext, _ f: Frame, size: CGSize) {
        let g0 = f.geometry
        let reach = g0.topInset + g0.scrimReach
        g.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: reach)),
               with: .linearGradient(Gradient(colors: [f.palette.top.opacity(0.74), f.palette.top.opacity(0.34), f.palette.top.opacity(0)]),
                                     startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: reach)))
    }
}

#if DEBUG
/// `CRAMLESS_SKY_PERF=1` logs how long drawing a whole frame of Today's world takes on the CPU (the sky included), averaged over
/// 60 frames, like `SkyPerf` does for the sky alone. Build with `SWIFT_OPTIMIZATION_LEVEL=-O` for real numbers.
enum HeroPerf {
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
        AppConfig.log.notice("hero frame: \(stars, privacy: .public) stars, average \(average / 60, format: .fixed(precision: 2), privacy: .public) ms, worst \(peak, format: .fixed(precision: 2), privacy: .public) ms over 60 frames")
        total = .zero
        worst = .zero
        frames = 0
    }
}
#endif
