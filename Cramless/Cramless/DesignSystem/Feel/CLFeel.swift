import SwiftUI

/// A moment's sound and haptic, together: `CLFeel.play(.right(combo: 3))`. The only way to play a cue, so a
/// moment always sounds and feels the same, and each of the two switches (Settings ▸ Accessibility ▸ Sounds,
/// Haptics) is honoured in one place. Plain taps, ticks and page turns stay on `CLHaptics` and make no sound.
@MainActor
enum CLFeel {
    /// A session is about to start: render the sounds and wake both engines.
    static func prepare() {
        CLSound.shared.prepare()
        if CLHaptics.isEnabled { CLHapticPatterns.prepare() }
    }

    /// Warms what a screen is about to play (`prewarm` renders the sounds off the main thread), so its first touch doesn't pay for the
    /// synthesis, the audio engine and the haptic engine while something animates.
    static func prepare(cues: [CLCue]) async {
        await CLSound.shared.prewarm(cues)
        if CLHaptics.isEnabled { CLHapticPatterns.prepare() }
    }

    static func play(_ cue: CLCue) {
        #if DEBUG
        FeelLog.record(cue)
        let started = ContinuousClock.now
        defer { FeelPerf.record(cue, ContinuousClock.now - started) }
        #endif
        CLSound.shared.play(cue)
        if CLHaptics.isEnabled { CLHapticPatterns.play(CLSynth.score(for: cue)) }
    }

    /// Cues one after another, 150 ms apart (a run's note, then its flourish).
    static func play(_ cues: [CLCue]) {
        for (index, cue) in cues.enumerated() {
            if index == 0 {
                play(cue)
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150 * index))
                    play(cue)
                }
            }
        }
    }
}

#if DEBUG
/// `CRAMLESS_FEEL_PERF=1` logs how long each `CLFeel.play` held the main thread ("feel: right1 took 41.2 ms"): the first sound of a
/// launch renders its samples and starts the audio engine, and the first haptic starts its engine, and a screen that animates at
/// that moment stutters unless they were warmed up first (`CLFeel.prepare(cues:)`).
enum FeelPerf {
    private static let on = ProcessInfo.processInfo.environment["CRAMLESS_FEEL_PERF"] == "1"

    static func record(_ cue: CLCue, _ time: Duration) {
        guard on else { return }
        let ms = Double(time.components.attoseconds) / 1e15 + Double(time.components.seconds) * 1000
        AppConfig.log.notice("feel: \(cue.key, privacy: .public) took \(ms, format: .fixed(precision: 1), privacy: .public) ms")
    }
}

/// Every cue played in a harness run, with the wall-clock time, one JSON line each in
/// `Documents/feel-log.jsonl`: `scripts/film.sh` reads it to lay the sounds over a silent simulator recording,
/// aligned frame by frame through the timecode strip (`FilmTimecode`). On in the harness
/// (`CRAMLESS_UITEST=1`) or with `CRAMLESS_FEEL_LOG=1`, even when sounds are muted.
@MainActor
enum FeelLog {
    static let isOn: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["CRAMLESS_UITEST"] == "1" || env["CRAMLESS_FEEL_LOG"] == "1"
    }()

    static var url: URL {
        URL.documentsDirectory.appending(path: "feel-log.jsonl")
    }

    /// Starts a fresh log (each harness launch).
    static func reset() {
        guard isOn else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func record(_ cue: CLCue) { mark(cue.key) }

    /// An event by name (a cue's key).
    static func mark(_ name: String) {
        guard isOn else { return }
        let line = "{\"t\":\(Date().timeIntervalSince1970),\"cue\":\"\(name)\"}\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

/// `CRAMLESS_FILM_SYNC=1` (set by `scripts/film.sh`): a 4-pt strip along the top edge, in a window above every other
/// (so it shows over sheets and covers too), with the wall clock in milliseconds as 32 black and white blocks,
/// repainted on every display refresh (a `CADisplayLink`, so it can't lag the picture the way a throttled SwiftUI
/// timeline can). film.sh reads the time off each frame of the recording and puts every logged sound on the frame
/// it happened (simulator recordings drop and stall under load, so one sync point isn't enough), then crops the
/// strip off.
@MainActor
enum FilmTimecode {
    static let height: CGFloat = 4
    private static var window: UIWindow?

    static func installIfAsked() {
        guard ProcessInfo.processInfo.environment["CRAMLESS_FILM_SYNC"] == "1", window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let strip = UIWindow(windowScene: scene)
        strip.windowLevel = .statusBar + 1
        strip.isUserInteractionEnabled = false
        let controller = UIViewController()
        controller.view = TimecodeStripView(frame: .zero)
        strip.rootViewController = controller
        strip.frame = CGRect(x: 0, y: 0, width: scene.screen.bounds.width, height: height)
        strip.isHidden = false
        window = strip
    }
}

/// The strip itself: 32 layers, set on each display refresh to the bits of the time the frame goes on screen.
final class TimecodeStripView: UIView {
    private var blocks: [CALayer] = []
    private var link: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        for _ in 0..<32 {
            let block = CALayer()
            block.backgroundColor = UIColor.black.cgColor
            layer.addSublayer(block)
            blocks.append(block)
        }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width / CGFloat(blocks.count)
        for (i, block) in blocks.enumerated() {
            block.frame = CGRect(x: CGFloat(i) * width, y: 0, width: width, height: bounds.height)
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let ahead = max(0, link.targetTimestamp - CACurrentMediaTime())
        let ms = UInt64((Date().timeIntervalSince1970 + ahead) * 1000) & 0xFFFF_FFFF
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, block) in blocks.enumerated() {
            let on = (ms >> UInt64(blocks.count - 1 - i)) & 1 == 1
            block.backgroundColor = (on ? UIColor.white : UIColor.black).cgColor
        }
        CATransaction.commit()
    }
}
#endif
