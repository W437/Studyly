import SwiftUI

/// The welcome's world: a still night scenery (`WelcomeBackdrop`: dusk, ridges, the lake), one small constellation, Cap's cap, waiting to
/// be lit, drawn over it (`WelcomeSkyDrawing`), and Cap on the shore beside it. A touch on a star lights it; the third lights the rest.
/// `WelcomeStage` is what happens; this draws it and gives it the touches.
///
/// It is built to stay smooth: the scenery never redraws, the sky is a few dozen plain strokes and fills, and while the person is
/// playing with it it draws at the display's own rate (it rests at 20 frames a second once the cap has had its moment).
struct WelcomeWorld: View {
    let stage: WelcomeStage
    let geometry: HeroWorldGeometry
    let capSize: CGFloat
    /// The welcome is the screen in front: nothing draws, tilts or plays while it is covered.
    var isFront = true

    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var tilt = HeroTilt()
    @State private var stars = WelcomeSkyDrawing.StarCache()
    @State private var viewSize = CGSize.zero
    @State private var onScreen = true
    @State private var powerTick = 0

    /// How far in the camera may go (points per star spacing): the cap is small, and a small sky should still be easy to touch.
    private static let largestFit = 46.0

    private var lowPower: Bool { _ = powerTick; return ProcessInfo.processInfo.isLowPowerModeEnabled }
    private var tiltOn: Bool { !reduceMotion && !lowPower }
    private var active: Bool { scenePhase == .active && onScreen && isFront }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WelcomeBackdrop(geometry: geometry)
            sky
            if isFront { cap }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0; remember() }
        .onScrollVisibilityChange(threshold: 0.05) { onScreen = $0 }
        .onAppear { stage.setCalm(reduceMotion); remember() }
        .onChange(of: reduceMotion) { stage.setCalm(reduceMotion) }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in powerTick &+= 1 }
        .task(id: tiltOn && active && HeroTilt.isAvailable) {
            guard tiltOn, active, HeroTilt.isAvailable else { tilt.stop(); return }
            tilt.start()
        }
        .onDisappear { tilt.stop() }
        #if DEBUG
        .task { await runHooks() }
        #endif
    }

    // MARK: Cap

    /// Cap on the shore, waving; once the cap is lit he cheers. His bubble is the welcome's one instruction.
    private var cap: some View {
        let finished = stage.isFinished
        return CapView(pose: finished ? .celebrate : .wave, size: capSize, motion: finished ? .hop : nil, sparkles: finished,
                       idle: finished ? nil : .breathe, decorative: false, says: stage.speech)
            .padding(.leading, 6)
            .padding(.bottom, 16)
    }

    // MARK: The sky

    private var sky: some View {
        // At the display's rate while it is being played with (a ring that opens or a star that ignites at 30 frames next to a 120 Hz
        // screen reads as lag); at a slow one once it rests, and not at all when nothing is on screen.
        let interval: Double? = stage.resting || reduceMotion ? 1.0 / 20.0 : nil
        return TimelineView(.animation(minimumInterval: interval, paused: !active)) { timeline in
            let time = timeline.date.timeIntervalSince(stage.clockStart)
            Canvas { g, size in
                let t = currentTilt(at: time)
                WelcomeSkyDrawing.draw(&g, size: size, frame: WelcomeSkyDrawing.Frame(
                    time: time, tilt: t, camera: seenCamera(size: size, tilt: t), geometry: geometry, litAt: stage.litAt,
                    hint: stage.hint, ripples: stage.ripples, finaleAt: stage.finaleAt, calm: reduceMotion), stars: stars)
            }
        }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap(at: $0.location) })
        .modifier(WorldAccessibility(stage: stage))
    }

    /// The camera that frames the cap in the free sky, a little higher than the middle: Cap and his bubble have the rest.
    private func fitCamera(_ size: CGSize) -> SkyCamera {
        SkyCamera.fit(WelcomeSky.layout, in: size, top: geometry.insetTop + (geometry.compact ? 0 : 18),
                      bottom: geometry.insetBottom + (geometry.compact ? 0 : capSize * 0.85), largest: Self.largestFit)
    }

    private func currentTilt(at time: Double) -> CGPoint {
        guard tiltOn else { return .zero }
        if HeroTilt.isAvailable { return CGPoint(x: tilt.box.x, y: tilt.box.y) }
        let sway = HeroTilt.idleSway(at: time)
        return CGPoint(x: sway.x, y: sway.y)
    }

    /// The camera the stars are drawn with (the tilt moves the constellation a few points): where a finger finds them.
    private func seenCamera(size: CGSize, tilt t: CGPoint) -> SkyCamera {
        let fit = fitCamera(size)
        let reach = WelcomeLook.tiltReach
        return SkyCamera(center: SkyPoint(x: fit.center.x - t.x * reach / fit.scale, y: fit.center.y - t.y * reach * 0.55 / fit.scale), scale: fit.scale)
    }

    private func remember() {
        guard viewSize.width > 1 else { return }
        stage.seen = (fitCamera(viewSize), viewSize)
    }

    private func tap(at point: CGPoint) {
        stage.tap(at: point, camera: seenCamera(size: viewSize, tilt: currentTilt(at: stage.time())), size: viewSize)
    }

    // MARK: VoiceOver

    /// One element, a button: it says what the sky is and how far it is lit, and its action lights the next star.
    private struct WorldAccessibility: ViewModifier {
        let stage: WelcomeStage

        func body(content: Content) -> some View {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("A night sky with a constellation shaped like Cap's graduation cap"))
                .accessibilityValue(Text("\(min(stage.state.count, WelcomeSkyState.guided)) of \(WelcomeSkyState.guided) stars lit"))
                .accessibilityHint(Text("Lights a star"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { stage.lightNext() }
                .accessibilityAction(named: Text("Light a star")) { stage.lightNext() }
        }
    }

    #if DEBUG
    /// `CRAMLESS_WELCOME=lit2` shows the sky after two stars at once; `CRAMLESS_WELCOME=2600:s1,4400:s4,6400:s0` taps those stars
    /// (by index) at those milliseconds after the world appears: the same path a finger takes, for films.
    private func runHooks() async {
        // Read every time, not consumed: the welcome can be built more than once as the harness sets the app up, and the one on screen
        // must get the script.
        guard let raw = TestHarness.value("CRAMLESS_WELCOME") else { return }
        if raw.hasPrefix("lit"), let n = Int(raw.dropFirst(3)) {
            stage.preset(lit: n)
            return
        }
        var elapsed = 0
        for event in raw.split(separator: ",") {
            let parts = event.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let at = Int(parts[0]), parts[1].hasPrefix("s"), let star = Int(parts[1].dropFirst()),
                  WelcomeSky.points.indices.contains(star) else { continue }
            try? await nap(max(0, at - elapsed))
            elapsed = at
            guard !Task.isCancelled, viewSize.width > 1 else { return }
            let camera = seenCamera(size: viewSize, tilt: currentTilt(at: stage.time()))
            stage.tap(at: camera.screen(WelcomeSky.points[star], in: viewSize), camera: camera, size: viewSize)
        }
    }
    #endif
}
