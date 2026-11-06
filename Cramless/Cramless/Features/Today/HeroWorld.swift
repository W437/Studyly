import SwiftUI

/// Today's sky band: your memory sky filling the whole width, background stars behind it, a cloud of colour behind each course,
/// hills and a strip of lake at the foot, and Cap standing on the shore. Tap anywhere on it and the full sky opens (the
/// constellations and their cards live there); with nothing studied yet the outline sky ripples instead. Tilt the phone and the
/// layers move against each other. Tapping Cap makes him answer.
///
/// Pull the page down and the band stays where it is (`TodayView` pins it): the world leans into the pull and, past a line, letting
/// go refreshes it with a flourish of light (`HeroRefresh.swift`).
///
/// - Reduce Motion: no twinkling, no tilt, no shooting stars, no ripples, no leaning; a refresh only brightens the sky for a moment.
///   Low Power Mode: nothing ambient.
/// - Differentiate Without Color: bright stars carry a cross, restless ones a dashed ring (`SkyRenderer`).
/// - VoiceOver: one element, "Your memory sky", which opens the sky (its constellations are listed there).
/// - It runs only while it is on screen and the app is active, at the screen's own rate.
///
/// DEBUG: `CRAMLESS_HERO=3000:x300y160` taps the point (300, 160) that many milliseconds after launch, through the same code as a
/// finger (it opens the sky).
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
    /// There is a sky to open: a tap (or VoiceOver's "Your memory sky" button) opens it.
    let opensSky: Bool
    /// The page's pull, and the refresh it starts.
    let pull: HeroPullModel
    var onOpenSky: () -> Void

    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.clDifferentiateWithoutColor) private var differentiate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.skyTheme) private var skyTheme

    @State private var plan: SkyPlan?
    @State private var clouds: [HeroCloud] = []
    @State private var camera: SkyCamera?
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
    private var needsFrames: Bool { active && (ambientOn || tiltOn || !ripples.isEmpty || refreshing) }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [skyTheme.palette.top, skyTheme.palette.bottom], startPoint: .top, endPoint: .bottom)
            world
            if let cap {
                CapView(cap, size: geometry.capSize, refreshed: capCheer)
                    .environment(\.capSpeaksBeside, geometry.style == .band)
                    .padding(.leading, 6)
                    .padding(.bottom, 2)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .onScrollVisibilityChange(threshold: 0.05) { onScreen = $0 }
        .onAppear {
            clockStart = Date()
            prepare()
            frameSky()
        }
        .onChange(of: scene) { old, new in
            prepare()
            if old.layout != new.layout { frameSky() }
        }
        .onChange(of: pull.finished) { if pull.outcome == .fresh { capCheer += 1 } }
        .onChange(of: viewSize) { frameSky() }
        .onChange(of: geometry) { frameSky() }
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
        // At the screen's own rate (a tilt or a shooting star stepped at 30 a second shudders on a 120 Hz screen), and not at all
        // when nothing moves.
        TimelineView(.animation(minimumInterval: nil, paused: !needsFrames)) { timeline in
            let time = needsFrames ? timeline.date.timeIntervalSince(clockStart) : 0
            // The pull is read here, not in `body`, so a pull redraws the world and nothing else.
            let lean = reduceMotion ? 0 : HeroPull.progress(distance: pull.distance)
            let wave = pull.waveTime(at: timeline.date).map { HeroWorldRenderer.Wave(t: $0, calm: reduceMotion) }
            let armed = pull.phase == .armed
            Canvas { g, size in
                let fit = fitCamera(size)
                HeroWorldRenderer.draw(&g, size: size, frame: HeroWorldRenderer.Frame(
                    scene: scene, plan: plan?.fitting(scene), camera: camera ?? fit, fit: fit, geometry: geometry, mode: mode, time: time,
                    ambient: ambientOn, tilt: currentTilt(at: time), dust: Self.dust, clouds: clouds,
                    differentiate: differentiate, restlessRing: reduceMotion, ripples: ripples, pull: lean, wave: wave, armed: armed,
                    palette: skyTheme.palette))
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

    private func prepare() {
        plan = SkyPlan(scene)
        clouds = HeroCloud.clouds(for: scene)
    }

    /// Frames the whole sky for the band.
    private func frameSky() {
        guard viewSize.width > 1, !scene.isEmpty else { camera = nil; return }
        camera = fitCamera(viewSize)
    }

    // MARK: Taps

    #if DEBUG
    /// `CRAMLESS_HERO=3000:x300y160`: after that many milliseconds, tap the point (300, 160): the path a finger takes, for films.
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
            if what.hasPrefix("x"), let y = what.firstIndex(of: "y"),
               let px = Double(what[what.index(after: what.startIndex)..<y]), let py = Double(what[what.index(after: y)...]) {
                tap(at: CGPoint(x: px, y: py))
            }
        }
    }
    #endif

    /// A tap opens the full sky, where the constellations can be looked at one by one. With nothing to open yet (the outline sky
    /// of the first day), the world answers with a ripple.
    private func tap(at point: CGPoint) {
        let time = Date().timeIntervalSince(clockStart)
        ripple(at: point, time: time)
        if opensSky { onOpenSky() }
    }

    private func ripple(at point: CGPoint, time: Double) {
        guard !reduceMotion else { return }
        ripples.append(HeroWorldRenderer.Ripple(point: point, start: time))
        if ripples.count > 4 { ripples.removeFirst(ripples.count - 4) }
    }
}
