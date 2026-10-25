import SwiftUI

/// The welcome sky as it plays: which stars are lit and when each ignited, the ripples, the finale, and what Cap says. `WelcomeWorld`
/// draws it and sends it touches; `run()` is Cap's part, for a person who doesn't touch anything: he says hello, says to tap one,
/// and then lights one himself, so the welcome finishes either way and never waits for a gesture.
@MainActor
@Observable
final class WelcomeStage {
    private(set) var state = WelcomeSkyState()
    /// Per star: when (seconds on the world's clock) it ignites, negative infinity for lit with no ceremony (Reduce Motion), nil
    /// while it is dark. The finale schedules the rest of the cap a little after the third star, one every `WelcomeLook.sweepGap`.
    private(set) var litAt: [Double?] = Array(repeating: nil, count: WelcomeSky.count)
    private(set) var ripples: [WelcomeSkyDrawing.Ripple] = []
    /// When all of the cap lit (its glow and shooting star start here); nil before the third star.
    private(set) var finaleAt: Double?
    private(set) var speech: CapScriptedLine?
    /// A beat after the cap is lit, when the glow has passed and Cap has said his last line: the words below the sky answer it.
    private(set) var celebrated = false
    /// Cap has said hello: from then on the next star he would light has a ring that opens round it, so it is clear what to touch.
    private(set) var introduced = false
    /// The sky has had its moment and rests: it draws at a slow rate from here (while it is busy it draws at the display's).
    private(set) var resting = false

    /// The cap is lit.
    var isFinished: Bool { state.isFinished }

    /// The star that has the ring: the next of Cap's order, from his hello until the cap is lit.
    var hint: Int? { introduced && !state.isFinished ? state.suggestion : nil }

    @ObservationIgnored private(set) var clockStart = Date()
    @ObservationIgnored private var lines = 0
    @ObservationIgnored private var calm = false
    /// Where the stars are drawn now, so Cap's own touch lands on one; the world keeps it up to date.
    @ObservationIgnored var seen: (camera: SkyCamera, size: CGSize)?

    /// The sounds the welcome can play, warmed at the start so the first touch doesn't stutter.
    static let cues: [CLCue] = [.right(combo: 1), .right(combo: 2), .right(combo: 3), .flourish]

    /// Seconds on the world's clock.
    func time(at date: Date = Date()) -> Double { date.timeIntervalSince(clockStart) }

    /// Reduce Motion: no ripples and no ignition; the stars simply light.
    func setCalm(_ calm: Bool) { self.calm = calm }

    // MARK: Cap's part

    func say(_ text: LocalizedStringResource) {
        lines += 1
        speech = CapScriptedLine(id: lines, text: text)
    }

    /// Hello, "tap one", then a star of his own: whatever the person hasn't done, he does, a beat at a time.
    func run() async {
        guard !state.isFinished else { return }
        guard await rest(WelcomeCopy.introAt) else { return }
        introduced = true
        if state.count == 0 { say(WelcomeCopy.intro) }
        while !state.isFinished {
            let before = state.count
            guard await rest(before == 0 ? WelcomeCopy.hintAfter : WelcomeCopy.nextAfter) else { return }
            guard state.count == before, !state.isFinished else { continue }
            if before == 0 {
                say(WelcomeCopy.hint)
                guard await rest(WelcomeCopy.lightAfter) else { return }
                guard state.count == 0 else { continue }
            }
            if let star = state.suggestion { light(star, byCap: true) }
        }
    }

    private func rest(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    // MARK: Touches

    /// A touch at `point` of the sky drawn with `camera`: the nearest star within reach lights; empty sky ripples.
    func tap(at point: CGPoint, camera: SkyCamera, size: CGSize) {
        if let star = Self.nearestStar(to: point, camera: camera, size: size) {
            light(star, byCap: false, at: point)
        } else {
            ripple(at: point, time: time())
        }
    }

    /// The star nearest `point` within `reach` points, or nil.
    nonisolated static func nearestStar(to point: CGPoint, camera: SkyCamera, size: CGSize, reach: Double = 44) -> Int? {
        var best: (index: Int, distance: Double)?
        for (i, p) in WelcomeSky.points.enumerated() {
            let s = camera.screen(p, in: size)
            let d = ((s.x - point.x) * (s.x - point.x) + (s.y - point.y) * (s.y - point.y)).squareRoot()
            if d <= reach, d < (best?.distance ?? .infinity) { best = (i, d) }
        }
        return best?.index
    }

    /// Lights a star: its sound, its ignition, what Cap says; the third lights the rest and starts the finale.
    func light(_ star: Int, byCap: Bool, at point: CGPoint? = nil) {
        let now = time()
        let outcome = state.light(star)
        let spot = point ?? seen.map { $0.camera.screen(WelcomeSky.points[star], in: $0.size) }
        switch outcome {
        case .ignored:
            if let spot { ripple(at: spot, time: now) }
            return
        case .lit(let star, let count):
            litAt[star] = calm ? -.infinity : now
            CLFeel.play(.right(combo: count))
            say(count == 1 ? WelcomeCopy.first : WelcomeCopy.second)
        case .finale(let star, let rest):
            litAt[star] = calm ? -.infinity : now
            for (k, other) in rest.enumerated() {
                litAt[other] = calm ? -.infinity : now + WelcomeLook.sweepDelay + Double(k) * WelcomeLook.sweepGap
            }
            finaleAt = now + (calm ? 0 : 0.2)
            CLFeel.play([.right(combo: WelcomeSkyState.guided), .flourish])
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(WelcomeCopy.finaleLineAfter))
                guard let self, !Task.isCancelled else { return }
                self.say(WelcomeCopy.finale)
                self.celebrated = true
                try? await Task.sleep(for: .seconds(WelcomeLook.glowSeconds))
                guard !Task.isCancelled else { return }
                self.resting = true
            }
        }
        if let spot { ripple(at: spot, time: now) }
    }

    private func ripple(at point: CGPoint, time: Double) {
        guard !calm else { return }
        ripples.removeAll { time - $0.start > WelcomeLook.rippleSeconds }
        ripples.append(WelcomeSkyDrawing.Ripple(point: point, start: time))
        if ripples.count > 4 { ripples.removeFirst(ripples.count - 4) }
    }

    /// VoiceOver's "Light a star": the next one Cap would.
    func lightNext() {
        guard let star = state.suggestion else { return }
        light(star, byCap: false)
    }

    #if DEBUG
    /// `CRAMLESS_WELCOME=lit1|lit2|lit3`: the sky after that many stars, at once (screenshots).
    func preset(lit count: Int) {
        introduced = true
        for star in WelcomeSky.suggested.prefix(count) { state.light(star) }
        for star in state.lit { litAt[star] = -.infinity }
        switch count {
        case 1: say(WelcomeCopy.first)
        case 2: say(WelcomeCopy.second)
        default: if state.isFinished { say(WelcomeCopy.finale); celebrated = true; resting = true }
        }
    }
    #endif
}
