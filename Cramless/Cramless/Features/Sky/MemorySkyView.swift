import SwiftUI

/// The memory sky: one star for every item you've studied, a constellation for every topic. Stars shine while an
/// item is remembered and dim as it fades; a restless star is a fragile memory. Tap a constellation to focus it, drag
/// to look around, pinch to zoom.
///
/// - Reduce Motion: nothing twinkles, the camera cuts instead of gliding, and a relight shows its result.
/// - Differentiate Without Color: bright stars carry a cross and restless ones a dashed ring.
/// - VoiceOver: the sky is a list of constellations (`SkyScreen` also offers the sky as a list).
struct MemorySkyView: View {
    let scene: SkyScene
    /// Changes whenever `scene` does, so the view works out its plan once per scene instead of once per frame.
    let sceneID: Int
    @Binding var focus: Int?
    /// What a finished session did to the sky; the view plays it once when it arrives.
    var relight: SkyRelight = .none
    var interactive = true
    /// Twinkling and the camera's glide. Off for a still, such as a card's preview.
    var animates = true
    /// What the screen's chrome covers at the top and the bottom, so the sky is framed in what's left.
    var insetTop = 0.0
    var insetBottom = 0.0
    var onRelight: (Int) -> Void = { _ in }
    /// Called once the relight has played (or has been skipped), so the owner can clear it.
    var onPlayed: () -> Void = {}

    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.clDifferentiateWithoutColor) private var differentiate
    @Environment(\.scenePhase) private var scenePhase

    @State private var plan: SkyPlan?
    @State private var camera: SkyCamera?
    @State private var move: CameraMove?
    @State private var playback: SkyPlayback?
    @State private var clockStart = Date()
    @State private var viewSize = CGSize.zero
    /// The shape the camera was last framed for; a scene with the same shape (only the light changed) keeps the camera.
    @State private var shape = 0
    @State private var dragFrom: SkyCamera?
    @State private var pinchFrom: SkyCamera?
    @Namespace private var rotor

    struct CameraMove: Equatable {
        var from: SkyCamera
        var to: SkyCamera
        var start: Double
        var duration: Double

        func camera(at time: Double) -> SkyCamera {
            let t = min(1, max(0, (time - start) / max(duration, 0.001)))
            return from.mixed(with: to, 1 - pow(1 - t, 3))
        }
        func isDone(at time: Double) -> Bool { time >= start + duration }
    }

    private var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    private var twinkles: Bool { animates && !reduceMotion && !lowPower && scenePhase == .active }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let fit = SkyCamera.fit(scene.layout, in: size, top: insetTop, bottom: insetBottom)
            ZStack {
                LinearGradient(colors: [SkyRenderer.top, SkyRenderer.bottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                if scene.isEmpty {
                    EmptyView()
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
                        let time = timeline.date.timeIntervalSince(clockStart)
                        Canvas { g, canvasSize in
                            guard let plan else { return }
                            let current = move?.camera(at: time) ?? camera ?? fit
                            SkyRenderer.draw(&g, size: canvasSize, frame: SkyFrame(
                                scene: scene, plan: plan, camera: current, time: time, animated: twinkles,
                                differentiate: differentiate, restlessRing: reduceMotion, focus: focus, playback: playback))
                        }
                    }
                    .gesture(interactive ? dragGesture(size: size, fit: fit) : nil)
                    .simultaneousGesture(interactive ? pinchGesture(size: size, fit: fit) : nil)
                    .simultaneousGesture(interactive ? SpatialTapGesture().onEnded { tap(at: $0.location, size: size, fit: fit) } : nil)
                    accessibilityLayer(size: size, fit: fit)
                }
            }
            .onAppear { clockStart = Date(); viewSize = size; shape = Self.shape(of: scene.layout); prepare(); frame(size: size, fit: fit, animated: false) }
            .onChange(of: sceneID) {
                prepare()
                // Reviewing, a sync or a reload changes the light, not the layout: the camera stays where it is (a person's
                // panning, a focused constellation, a relight's visit). Only a different sky is framed afresh.
                let now = Self.shape(of: scene.layout)
                if now != shape { shape = now; frame(size: size, fit: fit, animated: false) }
            }
            .onChange(of: focus) { frame(size: size, fit: fit, animated: true) }
            .onChange(of: size) { viewSize = size; frame(size: size, fit: fit, animated: false) }
            .task(id: relightKey) { await play() }
        }
        .accessibilityElement(children: .contain)
    }

    /// What the camera is framed for: how many stars and how big the sky is.
    private static func shape(of layout: SkyLayout) -> Int {
        var hasher = Hasher()
        hasher.combine(layout.stars.count)
        hasher.combine(layout.width)
        hasher.combine(layout.height)
        return hasher.finalize()
    }

    private var paused: Bool {
        !(twinkles || move != nil || playback != nil)
    }

    private var relightKey: Int { relight.relit.isEmpty ? 0 : relight.relit.hashValue }

    // MARK: Plan, camera, playback

    private func prepare() {
        plan = SkyPlan(scene)
    }

    /// Puts the camera where the focus says: the whole sky, or the focused constellation.
    private func frame(size: CGSize, fit: SkyCamera, animated: Bool) {
        let layout = scene.layout
        let target: SkyCamera
        if let i = focus, layout.constellations.indices.contains(i) {
            target = SkyCamera.focus(layout.constellations[i], in: size, top: insetTop, bottom: insetBottom)
        } else {
            target = fit
        }
        if animated, animates, !reduceMotion {
            glide(to: target, fit: fit, duration: 0.55)
        } else {
            camera = target
            move = nil
        }
    }

    /// Moves the camera to `target`, gliding. The resting camera is the target from the start; `move` carries the way there.
    private func glide(to target: SkyCamera, fit: SkyCamera, duration: Double) {
        let time = Date().timeIntervalSince(clockStart)
        let current = move?.camera(at: time) ?? camera ?? fit
        camera = target
        move = CameraMove(from: current, to: target, start: time, duration: duration)
        Task {
            try? await nap(Int(duration * 1000) + 60)
            if let m = move, m.isDone(at: Date().timeIntervalSince(clockStart)) { move = nil }
        }
    }

    /// Plays the relight once: the camera glides to the stars that were relit (unless they are spread over most of the
    /// sky, or a constellation is focused), they ignite one after another, and the camera glides back. Reduce Motion
    /// just shows the result.
    private func play() async {
        guard !relight.relit.isEmpty else { playback = nil; return }
        guard !reduceMotion, animates, viewSize.width > 1 else { playback = nil; onPlayed(); return }
        let layout = scene.layout
        let fit = SkyCamera.fit(layout, in: viewSize, top: insetTop, bottom: insetBottom)
        var visited = false
        if focus == nil {
            let points = layout.stars.filter { relight.relit.contains($0.id) }.map(\.point)
            if let visit = SkyCamera.framing(points, padding: 3, in: viewSize, top: insetTop, bottom: insetBottom, comparedTo: fit) {
                glide(to: visit, fit: fit, duration: 0.8)
                visited = true
                try? await nap(900)
            }
        }
        let begin = SkyPlayback(start: Date().timeIntervalSince(clockStart) + (visited ? 0.15 : 0.35), relight: relight, layout: layout)
        playback = begin
        let wait = begin.end - Date().timeIntervalSince(clockStart) + 0.5
        try? await Task.sleep(for: .seconds(max(0, wait)))
        guard !Task.isCancelled else { return }
        playback = nil
        if visited, focus == nil {
            glide(to: fit, fit: fit, duration: 0.8)
            try? await nap(900)
        }
        onPlayed()
    }

    // MARK: Gestures

    private func tap(at point: CGPoint, size: CGSize, fit: SkyCamera) {
        let current = move?.camera(at: Date().timeIntervalSince(clockStart)) ?? camera ?? fit
        let hit = SkyHit.constellation(at: point, camera: current, size: size, layout: scene.layout)
        guard hit != focus else { return }
        CLHaptics.select()
        withAnimation(CLMotion.settle) { focus = hit }
    }

    private func dragGesture(size: CGSize, fit: SkyCamera) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let start = dragFrom ?? (move?.camera(at: Date().timeIntervalSince(clockStart)) ?? camera ?? fit)
                dragFrom = start
                move = nil
                camera = start.panned(by: value.translation).clamped(to: scene.layout)
            }
            .onEnded { _ in dragFrom = nil }
    }

    private func pinchGesture(size: CGSize, fit: SkyCamera) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchFrom ?? (move?.camera(at: Date().timeIntervalSince(clockStart)) ?? camera ?? fit)
                pinchFrom = start
                move = nil
                let anchor = CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height)
                camera = start.zoomed(by: value.magnification, around: anchor, in: size, fit: fit).clamped(to: scene.layout)
            }
            .onEnded { _ in pinchFrom = nil }
    }

    // MARK: VoiceOver

    /// One element per constellation and per exam, over the drawing, so VoiceOver's focus lands where it is drawn.
    private func accessibilityLayer(size: CGSize, fit: SkyCamera) -> some View {
        let current = camera ?? fit
        let layout = scene.layout
        return ZStack(alignment: .topLeading) {
            ForEach(layout.constellations.indices.prefix(80), id: \.self) { i in
                let c = layout.constellations[i]
                let middle = current.screen(c.center, in: size)
                let side = max(44, c.radius * current.scale * 1.4)
                // An offset, not a position: the element's frame is then where the constellation is drawn.
                Color.clear
                    .frame(width: side, height: side)
                    .offset(x: middle.x - side / 2, y: middle.y - side / 2)
                    .accessibilityElement()
                    .accessibilityLabel(SkyCopy.label(i, in: scene))
                    .accessibilityAddTraits(focus == i ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint(Text("Focuses this constellation"))
                    .accessibilityAction { focus = i }
                    .accessibilityAction(named: Text("Relight")) { onRelight(i) }
                    .accessibilityRotorEntry(id: i, in: rotor)
            }
            ForEach(layout.regions) { region in
                let middle = current.screen(region.center, in: size)
                let side = max(44, region.radius * current.scale * 0.5)
                Color.clear
                    .frame(width: side, height: side)
                    .offset(x: middle.x - side / 2, y: middle.y - side / 2)
                    .accessibilityElement()
                    .accessibilityLabel(SkyCopy.examLabel(region, in: scene))
                    .accessibilityRotorEntry(id: region.id, in: rotor)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityRotor("Dim constellations") {
            ForEach(layout.constellations.indices.filter { scene.light.dimCount(layout.constellations[$0]) > 0 }, id: \.self) { i in
                AccessibilityRotorEntry(Text(layout.constellations[i].name), id: i, in: rotor)
            }
        }
        .accessibilityRotor("Exams") {
            ForEach(layout.regions) { region in
                AccessibilityRotorEntry(Text(region.title), id: region.id, in: rotor)
            }
        }
    }
}

// MARK: - A still

/// The sky drawn once, with no gestures or clock: the preview on a card, and what the render tests photograph.
struct SkyStill: View {
    let scene: SkyScene
    var insetTop = 0.0
    var insetBottom = 0.0
    var focus: Int? = nil
    var labels = false
    var differentiate = false

    var body: some View {
        Canvas { g, size in
            let camera = SkyCamera.fit(scene.layout, in: size, top: insetTop, bottom: insetBottom)
            SkyRenderer.draw(&g, size: size, frame: SkyFrame(
                scene: scene, plan: SkyPlan(scene), camera: camera, time: 0, animated: false,
                differentiate: differentiate, focus: focus, playback: nil, labels: labels))
        }
        .background(LinearGradient(colors: [SkyRenderer.top, SkyRenderer.bottom], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }
}
