import SwiftUI

/// Today's hero as a world: your memory sky filling the whole width, background stars behind it, a cloud of colour behind each
/// course, hills and a lake at the foot, and Cap standing on the shore, large, in the scene and not beside it. You can tap
/// a constellation and the camera glides to it, with a small card to relight it, all without leaving Today; tap the empty sky
/// and it ripples; the "stars" pill (and VoiceOver) opens the full sky; tilt the phone and the layers move against each other.
/// Tapping Cap makes him answer.
///
/// Pull the page down and the hero stays where it is (`TodayView` pins it): the world leans into the pull and, past a line, letting
/// go refreshes it with a flourish of light (`HeroRefresh.swift`).
///
/// - Reduce Motion: no twinkling, no tilt, no shooting stars, no ripples, no leaning, and the camera cuts; a refresh only brightens
///   the sky for a moment. Low Power Mode: nothing ambient.
/// - Differentiate Without Color: bright stars carry a cross, restless ones a dashed ring (`SkyRenderer`).
/// - VoiceOver: one element, "Your memory sky", which opens the sky (its constellations are listed there).
/// - It runs only while it is on screen and the app is active.
///
/// `HeroWorldGeometry` and the other pure parts are in `HeroWorldModel.swift`; the drawing is `HeroWorldRenderer`.
struct HeroWorld: View {
    let scene: SkyScene
    let mode: TodayHeroContent.Sky
    /// The sky breathes today (false once there is nothing more to do tonight).
    let ambient: Bool
    let geometry: HeroWorldGeometry
    /// Cap's moment, or nil where he steps out (the largest text sizes).
    let cap: CapMoment?
    /// There is a sky to open (VoiceOver's "Your memory sky" button does it).
    let opensSky: Bool
    /// The page's pull, and the refresh it starts.
    let pull: HeroPullModel
    @Binding var focus: Int?
    var onOpenSky: () -> Void
    var onRelight: (Int) -> Void

    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.clDifferentiateWithoutColor) private var differentiate
    @Environment(\.scenePhase) private var scenePhase

    @State private var plan: SkyPlan?
    @State private var clouds: [HeroCloud] = []
    @State private var camera: SkyCamera?
    @State private var move: MemorySkyView.CameraMove?
    @State private var clockStart = Date()
    @State private var onScreen = true
    @State private var viewSize = CGSize.zero
    @State private var tilt = HeroTilt()
    @State private var ripples: [HeroWorldRenderer.Ripple] = []
    @State private var powerTick = 0
    /// Bumped when a refresh has finished well, so Cap reacts.
    @State private var capCheer = 0

    private static let dust = HeroDust.make()
    /// The sky's camera may start this far in (points per star spacing): a small sky grows to fill its room.
    private static let largestFit = 40.0

    // MARK: What runs

    /// Low Power Mode, read afresh whenever it changes (`powerTick` makes the view look again).
    private var lowPower: Bool { _ = powerTick; return ProcessInfo.processInfo.isLowPowerModeEnabled }
    private var ambientOn: Bool { ambient && !reduceMotion && !lowPower }
    private var tiltOn: Bool { !reduceMotion && !lowPower }
    private var active: Bool { scenePhase == .active && onScreen }
    private var refreshing: Bool { pull.phase == .refreshing }
    private var needsFrames: Bool { active && (ambientOn || tiltOn || move != nil || !ripples.isEmpty || refreshing) }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [SkyRenderer.top, SkyRenderer.bottom], startPoint: .top, endPoint: .bottom)
            world
            if let cap {
                CapView(cap, size: geometry.capSize, refreshed: capCheer)
                    .padding(.leading, 2)
                    .padding(.bottom, 16)
                    .opacity(focus == nil ? 1 : 0)
                    .allowsHitTesting(focus == nil)
                    .animation(CLMotion.fade, value: focus == nil)
            }
            if let i = focus, scene.layout.constellations.indices.contains(i) {
                HeroFocusCard(scene: scene, index: i, onRelight: { onRelight(i) },
                              onClose: { withAnimation(CLMotion.settle) { focus = nil } })
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(CLMotion.settle, value: focus)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .onScrollVisibilityChange(threshold: 0.05) { onScreen = $0 }
        .onAppear {
            clockStart = Date()
            prepare()
            frame(animated: false)
        }
        .onChange(of: scene) { old, new in
            prepare()
            if let i = focus, !new.layout.constellations.indices.contains(i) { focus = nil }
            if old.layout != new.layout { frame(animated: false) }
        }
        .onChange(of: focus) { frame(animated: true) }
        .onChange(of: pull.phase) {
            // Looking again at the whole sky: let go of whatever was focused.
            if pull.phase == .refreshing, focus != nil { withAnimation(CLMotion.settle) { focus = nil } }
        }
        .onChange(of: pull.finished) { if pull.outcome == .fresh { capCheer += 1 } }
        .onChange(of: viewSize) { frame(animated: false) }
        .onChange(of: geometry) { frame(animated: false) }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in powerTick &+= 1 }
        #if DEBUG
        .task { await runHooks() }
        #endif
        .task(id: tiltOn && active && HeroTilt.isAvailable) {
            guard tiltOn, active, HeroTilt.isAvailable else { tilt.stop(); return }
            tilt.start()
        }
        .onDisappear { tilt.stop() }
    }

    // MARK: The drawing

    private var world: some View {
        // While the sky is being refreshed it draws as fast as the screen does; otherwise 30 frames a second is plenty.
        TimelineView(.animation(minimumInterval: refreshing ? nil : 1.0 / 30.0, paused: !needsFrames)) { timeline in
            let time = needsFrames ? timeline.date.timeIntervalSince(clockStart) : 0
            // The pull is read here, not in `body`, so a pull redraws the world and nothing else.
            let lean = reduceMotion ? 0 : HeroPull.progress(distance: pull.distance)
            let wave = pull.waveTime(at: timeline.date).map { HeroWorldRenderer.Wave(t: $0, calm: reduceMotion) }
            let armed = pull.phase == .armed
            Canvas { g, size in
                let fit = fitCamera(size)
                let current = move?.camera(at: time) ?? camera ?? fit
                HeroWorldRenderer.draw(&g, size: size, frame: HeroWorldRenderer.Frame(
                    scene: scene, plan: plan, camera: current, fit: fit, geometry: geometry, mode: mode, time: time,
                    ambient: ambientOn, tilt: currentTilt(at: time), dust: Self.dust, clouds: clouds, focus: focus,
                    differentiate: differentiate, restlessRing: reduceMotion, ripples: ripples, pull: lean, wave: wave, armed: armed))
            }
        }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap(at: $0.location) })
        .modifier(WorldAccessibility(scene: scene, opensSky: opensSky, open: onOpenSky, refresh: { pull.refreshNow() }))
        .task(id: ripples.count) {
            guard !ripples.isEmpty else { return }
            try? await Task.sleep(for: .seconds(HeroWorldRenderer.rippleSeconds + 0.1))
            guard !Task.isCancelled else { return }
            let now = Date().timeIntervalSince(clockStart)
            ripples.removeAll { now - $0.start > HeroWorldRenderer.rippleSeconds }
        }
    }

    /// The phone's tilt, or, with no motion sensor, a slow sway that keeps the world from standing still. A still sky (nothing
    /// left to do tonight) stays still unless the phone really moves.
    private func currentTilt(at time: Double) -> CGPoint {
        guard tiltOn else { return .zero }
        if HeroTilt.isAvailable { return CGPoint(x: tilt.box.x, y: tilt.box.y) }
        guard ambient else { return .zero }
        let sway = HeroTilt.idleSway(at: time)
        return CGPoint(x: sway.x, y: sway.y)
    }

    private struct WorldAccessibility: ViewModifier {
        let scene: SkyScene
        let opensSky: Bool
        let open: () -> Void
        let refresh: () -> Void

        func body(content: Content) -> some View {
            if opensSky {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Your memory sky"))
                    .accessibilityValue(Text(SkyCopy.summary(scene)))
                    .accessibilityHint(Text("Opens the sky"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { open() }
                    .accessibilityAction(named: Text("Refresh")) { refresh() }
            } else {
                content.accessibilityHidden(true)
            }
        }
    }

    // MARK: The camera

    private func fitCamera(_ size: CGSize) -> SkyCamera {
        SkyCamera.fit(scene.layout, in: size, top: geometry.insetTop, bottom: geometry.insetBottom, largest: Self.largestFit)
    }

    /// The whole sky, or the focused constellation framed above the card.
    private func targetCamera(_ size: CGSize) -> SkyCamera {
        let layout = scene.layout
        if let i = focus, layout.constellations.indices.contains(i) {
            return SkyCamera.focus(layout.constellations[i], in: size, top: geometry.insetTop,
                                   bottom: geometry.insetBottom + HeroFocusCard.reserved)
        }
        return fitCamera(size)
    }

    private func prepare() {
        plan = SkyPlan(scene)
        clouds = HeroCloud.clouds(for: scene)
    }

    /// Puts the camera where the focus says, gliding there unless Reduce Motion is on.
    private func frame(animated: Bool) {
        guard viewSize.width > 1, !scene.isEmpty else { camera = nil; move = nil; return }
        let target = targetCamera(viewSize)
        guard animated, !reduceMotion else {
            camera = target
            move = nil
            return
        }
        let time = Date().timeIntervalSince(clockStart)
        let current = move?.camera(at: time) ?? camera ?? target
        camera = target
        move = MemorySkyView.CameraMove(from: current, to: target, start: time, duration: 0.6)
        Task {
            try? await nap(660)
            if let m = move, m.isDone(at: Date().timeIntervalSince(clockStart)) { move = nil }
        }
    }

    // MARK: Taps

    #if DEBUG
    /// `CRAMLESS_HERO=3000:c2,9500:close,12000:x300y160`: after that many milliseconds, tap constellation 2's middle star, close
    /// what is focused, tap the point (300, 160): the same paths a finger takes, for films.
    private func runHooks() async {
        guard let raw = TestHarness.once("CRAMLESS_HERO") else { return }
        var elapsed = 0
        for event in raw.split(separator: ",") {
            let parts = event.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let at = Int(parts[0]) else { continue }
            try? await nap(max(0, at - elapsed))
            elapsed = at
            guard !Task.isCancelled else { return }
            let what = parts[1]
            if what == "close" {
                withAnimation(CLMotion.settle) { focus = nil }
            } else if what.hasPrefix("c"), let n = Int(what.dropFirst()), scene.layout.constellations.indices.contains(n), viewSize.width > 1 {
                let c = scene.layout.constellations[n]
                let time = Date().timeIntervalSince(clockStart)
                let now = move?.camera(at: time) ?? camera ?? fitCamera(viewSize)
                // Where it is drawn, tilt included, as a finger would find it.
                let t = currentTilt(at: time)
                let seen = SkyCamera(center: SkyPoint(x: now.center.x - t.x * 9 / now.scale, y: now.center.y - t.y * 9 * 0.55 / now.scale), scale: now.scale)
                if let first = c.stars.first { tap(at: seen.screen(scene.layout.stars[first].point, in: viewSize)) }
            } else if what.hasPrefix("x"), let y = what.firstIndex(of: "y"),
                      let px = Double(what[what.index(after: what.startIndex)..<y]), let py = Double(what[what.index(after: y)...]) {
                tap(at: CGPoint(x: px, y: py))
            }
        }
    }
    #endif

    private func tap(at point: CGPoint) {
        let time = Date().timeIntervalSince(clockStart)
        let fit = fitCamera(viewSize)
        let now = move?.camera(at: time) ?? camera ?? fit
        // The sky is drawn shifted by the tilt; hit-test where it is drawn.
        let t = currentTilt(at: time)
        let scale = now.scale
        let seen = SkyCamera(center: SkyPoint(x: now.center.x - t.x * 9 / scale, y: now.center.y - t.y * 9 * 0.55 / scale), scale: scale)
        if mode != .outline, !scene.isEmpty,
           let hit = SkyHit.nearestStar(at: point, camera: seen, size: viewSize, layout: scene.layout)
            ?? SkyHit.constellation(at: point, camera: seen, size: viewSize, layout: scene.layout) {
            guard hit != focus else { return }
            ripple(at: point, time: time)
            CLHaptics.select()
            withAnimation(CLMotion.settle) { focus = hit }
            return
        }
        // Empty sky: the world answers with a ripple, or lets go of what was focused. (The full sky opens from the pill, and
        // by VoiceOver: a near miss shouldn't throw you out of Today.)
        if focus != nil {
            withAnimation(CLMotion.settle) { focus = nil }
            return
        }
        ripple(at: point, time: time)
    }

    private func ripple(at point: CGPoint, time: Double) {
        guard !reduceMotion else { return }
        ripples.append(HeroWorldRenderer.Ripple(point: point, start: time))
        if ripples.count > 4 { ripples.removeFirst(ripples.count - 4) }
    }
}
